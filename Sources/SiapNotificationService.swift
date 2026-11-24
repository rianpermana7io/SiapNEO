import Foundation
import UIKit
import UserNotifications
import BackgroundTasks

extension Notification.Name {
    static let siapBackgroundDocsFetched = Notification.Name("siapneo_background_docs_fetched")
}

// MARK: - WhatsApp Template Helper (1:1 Port of Android WaTemplates)

enum SiapWaMessageHelper {
    static func normalizeTpsForWa(_ rawTps: String) -> String {
        let trimmed = rawTps.trimmingCharacters(in: .whitespacesAndNewlines)
        let up = trimmed.uppercased()
        if up.contains("GSRA") || up.contains("JICT") || up.contains("KOJA") {
            return "Graha"
        }
        if up.contains("NCT1") || up.contains("NPCT") || up.contains("NPCT1") {
            return "NPCT"
        }
        return trimmed
    }

    static func currentWibGreeting(date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current
        let hour = cal.component(.hour, from: date)
        switch hour {
        case 4..<11: return "Pagi"
        case 11..<15: return "Siang"
        case 15..<19: return "Sore"
        default: return "Malam"
        }
    }

    static func cleanField(_ raw: String, fallback: String = "") -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "-" || s.lowercased() == "null" {
            return fallback
        }
        return s
    }

    /// Exact port of Android WaTemplates.DEFAULT_PIC:
    /// "{salam}, saya Pemeriksa BC, dapat IP No {pib} ({importir}) di {tps}. Sudah bisa diperiksa sekarang?"
    static func renderDefaultPjMessage(for pib: PibDocument) -> String {
        let salam = currentWibGreeting()
        let noPib = cleanField(pib.noPib)
        let importir = cleanField(pib.importir)
        let tpsRaw = cleanField(pib.kodeTps)
        let tps = tpsRaw.isEmpty ? "" : normalizeTpsForWa(tpsRaw)

        var msg = "\(salam), saya Pemeriksa BC, dapat IP No \(noPib)"
        if !importir.isEmpty {
            msg += " (\(importir))"
        }
        if !tps.isEmpty {
            msg += " di \(tps)"
        }
        msg += ". Sudah bisa diperiksa sekarang?"
        return msg
    }
}

// MARK: - Thread-Safe Seen Document Store (1:1 Port of Android SessionManager.processNewNotifiedDocs)

actor NotifiedDocStore {
    static let shared = NotifiedDocStore()

    private let maxNotifiedDocKeys = 500
    private let keysStoreKey = "siapneo_ios_notified_doc_keys_v1"
    private let nipStoreKey = "siapneo_ios_notified_doc_nip_v1"

    /// Serialized diff against previously seen documents for `nip`.
    /// - On first run (no baseline stored for this NIP): seeds baseline cleanly and returns `[]` so old docs never spam.
    /// - On subsequent runs: records newly arrived doc keys (capped at 500) and returns newly arrived docs if `canNotify == true`.
    func process(docs: [PibDocument], nip: String, canNotify: Bool) -> [PibDocument] {
        let cleanNip = nip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNip.isEmpty else { return [] }

        var batchSeen = Set<String>()
        var uniquePairs: [(doc: PibDocument, key: String)] = []
        for doc in docs {
            let key = doc.clientIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, batchSeen.insert(key).inserted else { continue }
            uniquePairs.append((doc, key))
        }

        let defaults = UserDefaults.standard
        let savedNip = defaults.string(forKey: nipStoreKey)
        let savedKeys = defaults.stringArray(forKey: keysStoreKey)

        // First-run baseline seeding (mirrors Android SessionManager.getNotifiedDocKeysOrderedOrNull() == null)
        if savedNip != cleanNip || savedKeys == nil {
            let seeded = Array(uniquePairs.map(\.key).suffix(maxNotifiedDocKeys))
            defaults.set(cleanNip, forKey: nipStoreKey)
            defaults.set(seeded, forKey: keysStoreKey)
            return []
        }

        var ordered = savedKeys ?? []
        var knownSet = Set(ordered)
        var newDocs: [PibDocument] = []

        for pair in uniquePairs {
            if !knownSet.contains(pair.key) {
                knownSet.insert(pair.key)
                ordered.append(pair.key)
                newDocs.append(pair.doc)
            }
        }

        if !newDocs.isEmpty {
            if ordered.count > maxNotifiedDocKeys {
                ordered = Array(ordered.suffix(maxNotifiedDocKeys))
            }
            defaults.set(ordered, forKey: keysStoreKey)
        }

        return canNotify ? newDocs : []
    }

    func clearBaseline() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: keysStoreKey)
        defaults.removeObject(forKey: nipStoreKey)
    }

    func trackedCount() -> Int {
        UserDefaults.standard.stringArray(forKey: keysStoreKey)?.count ?? 0
    }
}

// MARK: - Native iOS Notification & Background Refresh Manager (1:1 Android NotificationHelper + NewDocCheckWorker)

@MainActor
final class SiapNotificationManager: NSObject, ObservableObject {
    static let shared = SiapNotificationManager()

    nonisolated static let bgRefreshTaskId = "com.kemenkeu.bcpriok.siapneo.ios.newdoccheck"
    nonisolated static let categoryWithPj = "SIAP_NEW_PIB_WITH_PJ"
    nonisolated static let categoryNoPj = "SIAP_NEW_PIB_NO_PJ"
    nonisolated static let actionOpenPib = "SIAP_ACTION_OPEN_PIB"
    nonisolated static let actionHubPj = "SIAP_ACTION_HUB_PJ"

    static let foregroundPollIntervalNs: UInt64 = 25_000_000_000 // 25s (exact Android HomeViewModel)
    static let resumeMinGapSeconds: TimeInterval = 5.0           // 5s (exact Android HomeViewModel)
    static let backgroundRefreshInterval: TimeInterval = 15 * 60 // 15m (exact Android NewDocCheckWorker)

    private static let enabledKey = "siapneo_ios_notif_enabled"
    private static let sessionKey = "siapneo_ios_session_v2"
    private static let lastCheckTsKey = "siapneo_ios_notif_last_check_ts"
    private static let lastBgCheckTsKey = "siapneo_ios_notif_last_bg_check_ts"

    @Published var isNotificationEnabled: Bool
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
    @Published var pendingOpenRequest: NotificationOpenRequest?
    @Published var lastCheckDisplay: String = ""
    @Published var lastBackgroundCheckDisplay: String = ""
    @Published var unreadCount: Int = 0

    var isSystemPermissionGranted: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    var isPermissionDenied: Bool {
        authorizationStatus == .denied
    }

    var isBackgroundRefreshAvailable: Bool {
        backgroundRefreshStatus == .available
    }

    var permissionBadgeLabel: String {
        if !isNotificationEnabled { return "DIBISUKAN" }
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "AKTIF"
        case .denied:
            return "IZIN DITOLAK"
        case .notDetermined:
            return "PERLU IZIN"
        @unknown default:
            return "AKTIF"
        }
    }

    private override init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            self.isNotificationEnabled = true
        } else {
            self.isNotificationEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        super.init()

        let lastTs = UserDefaults.standard.double(forKey: Self.lastCheckTsKey)
        if lastTs > 0 {
            self.lastCheckDisplay = Self.formatWibTime(Date(timeIntervalSince1970: lastTs))
        }
        let lastBgTs = UserDefaults.standard.double(forKey: Self.lastBgCheckTsKey)
        if lastBgTs > 0 {
            self.lastBackgroundCheckDisplay = Self.formatWibTime(Date(timeIntervalSince1970: lastBgTs))
        }
    }

    private static func formatWibTime(_ date: Date) -> String {
        SiapCrypto.wibFormatter("HH:mm").string(from: date) + " WIB"
    }

    // MARK: - Setup & Registration (Called in AppDelegate.didFinishLaunching)

    nonisolated func registerCategories() {
        let openPibAction = UNNotificationAction(
            identifier: Self.actionOpenPib,
            title: "Buka PIB",
            options: [.foreground]
        )
        let hubPjAction = UNNotificationAction(
            identifier: Self.actionHubPj,
            title: "Hubungi PJ",
            options: [.foreground]
        )

        let catWithPj = UNNotificationCategory(
            identifier: Self.categoryWithPj,
            actions: [openPibAction, hubPjAction],
            intentIdentifiers: [],
            options: []
        )
        let catNoPj = UNNotificationCategory(
            identifier: Self.categoryNoPj,
            actions: [openPibAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([catWithPj, catNoPj])
    }

    nonisolated func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgRefreshTaskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.executeBackgroundRefreshTask(refreshTask)
        }
    }

    nonisolated private static func executeBackgroundRefreshTask(_ task: BGAppRefreshTask) {
        let workTask = Task {
            await SiapNotificationManager.shared.scheduleBackgroundRefresh()
            let result = await SiapNotificationManager.shared.performBackgroundCheck()
            task.setTaskCompleted(success: result.success)
        }

        task.expirationHandler = {
            workTask.cancel()
        }
    }

    // MARK: - Scheduling Background Refresh

    func scheduleBackgroundRefresh() {
        guard isNotificationEnabled, Self.loadSavedSession() != nil else {
            cancelBackgroundRefresh()
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.backgroundRefreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Silently ignored on simulator or when Background App Refresh is disabled
        }
    }

    func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgRefreshTaskId)
    }

    // MARK: - Permissions & Settings

    func refreshSystemStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
    }

    func requestPermissionOnLaunchIfNeeded() async {
        await refreshSystemStatus()
        guard isNotificationEnabled else { return }
        if authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshSystemStatus()
        }
    }

    func requestPermissionExplicitly() async -> Bool {
        await refreshSystemStatus()
        if authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshSystemStatus()
        }
        return isSystemPermissionGranted
    }

    func setNotificationEnabled(_ enabled: Bool) async {
        isNotificationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            let granted = await requestPermissionExplicitly()
            if granted {
                scheduleBackgroundRefresh()
            }
        } else {
            cancelBackgroundRefresh()
        }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        openAppSettings()
    }

    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func clearBadge() async {
        unreadCount = 0
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func onLogout() async {
        cancelBackgroundRefresh()
        await NotifiedDocStore.shared.clearBaseline()
        await clearBadge()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - Document Processing & Notification Delivery

    private static func loadSavedSession() -> UserSession? {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionKey),
              let saved = try? JSONDecoder().decode(UserSession.self, from: data),
              !saved.nip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return saved
    }

    /// Processes a freshly fetched list of PIB documents (from foreground poll, manual refresh, or background refresh).
    /// Returns the number of new notifications posted.
    @discardableResult
    func handleFetchedDocuments(_ docs: [PibDocument], nip: String, isBackground: Bool = false) async -> Int {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastCheckTsKey)
        lastCheckDisplay = Self.formatWibTime(now)
        if isBackground {
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastBgCheckTsKey)
            lastBackgroundCheckDisplay = Self.formatWibTime(now)
        }

        await refreshSystemStatus()
        let canNotify = isNotificationEnabled && isSystemPermissionGranted

        let newDocs = await NotifiedDocStore.shared.process(docs: docs, nip: nip, canNotify: canNotify)
        guard !newDocs.isEmpty else { return 0 }

        let shouldBadge = isBackground || UIApplication.shared.applicationState != .active
        for doc in newDocs {
            if shouldBadge {
                unreadCount += 1
            }
            await postNewPibNotification(doc, isTest: false, badgeNumber: shouldBadge ? unreadCount : nil)
        }
        return newDocs.count
    }

    /// Standalone check invoked by BGAppRefreshTask / legacy background fetch (works even if UI hasn't mounted).
    func performBackgroundCheck() async -> (success: Bool, foundNew: Int) {
        guard isNotificationEnabled, let sess = Self.loadSavedSession() else {
            return (true, 0)
        }
        do {
            let fetched = try await SiapApiClient.shared.fetchHomescreen(nip: sess.nip)
            let count = await handleFetchedDocuments(fetched, nip: sess.nip, isBackground: true)
            NotificationCenter.default.post(name: .siapBackgroundDocsFetched, object: fetched)
            return (true, count)
        } catch {
            return (false, 0)
        }
    }

    /// Exact iOS port of Android NotificationHelper.showNewPibNotification(context, pib)
    func postNewPibNotification(_ pib: PibDocument, isTest: Bool = false, badgeNumber: Int? = nil) async {
        let waktuIp = SiapWaMessageHelper.cleanField(pib.ipCeisa, fallback: "-")
        let containerType = pib.cleanedContainerType
        let containerSuffix = containerType.isEmpty ? "" : " • \(containerType)"
        let cleanImportir = SiapWaMessageHelper.cleanField(pib.importir, fallback: "-")
        let tps = pib.tpsCardText

        let content = UNMutableNotificationContent()
        content.title = isTest ? "[TES] Instruksi Pemeriksaan Baru" : "Instruksi Pemeriksaan Baru"
        content.subtitle = "Waktu Penunjukan \(waktuIp)\(containerSuffix)"

        var bodyLines: [String] = []
        bodyLines.append("\(pib.noPib) tanggal \(pib.tglPibFormatted)\(containerSuffix)")
        bodyLines.append(cleanImportir)
        if !containerType.isEmpty {
            bodyLines.append("Jenis: \(containerType) • TPS: \(tps)")
        } else if tps != "-" {
            bodyLines.append("TPS: \(tps)")
        }
        bodyLines.append("PFPD: \(pib.pfpdCardText)")
        bodyLines.append("PJ: \(pib.cleanedNamaPj)")
        content.body = bodyLines.joined(separator: "\n")

        content.sound = .default
        content.threadIdentifier = "siap_document_channel"
        content.categoryIdentifier = pib.hasPhonePj ? Self.categoryWithPj : Self.categoryNoPj
        if let badgeNumber, badgeNumber > 0 {
            content.badge = NSNumber(value: badgeNumber)
        }

        let waMsg = SiapWaMessageHelper.renderDefaultPjMessage(for: pib)
        var userInfo: [String: Any] = [
            "kode_tiket": pib.kodeTiket,
            "no_pib": pib.noPib,
            "hp_pj": pib.hpPj,
            "wa_message": waMsg,
            "is_test": isTest
        ]
        if let encoded = try? JSONEncoder().encode(pib),
           let jsonStr = String(data: encoded, encoding: .utf8) {
            userInfo["pib_json"] = jsonStr
        }
        content.userInfo = userInfo

        let notifId = isTest
            ? "siap_pib_test_\(UUID().uuidString)"
            : "siap_pib_\(SiapCrypto.sanitizeToken(pib.clientIdentityKey))"

        let request = UNNotificationRequest(identifier: notifId, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func sendTestNotification(samplePib: PibDocument?) async -> Bool {
        let granted = await requestPermissionExplicitly()
        guard granted else { return false }

        let target: PibDocument
        if let samplePib {
            target = samplePib
        } else {
            let todayStr = SiapCrypto.wibFormatter("yyyy-MM-dd").string(from: Date())
            let nowIp = SiapCrypto.wibFormatter("dd-MM-yyyy HH:mm").string(from: Date())
            target = PibDocument(
                kodeTiket: "DEMO-NOTIF-001",
                noPib: "123456",
                tglPib: todayStr,
                jenisDokumen: "PIB",
                importir: "PT CONTOH IMPORTIR NUSANTARA",
                kodeTps: "GSRA",
                jenisKontainer: "FCL",
                ipCeisa: nowIp,
                namaPfpd: "PFPD Penguji",
                noHpPfpd: "",
                atensi: "",
                namaPj: "Pengurus Contoh",
                hpPj: "081234567890",
                nomorBap: "",
                tglBap: "-",
                persentasePeriksa: "30%",
                status: "Siap Periksa",
                jumlahItem: "5",
                barcon: "-",
                pendampingan: "-",
                bidangPendamping: "-",
                namaPendamping: "-",
                kendala: "-",
                cluster: "GRAHA"
            )
        }

        await postNewPibNotification(target, isTest: true)
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension SiapNotificationManager: UNUserNotificationCenterDelegate {
    /// Show notification banner + sound even while SIAP NEO is open in foreground (matches Android heads-up alert).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// Handle tap on notification banner, "Buka PIB" action, or "Hubungi PJ" WhatsApp action.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        let kodeTiket = (userInfo["kode_tiket"] as? String) ?? ""
        let noPib = (userInfo["no_pib"] as? String) ?? ""
        let hpPj = (userInfo["hp_pj"] as? String) ?? ""
        let waMessage = (userInfo["wa_message"] as? String) ?? ""

        var decodedPib: PibDocument? = nil
        if let jsonStr = userInfo["pib_json"] as? String,
           let data = jsonStr.data(using: .utf8) {
            decodedPib = try? JSONDecoder().decode(PibDocument.self, from: data)
        }

        let openReq: NotificationOpenRequest?
        if actionId == Self.actionHubPj {
            openReq = NotificationOpenRequest(
                kodeTiket: kodeTiket,
                noPib: noPib,
                openPibDocument: false,
                pib: decodedPib,
                hubPjPhone: hpPj,
                hubPjMessage: waMessage
            )
        } else if actionId == Self.actionOpenPib {
            openReq = NotificationOpenRequest(
                kodeTiket: kodeTiket,
                noPib: noPib,
                openPibDocument: true,
                pib: decodedPib,
                hubPjPhone: nil,
                hubPjMessage: nil
            )
        } else if actionId == UNNotificationDefaultActionIdentifier {
            openReq = NotificationOpenRequest(
                kodeTiket: kodeTiket,
                noPib: noPib,
                openPibDocument: false,
                pib: decodedPib,
                hubPjPhone: nil,
                hubPjMessage: nil
            )
        } else {
            openReq = nil
        }

        if let openReq {
            Task { @MainActor in
                SiapNotificationManager.shared.pendingOpenRequest = openReq
            }
        }
        completionHandler()
    }
}
