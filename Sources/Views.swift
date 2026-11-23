import SwiftUI
import UIKit

// MARK: - Upload Navigation Context

struct UploadFotoContext: Equatable {
    let pib: PibDocument
    let nokon: String
    let containers: [ContainerItem]
}

struct BarconFormTarget: Identifiable {
    let id = UUID()
    let pib: PibDocument
    let isKendalaTemuan: Bool
    var title: String { isKendalaTemuan ? "Kendala / Temuan Pemeriksaan" : "Aju Barcon" }
    var formUrl: URL {
        let formId = isKendalaTemuan
            ? "1FAIpQLSekG2MQzmbuTxR8d2CRs-QjqDoipBn8CRK2ptGRGv2jZqAZ0Q"
            : "1FAIpQLSfqSZrmToIvHdus4wQ_8JNGY50MEjIkZirqM2CSbdVdIQ0zHA"
        return URL(string: "https://docs.google.com/forms/d/e/\(formId)/viewform")!
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var session: UserSession?
    @Published var pibs: [PibDocument] = []
    @Published var lorongItems: [InstruksiLorongItem] = []
    @Published var assignedIps: [AssignedIpItem] = []
    @Published var isLoadingPibs = false
    @Published var isLoadingLorong = false
    @Published var isLoadingAssignedIps = false
    @Published var lastPibError: String?
    @Published var assignedIpError: String?
    @Published var assignedIpTotal = 0
    @Published var assignedIpHasMore = false
    @Published var lastUpdatedText: String = ""
    @Published var toastMessage: String?

    // Navigation state (Matches Android ScreenHome / HomeSubView)
    @Published var activeTab: SiapBottomTab = .beranda
    @Published var selectedPib: PibDocument?
    @Published var activeUploadContext: UploadFotoContext?
    @Published var activeDokap: DokapTarget?
    @Published var showManualSheet = false
    @Published var showRedistSheet = false
    @Published var showHoldSheet = false
    @Published var redistHistory: [RedistHistoryItem] = []
    @Published var holdHistory: [HoldHistoryItem] = []
    @Published var pendingBrowseQuery: String?
    @Published var pendingBrowseAutoExpand = false
    @Published var browseReturnToTps = false
    @Published var availableUpdate: AppUpdateInfo?
    @Published var showUpdatePromptSheet = false
    @Published var isCheckingUpdate = false
    @Published var lastUpdateCheckText: String = ""
    @Published var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: autoCheckUpdatesKey) }
    }
    @Published var barconSheetTarget: BarconFormTarget?
    @Published var submittedBarconKeys: Set<String> = []

    // Theme & UI Density (Matches Android ThemeState)
    @Published var themeMode: SiapThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: themeModeKey) }
    }
    @Published var uiDensity: SiapUiDensity {
        didSet { UserDefaults.standard.set(uiDensity.rawValue, forKey: densityKey) }
    }

    private let sessionKey = "siapneo_ios_session_v2"
    private let rememberedUserKey = "siapneo_ios_remembered_user"
    private let themeModeKey = "siapneo_ios_theme_mode"
    private let densityKey = "siapneo_ios_ui_density"
    private let autoCheckUpdatesKey = "siapneo_ios_auto_check_updates"
    private let snoozedUpdateBuildKey = "siapneo_ios_snoozed_update_build"
    private let lastRunBuildKey = "siapneo_ios_last_run_build"
    private var lastAutoCheckAt: Date = .distantPast

    var rememberedUsername: String {
        get { UserDefaults.standard.string(forKey: rememberedUserKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: rememberedUserKey) }
    }

    var isCompact: Bool { uiDensity == .compactPro }

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "siapneo_ios_theme_mode") ?? "system"
        self.themeMode = SiapThemeMode(rawValue: savedTheme) ?? .system
        let savedDensity = UserDefaults.standard.string(forKey: "siapneo_ios_ui_density") ?? "STANDARD"
        self.uiDensity = SiapUiDensity(rawValue: savedDensity) ?? .standard
        if UserDefaults.standard.object(forKey: "siapneo_ios_auto_check_updates") == nil {
            self.autoCheckUpdates = true
        } else {
            self.autoCheckUpdates = UserDefaults.standard.bool(forKey: "siapneo_ios_auto_check_updates")
        }
        let savedBarcons = UserDefaults.standard.stringArray(forKey: "siapneo_submitted_barcons") ?? []
        self.submittedBarconKeys = Set(savedBarcons)

        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let saved = try? JSONDecoder().decode(UserSession.self, from: data),
           !saved.nip.isEmpty {
            self.session = saved
        }

        let prevBuild = UserDefaults.standard.integer(forKey: lastRunBuildKey)
        let nowBuild = Int((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "147") ?? 147
        if prevBuild > 0 && nowBuild > prevBuild {
            let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.19.7"
            self.toastMessage = "SIAP NEO berhasil diperbarui ke v\(ver)!"
        }
        UserDefaults.standard.set(nowBuild, forKey: lastRunBuildKey)
    }

    func navigateBack() {
        if activeDokap != nil {
            activeDokap = nil
        } else if activeUploadContext != nil {
            activeUploadContext = nil
        } else if selectedPib != nil {
            selectedPib = nil
        }
    }

    func openPib(_ pib: PibDocument) {
        activeDokap = nil
        activeUploadContext = nil
        selectedPib = pib
    }

    func openUpload(pib: PibDocument, nokon: String, containers: [ContainerItem]) {
        activeUploadContext = UploadFotoContext(pib: pib, nokon: nokon, containers: containers)
    }

    /// Exact port of Android HomeViewModel.openPibByNumber + searchPibInBrowse from Monitoring TPS
    func openPibFromTps(noPib: String, fallbackQuery: String) {
        let digits = noPib.filter(\.isNumber)
        let normTarget = String(digits.drop(while: { $0 == "0" }))
        if !digits.isEmpty {
            if let existing = pibs.first(where: { doc in
                let d = doc.noPib.filter(\.isNumber)
                let nd = String(d.drop(while: { $0 == "0" }))
                return d == digits || (!normTarget.isEmpty && nd == normTarget)
            }) {
                openPib(existing)
                return
            }
        }
        let query = !digits.isEmpty ? digits : fallbackQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            showToast("Nomor PIB tidak tersedia untuk baris ini")
            return
        }
        searchPibInBrowse(query: query, fromTps: true)
    }

    func searchPibInBrowse(query: String, fromTps: Bool = true) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedPib = nil
        activeUploadContext = nil
        activeDokap = nil
        browseReturnToTps = fromTps
        pendingBrowseAutoExpand = true
        pendingBrowseQuery = trimmed
        activeTab = .browse
    }

    // MARK: - Barcon, Kendala/Temuan, Quick BAP & TrollStore Auto-Update

    private func barconKey(for pib: PibDocument) -> String {
        let d = pib.noPib.filter(\.isNumber)
        return d.isEmpty ? pib.kodeTiket : d
    }

    func isBarconSubmitted(for pib: PibDocument) -> Bool {
        submittedBarconKeys.contains(barconKey(for: pib))
    }

    func toggleBarconSubmitted(for pib: PibDocument) {
        let key = barconKey(for: pib)
        if submittedBarconKeys.contains(key) {
            submittedBarconKeys.remove(key)
            showToast("Status Aju Barcon PIB \(pib.noPib) dibatalkan")
        } else {
            submittedBarconKeys.insert(key)
            showToast("Aju Barcon PIB \(pib.noPib) ditandai sudah diajukan")
        }
        UserDefaults.standard.set(Array(submittedBarconKeys), forKey: "siapneo_submitted_barcons")
    }

    func openBarconForm(for pib: PibDocument) {
        barconSheetTarget = BarconFormTarget(pib: pib, isKendalaTemuan: false)
    }

    func openKendalaTemuanForm(for pib: PibDocument) {
        barconSheetTarget = BarconFormTarget(pib: pib, isKendalaTemuan: true)
    }

    func openBapForPib(_ pib: PibDocument) async {
        guard let sess = session else { return }
        showToast("Mencari dokumen BAP PIB \(pib.noPib)...")
        if let dokap = try? await SiapApiClient.shared.fetchDokumen(kodeTiket: pib.kodeTiket) {
            for (k, v) in dokap {
                if k.lowercased().contains("bap") {
                    if let u = URL(string: SiapApiClient.shared.absolutizeSiap3(v)) {
                        activeDokap = DokapTarget(title: "BAP • PIB \(pib.noPib)", url: u)
                        return
                    }
                }
            }
        }
        if let bapStr = try? await SiapApiClient.shared.fetchBapUrlForPib(
            username: sess.username,
            password: sess.password,
            fallbackEmail: sess.usernameEmail,
            noPib: pib.noPib
        ), let u = URL(string: bapStr) {
            activeDokap = DokapTarget(title: "BAP • PIB \(pib.noPib)", url: u)
            return
        }
        showToast("Dokumen BAP untuk PIB \(pib.noPib) belum tersedia di server")
    }

    var currentAppVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.19.7"
    }

    var currentAppBuild: Int {
        Int((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "147") ?? 147
    }

    var isTrollStoreUrlSchemeReady: Bool {
        guard let url = URL(string: "apple-magnifier://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func checkForAppUpdate(silent: Bool, force: Bool = false) async {
        if silent && !autoCheckUpdates { return }
        if silent && !force && Date().timeIntervalSince(lastAutoCheckAt) < 900 {
            return
        }
        if isCheckingUpdate { return }
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        lastAutoCheckAt = Date()

        guard let info = await SiapApiClient.shared.checkLatestReleaseUpdate() else {
            if !silent { showToast("Gagal memeriksa pembaruan dari server update") }
            return
        }
        let df = SiapCrypto.wibFormatter("HH:mm")
        lastUpdateCheckText = "Dicek \(df.string(from: Date())) WIB"

        let isNewer = SiapApiClient.shared.isVersionNewer(
            remoteVersion: info.remoteVersion,
            remoteBuild: info.remoteBuild,
            localVersion: currentAppVersion,
            localBuild: currentAppBuild
        )
        if isNewer {
            availableUpdate = info
            let snoozedBuild = UserDefaults.standard.integer(forKey: snoozedUpdateBuildKey)
            if !silent || info.mandatory || snoozedBuild != info.remoteBuild {
                showUpdatePromptSheet = true
            }
            if !silent {
                showToast("Pembaruan v\(info.remoteVersion) (\(info.remoteBuild)) tersedia!")
            }
        } else {
            availableUpdate = nil
            showUpdatePromptSheet = false
            if !silent { showToast("SIAP NEO sudah versi terbaru (v\(currentAppVersion))") }
        }
    }

    func dismissUpdatePrompt(snoozeBuild: Bool) {
        if snoozeBuild, let upd = availableUpdate {
            UserDefaults.standard.set(upd.remoteBuild, forKey: snoozedUpdateBuildKey)
        }
        showUpdatePromptSheet = false
    }

    func triggerTrollStoreUpdate(_ info: AppUpdateInfo) {
        showUpdatePromptSheet = false
        let encoded = info.ipaDownloadUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? info.ipaDownloadUrl
        if let trollUrl = URL(string: "apple-magnifier://install?url=\(encoded)"),
           UIApplication.shared.canOpenURL(trollUrl) {
            UIApplication.shared.open(trollUrl)
        } else if let directUrl = URL(string: info.ipaDownloadUrl) {
            showToast("URL Scheme TrollStore belum aktif — membuka unduhan Safari")
            UIApplication.shared.open(directUrl)
        }
    }

    func openDirectIpaDownload(_ info: AppUpdateInfo) {
        showUpdatePromptSheet = false
        if let directUrl = URL(string: info.ipaDownloadUrl) {
            UIApplication.shared.open(directUrl)
        }
    }

    func saveSession(_ s: UserSession) {
        self.session = s
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    func logout() {
        self.session = nil
        self.pibs = []
        self.assignedIps = []
        self.assignedIpTotal = 0
        self.assignedIpHasMore = false
        self.assignedIpError = nil
        self.lorongItems = []
        self.redistHistory = []
        self.holdHistory = []
        self.showRedistSheet = false
        self.showHoldSheet = false
        self.selectedPib = nil
        self.activeUploadContext = nil
        self.activeDokap = nil
        self.activeTab = .beranda
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    func showToast(_ msg: String) {
        toastMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if toastMessage == msg { toastMessage = nil }
        }
    }

    func loadPibs() async {
        guard let nip = session?.nip, !nip.isEmpty else { return }
        isLoadingPibs = true
        lastPibError = nil
        defer { isLoadingPibs = false }
        do {
            let fetched = try await SiapApiClient.shared.fetchHomescreen(nip: nip)
            pibs = fetched.sorted { a, b in
                let ka = SiapApiClient.shared.toSortableTimestamp(a.tglPib)
                let kb = SiapApiClient.shared.toSortableTimestamp(b.tglPib)
                if ka != kb { return ka > kb }
                return a.noPib > b.noPib
            }
            let df = SiapCrypto.wibFormatter("HH:mm")
            lastUpdatedText = "Diperbarui \(df.string(from: Date())) WIB"
        } catch {
            lastPibError = error.localizedDescription
            showToast("Gagal memuat PIB: \(error.localizedDescription)")
        }
    }

    func loadAssignedIps(query: String = "", reset: Bool = true) async {
        guard let sess = session else { return }
        isLoadingAssignedIps = true
        assignedIpError = nil
        defer { isLoadingAssignedIps = false }
        let startIdx = reset ? 0 : assignedIps.count
        let pageSize = reset ? 25 : 15
        do {
            let res = try await SiapApiClient.shared.fetchAssignedIpList(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                start: startIdx,
                length: pageSize,
                query: query
            )
            if reset {
                assignedIps = res.items
            } else {
                let existing = Set(assignedIps.map(\.id))
                let fresh = res.items.filter { !existing.contains($0.id) }
                assignedIps.append(contentsOf: fresh)
            }
            assignedIpTotal = max(res.totalRecords, assignedIps.count)
            assignedIpHasMore = res.items.count >= pageSize && assignedIps.count < assignedIpTotal
        } catch {
            assignedIpError = error.localizedDescription
            showToast("Gagal memuat Daftar IP: \(error.localizedDescription)")
        }
    }

    func loadLorong() async {
        guard let nip = session?.nip, !nip.isEmpty else { return }
        isLoadingLorong = true
        defer { isLoadingLorong = false }
        do {
            let fetched = try await SiapApiClient.shared.fetchDetailKontainerNip(nip: nip)
            lorongItems = fetched.sorted { a, b in
                let ka = SiapApiClient.shared.toSortableTimestamp(a.tglPib)
                let kb = SiapApiClient.shared.toSortableTimestamp(b.tglPib)
                if ka != kb { return ka > kb }
                return a.noPib > b.noPib
            }
        } catch {
            showToast("Gagal memuat Instruksi Lorong: \(error.localizedDescription)")
        }
    }

    func openWhatsApp(phone: String, message: String) {
        var digits = phone.filter(\.isNumber)
        if digits.hasPrefix("0") {
            digits = "62" + digits.dropFirst()
        }
        let enc = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = digits.isEmpty ? "https://wa.me/?text=\(enc)" : "https://wa.me/\(digits)?text=\(enc)"
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Login View (Authentic SIAP NEO with Official Shield Logo)

struct LoginView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @State private var username = ""
    @State private var password = ""
    @State private var rememberUser = true
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            SiapColors.light.headerGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 36)

                    VStack(spacing: 10) {
                        Image("SiapLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)

                        Text("SIAP NEO")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)

                        Text("KPU Bea dan Cukai Tipe A Tanjung Priok")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(SiapColors.hintOnNavy)

                        Text("Sistem Informasi Pemeriksaan Fisik • v1.19.8")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(SiapColors.brandAmber.opacity(0.2))
                            .foregroundStyle(SiapColors.brandAmber)
                            .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        Text("Masuk Akun Pemeriksa")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(colors.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username / Email SIAP")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(colors.textSecondary)
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(colors.primaryAction)
                                TextField("Masukkan username SIAP", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(colors.textPrimary)
                                if !username.isEmpty {
                                    Button { username = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(colors.textHint)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(13)
                            .background(colors.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(colors.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(colors.textSecondary)
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(colors.primaryAction)
                                if showPassword {
                                    TextField("Masukkan password", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .foregroundStyle(colors.textPrimary)
                                } else {
                                    SecureField("Masukkan password", text: $password)
                                        .foregroundStyle(colors.textPrimary)
                                }
                                Button { showPassword.toggle() } label: {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundStyle(colors.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(13)
                            .background(colors.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(colors.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Toggle(isOn: $rememberUser) {
                            Text("Ingat Username")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(colors.textPrimary)
                        }
                        .tint(colors.primaryAction)

                        if let errorMsg {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(errorMsg).font(.system(size: 12.5, weight: .medium))
                            }
                            .foregroundStyle(colors.danger)
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.danger.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(colors.danger.opacity(0.35), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        SiapFilledButton(
                            isLoading ? "Menghubungkan ke SIAP..." : "Masuk",
                            icon: isLoading ? nil : "arrow.right.circle.fill",
                            bg: colors.primaryAction,
                            fg: colors.onPrimaryAction,
                            isLoading: isLoading
                        ) {
                            Task { await performLogin() }
                        }
                        .disabled(isLoading || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                        .opacity(isLoading || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty ? 0.55 : 1.0)
                    }
                    .padding(20)
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(colors.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.black.opacity(0.32), radius: 22, y: 10)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 28)
                }
            }
        }
        .onAppear {
            if username.isEmpty && !app.rememberedUsername.isEmpty {
                username = app.rememberedUsername
            }
        }
    }

    private func performLogin() async {
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let sess = try await SiapApiClient.shared.login(username: cleanUser, password: password)
            if rememberUser { app.rememberedUsername = cleanUser }
            app.saveSession(sess)
            async let p: Void = app.loadPibs()
            async let l: Void = app.loadLorong()
            _ = await (p, l)
            app.showToast("Berhasil Login • \(sess.displayName)")
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Tab 1: Beranda (Authentic Android HomeDashboardContent + PibGridCard)

struct HomeDashboardView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @State private var searchText = ""
    @State private var filter: HomeStatusFilter = .semua
    @State private var batalTarget: PibDocument?

    private var siapCount: Int { app.pibs.filter { $0.normalizedStatusCategory == "siap" }.count }
    private var sedangCount: Int { app.pibs.filter { $0.normalizedStatusCategory == "sedang" }.count }
    private var selesaiCount: Int { app.pibs.filter { $0.normalizedStatusCategory == "selesai" }.count }

    private var filteredPibs: [PibDocument] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return app.pibs.filter { doc in
            let matchFilter: Bool
            switch filter {
            case .semua: matchFilter = true
            case .siap: matchFilter = doc.normalizedStatusCategory == "siap"
            case .sedang: matchFilter = doc.normalizedStatusCategory == "sedang"
            case .selesai: matchFilter = doc.normalizedStatusCategory == "selesai"
            case .atensi: matchFilter = doc.hasAtensi
            }
            if !matchFilter { return false }
            if q.isEmpty { return true }
            return doc.noPib.lowercased().contains(q)
                || doc.importir.lowercased().contains(q)
                || doc.kodeTps.lowercased().contains(q)
                || doc.kodeTiket.lowercased().contains(q)
                || doc.namaPfpd.lowercased().contains(q)
                || doc.namaPj.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: app.isCompact ? 9 : 12) {
                // Officer Summary Strip (Matches Android SiapCardBrush)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.session?.displayName ?? "Pemeriksa")
                                .font(.system(size: 15.5, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text("NIP \(app.session?.nip ?? "-")")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(SiapColors.hintOnNavy)
                                if let jab = app.session?.jabatan, !jab.isEmpty {
                                    Text("• \(jab)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(SiapColors.brandAmber)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        HomeMetricBox(label: "Total", value: "\(app.pibs.count)", accent: .white)
                        HomeMetricBox(label: "Siap", value: "\(siapCount)", accent: Color(hex: 0xFCA5A5))
                        HomeMetricBox(label: "Sedang", value: "\(sedangCount)", accent: Color(hex: 0x86EFAC))
                        HomeMetricBox(label: "Selesai", value: "\(selesaiCount)", accent: Color(hex: 0x7DD3FC))
                    }
                }
                .padding(14)
                .background(colors.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 10)

                // Daftar PIB Header Row (Matches Android HomeDashboardContent)
                HStack(spacing: 8) {
                    Text("Daftar PIB")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)

                    Text("\(filteredPibs.count)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(colors.primaryAction)
                        .foregroundStyle(colors.onPrimaryAction)
                        .clipShape(Capsule())

                    if !app.lastUpdatedText.isEmpty {
                        Text(app.lastUpdatedText)
                            .font(.system(size: 11))
                            .foregroundStyle(colors.textHint)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        app.showManualSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Manual")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(colors.primaryContainer)
                        .foregroundStyle(colors.onPrimaryContainer)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)

                // Authentic Android Redist & Hold Quick Action Row
                HStack(spacing: 10) {
                    Button {
                        app.showRedistSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 13, weight: .bold))
                            Text("Redist")
                                .font(.system(size: 13.5, weight: .bold))
                        }
                        .foregroundStyle(SiapColors.brandAmber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(colors.isDark ? Color(hex: 0x132231) : colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SiapColors.brandAmber.opacity(colors.isDark ? 0.85 : 0.9), lineWidth: 1.3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        app.showHoldSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Hold")
                                .font(.system(size: 13.5, weight: .bold))
                        }
                        .foregroundStyle(SiapColors.brandSky)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(colors.isDark ? Color(hex: 0x132231) : colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SiapColors.brandSky.opacity(colors.isDark ? 0.85 : 0.9), lineWidth: 1.3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(colors.textHint)
                    TextField("Cari No PIB, Importir, TPS, PFPD, PJ...", text: $searchText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(colors.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(colors.textHint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(colors.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)

                // Status Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(HomeStatusFilter.allCases) { item in
                            let active = filter == item
                            Button { filter = item } label: {
                                Text(filterChipTitle(item))
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(active ? colors.primaryAction : colors.surface)
                                    .foregroundStyle(active ? colors.onPrimaryAction : colors.textSecondary)
                                    .overlay(
                                        Capsule().stroke(active ? Color.clear : colors.cardBorder, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Content List
                if app.isLoadingPibs && app.pibs.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(colors.primaryAction).scaleEffect(1.1)
                        Text("Memuat daftar PIB dari server SIAP...")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else if filteredPibs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 38))
                            .foregroundStyle(colors.textHint)
                        Text(app.pibs.isEmpty ? "Belum ada penugasan PIB aktif" : "Tidak ada PIB cocok dengan filter")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                        if let err = app.lastPibError {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(colors.danger)
                                .multilineTextAlignment(.center)
                        }
                        SiapOutlinedButton("Muat Ulang Beranda", icon: "arrow.clockwise", color: colors.primaryAction) {
                            Task { await app.loadPibs() }
                        }
                        .frame(maxWidth: 210)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(colors.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 12)
                } else {
                    ForEach(filteredPibs) { doc in
                        PibGridCardView(
                            doc: doc,
                            colors: colors,
                            isCompact: app.isCompact,
                            onTap: { app.openPib(doc) },
                            onWhatsAppPfpd: {
                                app.openWhatsApp(
                                    phone: doc.noHpPfpd,
                                    message: "Yth. \(doc.namaPfpd), konfirmasi pemeriksaan fisik PIB \(doc.noPib) (\(doc.importir))."
                                )
                            },
                            onWhatsAppPj: {
                                app.openWhatsApp(
                                    phone: doc.hpPj,
                                    message: "Selamat pagi/siang \(doc.namaPj), mohon kesiapan pemeriksaan fisik PIB \(doc.noPib) (\(doc.importir)) di TPS \(doc.kodeTps)."
                                )
                            },
                            onBatal: { batalTarget = doc }
                        )
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .refreshable {
            await app.loadPibs()
        }
        .task {
            if app.pibs.isEmpty && app.session != nil {
                await app.loadPibs()
            }
        }
        .alert("Batalkan Pemeriksaan PIB?", isPresented: Binding(
            get: { batalTarget != nil },
            set: { if !$0 { batalTarget = nil } }
        )) {
            Button("Batal", role: .cancel) { batalTarget = nil }
            Button("Ya, Batalkan", role: .destructive) {
                if let target = batalTarget {
                    Task {
                        do {
                            try await SiapApiClient.shared.updateBatalPeriksa(kodeTiket: target.kodeTiket)
                            app.showToast("PIB \(target.noPib) dibatalkan")
                            await app.loadPibs()
                        } catch {
                            app.showToast("Gagal batal: \(error.localizedDescription)")
                        }
                        batalTarget = nil
                    }
                }
            }
        } message: {
            Text("Batalkan pemeriksaan untuk PIB No. \(batalTarget?.noPib ?? "")?")
        }
    }

    private func filterChipTitle(_ item: HomeStatusFilter) -> String {
        switch item {
        case .semua: return "Semua (\(app.pibs.count))"
        case .siap: return "Siap (\(siapCount))"
        case .sedang: return "Sedang (\(sedangCount))"
        case .selesai: return "Selesai (\(selesaiCount))"
        case .atensi: return "Atensi (\(app.pibs.filter(\.hasAtensi).count))"
        }
    }
}

struct HomeMetricBox: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Authentic Android PibGridCard

struct PibGridCardView: View {
    @EnvironmentObject var app: AppState
    let doc: PibDocument
    let colors: SiapColors
    let isCompact: Bool
    let onTap: () -> Void
    let onWhatsAppPfpd: () -> Void
    let onWhatsAppPj: () -> Void
    let onBatal: () -> Void

    var body: some View {
        let st = colors.statusBadgeStyle(for: doc.status)

        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(st.accent)
                    .frame(width: 4.5)

                VStack(alignment: .leading, spacing: isCompact ? 6 : 9) {
                    // Row 1: PIB No + Date + Status Badge
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("PIB \(doc.noPib)")
                                    .font(.system(size: isCompact ? 15 : 16.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(colors.textPrimary)

                                if !doc.jenisKontainer.isEmpty && doc.jenisKontainer != "-" {
                                    Text(doc.isLclDefault ? "LCL" : "FCL")
                                        .font(.system(size: 10, weight: .heavy))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(colors.primaryContainer)
                                        .foregroundStyle(colors.onPrimaryContainer)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                }

                                if !doc.barcon.isEmpty && doc.barcon != "-" && doc.barcon != "0" {
                                    Text("BARCON")
                                        .font(.system(size: 9.5, weight: .heavy))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(colors.warningBoxBg)
                                        .foregroundStyle(colors.warningBoxText)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                }
                            }
                            Text(SiapCrypto.formatDisplayDate(doc.tglPib))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(colors.textHint)
                        }

                        Spacer(minLength: 4)
                        SiapStatusChip(text: doc.status, colors: colors)
                    }

                    // Row 2: Importir
                    Text(doc.importir)
                        .font(.system(size: isCompact ? 13 : 14, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Row 3: Meta pills (TPS, Persen, Item, IP)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if !doc.kodeTps.isEmpty && doc.kodeTps != "-" {
                                SiapMetaTag(icon: "building.2.fill", text: "TPS \(doc.kodeTps)", bg: colors.surfaceElevated, fg: colors.textSecondary)
                            }
                            if !doc.persentasePeriksa.isEmpty && doc.persentasePeriksa != "-" {
                                SiapMetaTag(icon: "percent", text: doc.persentasePeriksa, bg: colors.surfaceElevated, fg: colors.secondary)
                            }
                            if !doc.jumlahItem.isEmpty && doc.jumlahItem != "-" {
                                SiapMetaTag(icon: "shippingbox", text: "\(doc.jumlahItem) Item", bg: colors.surfaceElevated, fg: colors.textSecondary)
                            }
                            if !doc.ipCeisa.isEmpty && doc.ipCeisa != "-" {
                                SiapMetaTag(icon: "doc.plaintext", text: "IP \(doc.ipCeisa)", bg: colors.surfaceElevated, fg: colors.textHint)
                            }
                        }
                    }

                    // Row 4: Atensi PFPD Warning Box
                    if doc.hasAtensi {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(colors.warningBoxText)
                                .padding(.top, 1)
                            Text("Atensi: \(doc.atensi)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(colors.warningBoxText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.warningBoxBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(colors.warningBoxBorder.opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // Row 5: PFPD / PJ Split + Quick Actions (Matches PfpdPjSplit)
                    Divider().overlay(colors.divider)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            if !doc.namaPfpd.isEmpty && doc.namaPfpd != "-" {
                                Text("PFPD: \(doc.namaPfpd)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(colors.textSecondary)
                                    .lineLimit(1)
                            }
                            if !doc.namaPj.isEmpty && doc.namaPj != "-" {
                                Text("PJ: \(doc.namaPj)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(colors.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !doc.noHpPfpd.isEmpty && doc.noHpPfpd != "-" {
                            Button(action: onWhatsAppPfpd) {
                                HStack(spacing: 3) {
                                    Image(systemName: "message.fill")
                                    Text("PFPD")
                                }
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(colors.success.opacity(0.15))
                                .foregroundStyle(colors.success)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if !doc.hpPj.isEmpty && doc.hpPj != "-" {
                            Button(action: onWhatsAppPj) {
                                HStack(spacing: 3) {
                                    Image(systemName: "message.fill")
                                    Text("PJ")
                                }
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(colors.success.opacity(0.15))
                                .foregroundStyle(colors.success)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: onBatal) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(colors.danger.opacity(0.85))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                    }

                    // Row 6: Authentic Android Selesai / Sudah BAP Action Row (Aju Barcon | Lihat BAP | Kendala)
                    if doc.isSudahBapOrSelesai || (!doc.barcon.isEmpty && doc.barcon != "-" && doc.barcon != "0") {
                        let barconDone = app.isBarconSubmitted(for: doc)
                        HStack(spacing: 7) {
                            Button {
                                app.openBarconForm(for: doc)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: barconDone ? "checkmark.circle.fill" : "shippingbox.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(barconDone ? "Barcon Diajukan" : "Aju Barcon")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 8)
                                .background(barconDone ? colors.success.opacity(0.18) : colors.primaryAction)
                                .foregroundStyle(barconDone ? colors.success : colors.onPrimaryAction)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(barconDone ? colors.success.opacity(0.55) : Color.clear, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            if doc.isSudahBapOrSelesai {
                                Button {
                                    Task { await app.openBapForPib(doc) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("BAP")
                                            .font(.system(size: 11.5, weight: .bold))
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 10)
                                    .background(colors.primaryContainer)
                                    .foregroundStyle(colors.onPrimaryContainer)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                app.openKendalaTemuanForm(for: doc)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.bubble.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Kendala")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.vertical, 7)
                                .padding(.horizontal, 9)
                                .background(colors.surfaceElevated)
                                .foregroundStyle(colors.textSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(colors.cardBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(isCompact ? 11 : 13)
            }
            .background(colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(colors.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(colors.isDark ? 0.22 : 0.05), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-Screen Drill-Down: HeaderPibFclPanel + PibDocumentBottomActionBar

struct HeaderPibFclPanel: View {
    @EnvironmentObject var app: AppState
    let pib: PibDocument
    let colors: SiapColors

    @State private var isRincianExpanded = true
    @State private var isLampiranExpanded = true
    @State private var containers: [ContainerItem] = []
    @State private var isLoadingContainers = false
    @State private var dokapLinks: [String: String] = [:]
    @State private var siap3Attachments: [PendokDocumentAttachment] = []
    @State private var bapUrl: String?
    @State private var isLoadingAttachments = false
    @State private var attachmentNote: String?
    @State private var manualContainer = ""
    @State private var showAddContainer = false
    @State private var showTtdSheet = false
    @State private var showSelesaiConfirm = false
    @State private var showBatalConfirm = false
    @State private var isSubmittingAction = false

    private var modeLabel: String { pib.isLclDefault ? "LCL" : "FCL" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    // Collapsible Card: RINCIAN DOKUMEN PIB (FCL/LCL)
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRincianExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(SiapColors.brandAmber)
                                Text("RINCIAN DOKUMEN PIB (\(modeLabel))")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                SiapStatusChip(text: pib.status, colors: colors)
                                Image(systemName: isRincianExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(SiapColors.hintOnNavy)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(colors.cardGradient)
                        }
                        .buttonStyle(.plain)

                        if isRincianExpanded {
                            VStack(spacing: 8) {
                                SiapMetaRow(label: "No. / Tanggal PIB", value: "\(pib.noPib) / \(SiapCrypto.formatDisplayDate(pib.tglPib))", colors: colors)
                                SiapMetaRow(label: "Importir", value: pib.importir, colors: colors)
                                SiapMetaRow(label: "Lokasi TPS", value: pib.kodeTps, colors: colors)
                                SiapMetaRow(label: "Kode Tiket", value: pib.kodeTiket, colors: colors)
                                SiapMetaRow(label: "IP CEISA", value: pib.ipCeisa, colors: colors)
                                SiapMetaRow(label: "Jenis / Persen", value: "\(pib.jenisKontainer) • \(pib.persentasePeriksa)", colors: colors)
                                SiapMetaRow(label: "Jumlah Item", value: pib.jumlahItem, colors: colors)
                                if !pib.barcon.isEmpty && pib.barcon != "-" {
                                    SiapMetaRow(label: "Barang Contoh", value: pib.barcon, colors: colors)
                                }
                                if !pib.nomorBap.isEmpty && pib.nomorBap != "-" {
                                    SiapMetaRow(label: "Nomor BAP", value: "\(pib.nomorBap) (\(SiapCrypto.formatDisplayDate(pib.tglBap)))", colors: colors)
                                }
                                if !pib.pendampingan.isEmpty && pib.pendampingan != "-" {
                                    SiapMetaRow(label: "Pendampingan", value: "\(pib.pendampingan) \(pib.namaPendamping)", colors: colors)
                                }

                                // PFPD & PJ with direct WA buttons
                                Divider().overlay(colors.divider)

                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Nama PFPD").font(.system(size: 11)).foregroundStyle(colors.textHint)
                                        Text(pib.namaPfpd).font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.textPrimary)
                                    }
                                    Spacer()
                                    if !pib.noHpPfpd.isEmpty && pib.noHpPfpd != "-" {
                                        Button {
                                            app.openWhatsApp(phone: pib.noHpPfpd, message: "Yth. \(pib.namaPfpd), update pemeriksaan PIB \(pib.noPib) (\(pib.importir)).")
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "message.fill")
                                                Text("WA PFPD")
                                            }
                                            .font(.system(size: 11.5, weight: .bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(colors.success.opacity(0.16))
                                            .foregroundStyle(colors.success)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pengurus / PJ").font(.system(size: 11)).foregroundStyle(colors.textHint)
                                        Text(pib.namaPj).font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.textPrimary)
                                    }
                                    Spacer()
                                    if !pib.hpPj.isEmpty && pib.hpPj != "-" {
                                        Button {
                                            app.openWhatsApp(phone: pib.hpPj, message: "Halo \(pib.namaPj), mohon kesiapan pemeriksaan fisik PIB \(pib.noPib) di TPS \(pib.kodeTps).")
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "message.fill")
                                                Text("WA PJ")
                                            }
                                            .font(.system(size: 11.5, weight: .bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(colors.success.opacity(0.16))
                                            .foregroundStyle(colors.success)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if pib.hasAtensi {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(colors.warningBoxText)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("ATENSI PFPD")
                                                .font(.system(size: 10.5, weight: .heavy))
                                                .foregroundStyle(colors.warningBoxText)
                                            Text(pib.atensi)
                                                .font(.system(size: 12.5, weight: .semibold))
                                                .foregroundStyle(colors.warningBoxText)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(colors.warningBoxBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(colors.warningBoxBorder.opacity(0.6), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                            .padding(14)
                            .background(colors.surface)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(colors.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    // Aju Barcon & Kendala/Temuan Bar (Matches Android Selesai/BAP workflow)
                    HStack(spacing: 8) {
                        let barconDone = app.isBarconSubmitted(for: pib)
                        SiapFilledButton(
                            barconDone ? "Barcon Diajukan" : "Aju Barcon",
                            icon: barconDone ? "checkmark.circle.fill" : "shippingbox.fill",
                            bg: barconDone ? colors.success : colors.primaryAction,
                            fg: barconDone ? (colors.isDark ? Color(hex: 0x052E16) : .white) : colors.onPrimaryAction
                        ) {
                            app.openBarconForm(for: pib)
                        }

                        SiapOutlinedButton(
                            "Kendala / Temuan",
                            icon: "exclamationmark.bubble.fill",
                            color: colors.secondary,
                            bg: colors.surface
                        ) {
                            app.openKendalaTemuanForm(for: pib)
                        }
                    }
                    .padding(.horizontal, 12)

                    // Container List Section (Matches Daftar Kontainer (N))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Daftar Kontainer (\(containers.count))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(colors.textPrimary)
                            Spacer()
                            Button {
                                showAddContainer.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Input")
                                }
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(colors.primaryContainer)
                                .foregroundStyle(colors.onPrimaryContainer)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task { await loadDetails() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(colors.primaryAction)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)

                        if showAddContainer {
                            HStack(spacing: 8) {
                                TextField("Contoh: TCKU1234567 atau LCL", text: $manualContainer)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 13.5, design: .monospaced))
                                    .foregroundStyle(colors.textPrimary)
                                    .padding(11)
                                    .background(colors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                Button {
                                    let tok = manualContainer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                    guard !tok.isEmpty else { return }
                                    app.openUpload(pib: pib, nokon: tok, containers: containers)
                                    manualContainer = ""
                                    showAddContainer = false
                                } label: {
                                    Text("Buka")
                                        .font(.system(size: 13, weight: .bold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .background(colors.primaryAction)
                                        .foregroundStyle(colors.onPrimaryAction)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                        }

                        if isLoadingContainers {
                            HStack(spacing: 10) {
                                ProgressView().tint(colors.primaryAction)
                                Text("Memuat daftar kontainer...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else if containers.isEmpty {
                            VStack(spacing: 10) {
                                Text("Belum ada kontainer terdaftar (atau dokumen LCL).")
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.textSecondary)
                                SiapFilledButton(
                                    "Upload Foto Pemeriksaan (\(modeLabel))",
                                    icon: "camera.fill",
                                    bg: colors.primaryAction,
                                    fg: colors.onPrimaryAction
                                ) {
                                    app.openUpload(pib: pib, nokon: pib.isLclDefault ? "LCL" : "KONTAINER", containers: containers)
                                }
                                .frame(maxWidth: 280)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(colors.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 12)
                        } else {
                            ForEach(containers) { c in
                                ContainerCardRow(container: c, colors: colors) {
                                    app.openUpload(pib: pib, nokon: c.noContainer, containers: containers)
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                    }

                    // Lampiran Dokumen Section (Merged SIAP FB get_dokumen + SIAP 3.0 pendok_mk/get_jenis_dokumen + BAP)
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLampiranExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "paperclip")
                                    .foregroundStyle(colors.primaryAction)
                                Text("Lampiran Dokumen (\(allLampiranRows.count))")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(colors.textPrimary)
                                Spacer()
                                if isLoadingAttachments {
                                    ProgressView().tint(colors.primaryAction).scaleEffect(0.8)
                                }
                                Button {
                                    Task { await loadAttachments() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(colors.primaryAction)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                Image(systemName: isLampiranExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(colors.textHint)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(colors.surfaceElevated)
                        }
                        .buttonStyle(.plain)

                        if isLampiranExpanded {
                            VStack(spacing: 8) {
                                if isLoadingAttachments && allLampiranRows.isEmpty {
                                    HStack(spacing: 8) {
                                        ProgressView().tint(colors.primaryAction)
                                        Text("Mengambil lampiran dari SIAP FB & SIAP 3.0...")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(colors.textSecondary)
                                    }
                                    .padding(.vertical, 10)
                                } else if allLampiranRows.isEmpty {
                                    VStack(spacing: 6) {
                                        Text("Belum ada lampiran ditemukan untuk PIB \(pib.noPib).")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(colors.textHint)
                                        if let note = attachmentNote {
                                            Text(note)
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(colors.warning)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                } else {
                                    ForEach(allLampiranRows) { row in
                                        Button {
                                            app.activeDokap = DokapTarget(title: row.title, url: row.url)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "doc.richtext.fill")
                                                    .font(.system(size: 17))
                                                    .foregroundStyle(colors.primaryAction)
                                                    .frame(width: 32, height: 32)
                                                    .background(colors.primaryContainer)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(row.title)
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(colors.textPrimary)
                                                        .lineLimit(2)
                                                    if !row.subtitle.isEmpty {
                                                        Text(row.subtitle)
                                                            .font(.system(size: 11))
                                                            .foregroundStyle(colors.textHint)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                                Text("Lihat")
                                                    .font(.system(size: 11.5, weight: .bold))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(colors.primaryAction)
                                                    .foregroundStyle(colors.onPrimaryAction)
                                                    .clipShape(Capsule())
                                            }
                                            .padding(10)
                                            .background(colors.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(12)
                            .background(colors.surface)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(colors.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 20)
            }

            // Sticky Bottom Action Bar (Exact port of Android PibDocumentBottomActionBar!)
            VStack(spacing: 8) {
                // Row 1: Dokap Quick Pills (PIB | INV/PL | B/L | BAP)
                HStack(spacing: 6) {
                    DokapPillButton(title: "PIB", icon: "doc.text.fill", available: resolvePibUrl() != nil, colors: colors) {
                        openResolvedDoc(title: "Dokumen PIB \(pib.noPib)", url: resolvePibUrl())
                    }
                    DokapPillButton(title: "INV/PL", icon: "list.bullet.rectangle", available: resolvePlUrl() != nil, colors: colors) {
                        openResolvedDoc(title: "INV / PL • \(pib.noPib)", url: resolvePlUrl())
                    }
                    DokapPillButton(title: "B/L", icon: "ferry.fill", available: resolveBlUrl() != nil, colors: colors) {
                        openResolvedDoc(title: "B/L • \(pib.noPib)", url: resolveBlUrl())
                    }
                    DokapPillButton(title: "BAP", icon: "checkmark.seal.fill", available: resolveBapUrl() != nil, colors: colors) {
                        openResolvedDoc(title: "BAP • \(pib.noPib)", url: resolveBapUrl())
                    }
                }

                // Row 2: TTD PJ | Selesai Periksa | Batal
                HStack(spacing: 8) {
                    SiapOutlinedButton("TTD PJ", icon: "signature", color: colors.secondary, bg: colors.surfaceElevated) {
                        showTtdSheet = true
                    }
                    .frame(width: 104)

                    SiapFilledButton(
                        "Selesai Periksa",
                        icon: "checkmark.seal.fill",
                        bg: colors.success,
                        fg: colors.isDark ? Color(hex: 0x052E16) : .white,
                        isLoading: isSubmittingAction
                    ) {
                        showSelesaiConfirm = true
                    }

                    Button {
                        showBatalConfirm = true
                    } label: {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(colors.danger)
                            .frame(width: 44, height: 44)
                            .background(colors.danger.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(colors.danger.opacity(0.5), lineWidth: 1.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(
                colors.surface
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(alignment: .top) {
                Rectangle().fill(colors.divider).frame(height: 0.75)
            }
        }
        .task(id: pib.kodeTiket) {
            await loadDetails()
        }
        .sheet(isPresented: $showTtdSheet) {
            TtdPjModalSheet(pib: pib, colors: colors)
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
        }
        .alert("Konfirmasi Selesai Pemeriksaan", isPresented: $showSelesaiConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Ya, Selesai") {
                Task { await submitSelesai() }
            }
        } message: {
            Text("Apakah pemeriksaan fisik barang untuk PIB No. \(pib.noPib) sudah selesai?")
        }
        .alert("Batalkan Pemeriksaan?", isPresented: $showBatalConfirm) {
            Button("Tidak", role: .cancel) {}
            Button("Ya, Batalkan", role: .destructive) {
                Task { await submitBatal() }
            }
        } message: {
            Text("Batalkan pemeriksaan untuk PIB No. \(pib.noPib)?")
        }
    }

    private struct LampiranRowItem: Identifiable {
        var id: String { "\(title)_\(url.absoluteString)" }
        let title: String
        let subtitle: String
        let url: URL
    }

    private var allLampiranRows: [LampiranRowItem] {
        var rows: [LampiranRowItem] = []
        var seen = Set<String>()

        for (k, v) in dokapLinks.sorted(by: { $0.key < $1.key }) {
            let absStr = SiapApiClient.shared.absolutizeSiap3(v)
            if let u = URL(string: absStr), seen.insert(u.absoluteString).inserted {
                rows.append(LampiranRowItem(title: k, subtitle: "SIAP FB Dokap", url: u))
            }
        }
        for att in siap3Attachments {
            if let u = URL(string: att.fileUrl), seen.insert(u.absoluteString).inserted {
                let sub = att.tglUpload.isEmpty ? att.jenisDokumen : "\(att.jenisDokumen) • \(att.tglUpload)"
                rows.append(LampiranRowItem(title: att.namaDokumen, subtitle: sub, url: u))
            }
        }
        if let bap = bapUrl, let u = URL(string: bap), seen.insert(u.absoluteString).inserted {
            rows.append(LampiranRowItem(title: "BAP Pemeriksaan (Cetak BAP)", subtitle: "SIAP 3.0", url: u))
        }
        return rows
    }

    private func loadDetails() async {
        isLoadingContainers = true
        async let cTask: [ContainerItem] = (try? await SiapApiClient.shared.fetchContainers(kodeTiket: pib.kodeTiket)) ?? []
        async let dTask: [String: String] = (try? await SiapApiClient.shared.fetchDokumen(kodeTiket: pib.kodeTiket)) ?? [:]
        containers = await cTask
        dokapLinks = await dTask
        isLoadingContainers = false
        await loadAttachments()
    }

    private func loadAttachments() async {
        guard let sess = app.session else { return }
        isLoadingAttachments = true
        attachmentNote = nil
        defer { isLoadingAttachments = false }
        do {
            async let attTask = SiapApiClient.shared.fetchAttachmentsForPib(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                noPib: pib.noPib,
                importirHint: pib.importir
            )
            async let bapTask = SiapApiClient.shared.fetchBapUrlForPib(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                noPib: pib.noPib
            )
            siap3Attachments = try await attTask
            bapUrl = try? await bapTask
        } catch {
            attachmentNote = error.localizedDescription
        }
    }

    private func resolvePibUrl() -> URL? {
        if let u = findInDokap(keys: ["pib"]) { return u }
        if let att = siap3Attachments.first(where: { $0.namaDokumen.uppercased().contains("PIB") || $0.jenisDokumen.uppercased().contains("PIB") }),
           let u = URL(string: att.fileUrl) { return u }
        for (k, v) in dokapLinks {
            let ku = k.uppercased()
            if !ku.contains("B/L") && !ku.contains("BILL") && !ku.contains("LADING"),
               let u = URL(string: SiapApiClient.shared.absolutizeSiap3(v)) { return u }
        }
        return nil
    }

    private func resolvePlUrl() -> URL? {
        if let u = findInDokap(keys: ["packing", "pl", "inv", "invoice"]) { return u }
        if let att = siap3Attachments.first(where: {
            let t = ($0.namaDokumen + " " + $0.jenisDokumen).uppercased()
            return t.contains("PACKING") || t.contains("INVOICE") || t.contains("INV") || t.contains("PL")
        }), let u = URL(string: att.fileUrl) { return u }
        return nil
    }

    private func resolveBlUrl() -> URL? {
        if let u = findInDokap(keys: ["b/l", "bill", "lading", "awb", "bl"]) { return u }
        if let att = siap3Attachments.first(where: {
            let t = ($0.namaDokumen + " " + $0.jenisDokumen).uppercased()
            let tokens = t.components(separatedBy: CharacterSet.alphanumerics.inverted)
            return t.contains("B/L") || t.contains("BILL") || t.contains("LADING") || t.contains("AWB") || t.contains("AIRWAY") || tokens.contains("BL")
        }), let u = URL(string: att.fileUrl) { return u }
        return nil
    }

    private func resolveBapUrl() -> URL? {
        if let u = findInDokap(keys: ["bap", "cetak_bap"]) { return u }
        if let bap = bapUrl, let u = URL(string: bap) { return u }
        return nil
    }

    private func findInDokap(keys: [String]) -> URL? {
        for (k, v) in dokapLinks {
            let kl = k.lowercased()
            if keys.contains(where: { kl.contains($0) }) {
                let absStr = SiapApiClient.shared.absolutizeSiap3(v)
                if let u = URL(string: absStr) { return u }
            }
        }
        return nil
    }

    private func openResolvedDoc(title: String, url: URL?) {
        if let url {
            app.activeDokap = DokapTarget(title: title, url: url)
        } else if isLoadingAttachments {
            app.showToast("Sedang mengambil lampiran dari SIAP 3.0...")
        } else {
            app.showToast("\(title) belum tersedia — cek daftar Lampiran Dokumen di atas")
        }
    }

    private func submitSelesai() async {
        isSubmittingAction = true
        defer { isSubmittingAction = false }
        do {
            try await SiapApiClient.shared.updateSelesaiPeriksa(kodeTiket: pib.kodeTiket)
            app.showToast("PIB \(pib.noPib) ditandai Selesai Periksa")
            await app.loadPibs()
            app.selectedPib = nil
        } catch {
            app.showToast("Gagal selesai: \(error.localizedDescription)")
        }
    }

    private func submitBatal() async {
        isSubmittingAction = true
        defer { isSubmittingAction = false }
        do {
            try await SiapApiClient.shared.updateBatalPeriksa(kodeTiket: pib.kodeTiket)
            app.showToast("PIB \(pib.noPib) dibatalkan")
            await app.loadPibs()
            app.selectedPib = nil
        } catch {
            app.showToast("Gagal batal: \(error.localizedDescription)")
        }
    }
}

struct SiapMetaRow: View {
    let label: String
    let value: String
    let colors: SiapColors

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textHint)
                .frame(width: 112, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }
}

struct ContainerCardRow: View {
    let container: ContainerItem
    let colors: SiapColors
    let onOpenUpload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(colors.primaryAction)
                Text(container.noContainer)
                    .font(.system(size: 15.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(colors.textPrimary)
                if !container.ukuranContainer.isEmpty && container.ukuranContainer != "-" {
                    Text("UK \(container.ukuranContainer)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(colors.primaryContainer)
                        .foregroundStyle(colors.onPrimaryContainer)
                        .clipShape(Capsule())
                }
                Spacer()
            }

            if !container.instruksiLorong.isEmpty && container.instruksiLorong != "-" {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.secondary)
                    Text("Lorong: \(container.instruksiLorong)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            if !container.pelaksanaanLorong.isEmpty && container.pelaksanaanLorong != "-" {
                Text("Pelaksanaan: \(container.pelaksanaanLorong)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(colors.textSecondary)
            }

            if !container.teknikPeriksa.isEmpty && container.teknikPeriksa != "-" {
                Text("Teknik: \(container.teknikPeriksa)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(colors.textHint)
            }

            SiapFilledButton(
                "Foto & Upload Pemeriksaan",
                icon: "camera.fill",
                bg: colors.primaryAction,
                fg: colors.onPrimaryAction,
                action: onOpenUpload
            )
        }
        .padding(13)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DokapPillButton: View {
    let title: String
    let icon: String
    let available: Bool
    let colors: SiapColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 11.5, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(available ? colors.primaryContainer : colors.surfaceElevated)
            .foregroundStyle(available ? colors.onPrimaryContainer : colors.textHint)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(available ? colors.primaryAction.opacity(0.45) : colors.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-Screen Drill-Down: UploadFotoPanel (CEISA / SIAP Foto Kontainer UI)

private struct PendingPhotoUpload: Identifiable {
    let id = UUID()
    let step: StepOption
    let image: UIImage
}

private enum UploadPanelSheet: Identifiable {
    case gallery
    case confirm(PendingPhotoUpload)
    case barang
    case fullscreen(OnlineImageItem)

    var id: String {
        switch self {
        case .gallery: return "gallery"
        case .confirm(let d): return "confirm_\(d.id.uuidString)"
        case .barang: return "barang"
        case .fullscreen(let item): return "full_\(item.id)"
        }
    }
}

private enum BarangPanelSheet: Identifiable {
    case gallery
    case confirm(PendingPhotoUpload)
    case fullscreen(OnlineImageItem)

    var id: String {
        switch self {
        case .gallery: return "barang_gallery"
        case .confirm(let d): return "barang_confirm_\(d.id.uuidString)"
        case .fullscreen(let item): return "barang_full_\(item.id)"
        }
    }
}

struct UploadFotoPanel: View {
    @EnvironmentObject var app: AppState
    let pib: PibDocument
    let initialNokon: String
    let allContainers: [ContainerItem]
    let colors: SiapColors

    @StateObject private var locMgr = LocationManager()
    @State private var selectedNokon = ""
    @State private var activeAddStep: StepOption = StepOption.containerPhotoSteps[0]
    @State private var showSourceDialog = false
    @State private var showCameraCover = false
    @State private var activeSheet: UploadPanelSheet?
    @State private var capturedDraftTemp: PendingPhotoUpload?
    @State private var watermarkEnabled = true
    @State private var onlineImages: [OnlineImageItem] = []
    @State private var isLoadingImages = false
    @State private var deleteTarget: OnlineImageItem?

    // Kontainer section state (Perintah Lorong, Ya/Tidak, Waktu Mulai)
    @State private var lorongDilaksanakanYa = true
    @State private var alasanTidakLorong = "-"
    @State private var teknikPeriksa = "-"
    @State private var alasanOptions: [String] = []
    @State private var teknikOptions: [String] = []
    @State private var waktuMulaiText = ""

    private var activeContainer: ContainerItem? {
        allContainers.first(where: { $0.noContainer.caseInsensitiveCompare(selectedNokon) == .orderedSame })
    }

    private var perintahLorongDisplay: String {
        let raw = activeContainer?.instruksiLorong.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (raw.isEmpty || raw == "not found") ? "-" : raw
    }

    private var barangImagesCount: Int {
        onlineImages.filter { item in
            StepOption.barangPhotoSteps.contains(where: { $0.matches(item.ketPraPemeriksaan) })
        }.count
    }

    private var unmatchedContainerImages: [OnlineImageItem] {
        let idCardStep = StepOption(code: "1", label: "ID Card PJ")
        return onlineImages.filter { item in
            !StepOption.containerPhotoSteps.contains(where: { $0.matches(item.ketPraPemeriksaan) })
            && !StepOption.barangPhotoSteps.contains(where: { $0.matches(item.ketPraPemeriksaan) })
            && !idCardStep.matches(item.ketPraPemeriksaan)
        }
    }

    private var sectionHeaderColor: Color {
        colors.isDark ? SiapColors.brandSky : Color(hex: 0x163A63)
    }

    private var navyActionColor: Color {
        colors.isDark ? Color(hex: 0x1E4B8A) : Color(hex: 0x0A2D63)
    }

    private var greenFinishColor: Color {
        Color(hex: 0x4BD367)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Multi-container switcher pills (only shown when > 1 container)
                if allContainers.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(allContainers) { c in
                                let active = selectedNokon == c.noContainer
                                Button {
                                    selectedNokon = c.noContainer
                                    syncContainerFormState()
                                    if let ctx = app.activeUploadContext {
                                        app.activeUploadContext = UploadFotoContext(pib: ctx.pib, nokon: c.noContainer, containers: ctx.containers)
                                    }
                                    Task { await loadContainerData() }
                                } label: {
                                    Text(c.noContainer)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(active ? navyActionColor : colors.surface)
                                        .foregroundStyle(active ? Color.white : colors.textSecondary)
                                        .overlay(
                                            Capsule().stroke(active ? Color.clear : colors.cardBorder, lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.top, 10)
                }

                // SECTION 1: Foto Kontainer
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Foto Kontainer")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(sectionHeaderColor)
                        Spacer()
                        if isLoadingImages {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(sectionHeaderColor)
                        } else {
                            Button {
                                Task { await loadImages() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Muat Ulang")
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(sectionHeaderColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Bounded scrollable card matching the CEISA/SIAP Foto Kontainer layout
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(StepOption.containerPhotoSteps) { step in
                                let stepPhotos = onlineImages.filter { step.matches($0.ketPraPemeriksaan) }
                                FotoCategoryStripRow(
                                    title: step.sectionTitle,
                                    photos: stepPhotos,
                                    colors: colors,
                                    onTapAdd: {
                                        activeAddStep = step
                                        showSourceDialog = true
                                    },
                                    onTapPhoto: { item in
                                        activeSheet = .fullscreen(item)
                                    },
                                    onDeletePhoto: { item in
                                        deleteTarget = item
                                    }
                                )
                            }

                            if !unmatchedContainerImages.isEmpty {
                                FotoCategoryStripRow(
                                    title: "Foto Lainnya",
                                    photos: unmatchedContainerImages,
                                    colors: colors,
                                    onTapAdd: {
                                        activeAddStep = StepOption.containerPhotoSteps[0]
                                        showSourceDialog = true
                                    },
                                    onTapPhoto: { item in
                                        activeSheet = .fullscreen(item)
                                    },
                                    onDeletePhoto: { item in
                                        deleteTarget = item
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                    .frame(height: 335)
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(colors.isDark ? colors.cardBorder : Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(colors.isDark ? 0.28 : 0.08), radius: 8, x: 0, y: 3)
                    .padding(.horizontal, 14)
                }
                .padding(.top, allContainers.count > 1 ? 0 : 10)

                // SECTION 2: Tambah Barang >
                Button {
                    activeSheet = .barang
                } label: {
                    HStack(spacing: 10) {
                        Text("Tambah Barang")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(colors.isDark ? colors.textPrimary : Color(hex: 0x0F2638))
                        Spacer()
                        if barangImagesCount > 0 {
                            Text("\(barangImagesCount) foto")
                                .font(.system(size: 11.5, weight: .bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(colors.primaryContainer)
                                .foregroundStyle(colors.onPrimaryContainer)
                                .clipShape(Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.isDark ? colors.textSecondary : Color(hex: 0x0F2638))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(colors.isDark ? colors.cardBorder : Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(colors.isDark ? 0.25 : 0.08), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)

                // SECTION 3: Kontainer (Perintah Lorong, Ya/Tidak, Waktu Mulai, Update & Selesai)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kontainer")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(sectionHeaderColor)
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Perintah Lorong")
                                .font(.system(size: 13.5))
                                .foregroundStyle(colors.textHint)
                            Spacer()
                            Text(perintahLorongDisplay)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(colors.textPrimary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Perintah lorong dilaksanakan")
                                .font(.system(size: 13.5))
                                .foregroundStyle(colors.textHint)

                            SiapRadioRow(label: "Ya", selected: lorongDilaksanakanYa, colors: colors) {
                                lorongDilaksanakanYa = true
                            }

                            SiapRadioRow(label: "Tidak", selected: !lorongDilaksanakanYa, colors: colors) {
                                lorongDilaksanakanYa = false
                            }
                        }

                        if !lorongDilaksanakanYa {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Alasan Tidak Lorong")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(colors.textHint)
                                if !alasanOptions.isEmpty {
                                    Menu {
                                        ForEach(alasanOptions, id: \.self) { opt in
                                            Button(opt) { alasanTidakLorong = opt }
                                        }
                                    } label: {
                                        HStack {
                                            Text(alasanTidakLorong == "-" || alasanTidakLorong.isEmpty ? "Pilih alasan tidak lorong..." : alasanTidakLorong)
                                                .font(.system(size: 13))
                                                .foregroundStyle(colors.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(colors.textHint)
                                        }
                                        .padding(10)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                } else {
                                    TextField("Alasan tidak dilaksanakan lorong", text: $alasanTidakLorong)
                                        .font(.system(size: 13))
                                        .padding(10)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }

                                if !teknikOptions.isEmpty {
                                    Text("Teknik Periksa")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(colors.textHint)
                                    Menu {
                                        ForEach(teknikOptions, id: \.self) { opt in
                                            Button(opt) { teknikPeriksa = opt }
                                        }
                                    } label: {
                                        HStack {
                                            Text(teknikPeriksa == "-" || teknikPeriksa.isEmpty ? "Pilih teknik periksa..." : teknikPeriksa)
                                                .font(.system(size: 13))
                                                .foregroundStyle(colors.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(colors.textHint)
                                        }
                                        .padding(10)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }

                        HStack {
                            Text("Waktu Mulai")
                                .font(.system(size: 13.5))
                                .foregroundStyle(colors.textHint)
                            Spacer()
                            Text(waktuMulaiText)
                                .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                    .padding(16)
                    .background(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(colors.isDark ? colors.cardBorder : Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(colors.isDark ? 0.28 : 0.08), radius: 8, x: 0, y: 3)
                    .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 26)
        }
        .onAppear {
            if selectedNokon.isEmpty { selectedNokon = initialNokon }
            if waktuMulaiText.isEmpty {
                let ip = pib.ipCeisa.trimmingCharacters(in: .whitespacesAndNewlines)
                waktuMulaiText = (!ip.isEmpty && ip != "-") ? ip : SiapCrypto.wibFormatter("yyyy-MM-dd HH:mm:ss").string(from: Date())
            }
            syncContainerFormState()
            locMgr.request()
        }
        .onDisappear {
            locMgr.stop()
        }
        .task {
            if selectedNokon.isEmpty { selectedNokon = initialNokon }
            await loadContainerData()
        }
        .confirmationDialog("Tambah Foto \(activeAddStep.sectionTitle)", isPresented: $showSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Ambil Foto (Kamera)") {
                    openCameraAfterDialog()
                }
            }
            Button("Pilih dari Galeri") {
                openGalleryAfterDialog()
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Kontainer \(selectedNokon) • \(activeAddStep.label)")
        }
        .fullScreenCover(isPresented: $showCameraCover, onDismiss: {
            flushCapturedDraft()
        }) {
            ZStack {
                Color.black.ignoresSafeArea()
                ImagePicker(sourceType: .camera) { img in
                    capturedDraftTemp = PendingPhotoUpload(step: activeAddStep, image: img)
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            flushCapturedDraft()
        }) { sheet in
            switch sheet {
            case .gallery:
                ImagePicker(sourceType: .photoLibrary) { img in
                    capturedDraftTemp = PendingPhotoUpload(step: activeAddStep, image: img)
                }
            case .confirm(let draft):
                UploadPhotoConfirmSheet(
                    pib: pib,
                    nokon: selectedNokon,
                    ukuran: activeContainer?.ukuranContainer ?? "",
                    step: draft.step,
                    image: draft.image,
                    existingCount: onlineImages.count,
                    locMgr: locMgr,
                    watermarkEnabled: $watermarkEnabled,
                    pelLorong: lorongDilaksanakanYa ? "1" : "0",
                    alasanLorong: lorongDilaksanakanYa ? "-" : alasanTidakLorong,
                    teknikPeriksa: teknikPeriksa,
                    colors: colors,
                    onOcrContainerDetected: { found in
                        selectedNokon = found
                    },
                    onUploaded: {
                        Task { await loadImages() }
                    }
                )
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
            case .barang:
                FotoBarangSheet(
                    pib: pib,
                    nokon: selectedNokon,
                    ukuran: activeContainer?.ukuranContainer ?? "",
                    onlineImages: onlineImages,
                    locMgr: locMgr,
                    watermarkEnabled: $watermarkEnabled,
                    pelLorong: lorongDilaksanakanYa ? "1" : "0",
                    alasanLorong: lorongDilaksanakanYa ? "-" : alasanTidakLorong,
                    teknikPeriksa: teknikPeriksa,
                    colors: colors,
                    onReloadImages: {
                        await loadImages()
                    },
                    onDeleteImage: { item in
                        deleteTarget = item
                    }
                )
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
            case .fullscreen(let item):
                FotoFullscreenSheet(
                    item: item,
                    onClose: { activeSheet = nil },
                    onRequestDelete: {
                        let target = item
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            deleteTarget = target
                        }
                    }
                )
            }
        }
        .alert("Hapus Foto?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Batal", role: .cancel) { deleteTarget = nil }
            Button("Hapus", role: .destructive) {
                if let target = deleteTarget {
                    Task {
                        do {
                            try await SiapApiClient.shared.deleteImage(imageId: target.id)
                            app.showToast("Foto berhasil dihapus")
                            await loadImages()
                        } catch {
                            app.showToast("Gagal hapus foto: \(error.localizedDescription)")
                        }
                        deleteTarget = nil
                    }
                }
            }
        } message: {
            Text("Hapus foto ini dari pemeriksaan kontainer \(selectedNokon)?")
        }
    }

    private func openCameraAfterDialog() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            let granted = await CameraPermissionHelper.ensureCameraAccess()
            if granted {
                showCameraCover = true
            } else {
                app.showToast("Izin kamera belum aktif — buka Pengaturan > SIAP NEO > Kamera")
            }
        }
    }

    private func openGalleryAfterDialog() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            activeSheet = .gallery
        }
    }

    private func flushCapturedDraft() {
        guard let draft = capturedDraftTemp else { return }
        capturedDraftTemp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            activeSheet = .confirm(draft)
        }
    }

    private func syncContainerFormState() {
        if let c = activeContainer {
            let p = c.pelaksanaanLorong.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if p == "1" || p == "ya" || p == "true" {
                lorongDilaksanakanYa = true
            } else if p == "0" || p == "tidak" || p == "false" {
                lorongDilaksanakanYa = (c.alasanLorong.isEmpty || c.alasanLorong == "-") ? true : false
            }
            if !c.alasanLorong.isEmpty && c.alasanLorong != "-" {
                alasanTidakLorong = c.alasanLorong
            }
            if !c.teknikPeriksa.isEmpty && c.teknikPeriksa != "-" {
                teknikPeriksa = c.teknikPeriksa
            }
        }
    }

    private func loadContainerData() async {
        async let imgTask: Void = loadImages()
        async let cekTask = SiapApiClient.shared.cekPelaksanaanLorong(kodeTiket: pib.kodeTiket, nokon: selectedNokon)
        async let alasanTask = SiapApiClient.shared.fetchAlasanTidakLorong()
        async let teknikTask = SiapApiClient.shared.fetchTeknikPeriksa()

        _ = await imgTask
        let cek = await cekTask
        let alasan = await alasanTask
        let teknik = await teknikTask

        if cek == "1" {
            lorongDilaksanakanYa = true
        }
        if !alasan.isEmpty { alasanOptions = alasan }
        if !teknik.isEmpty { teknikOptions = teknik }
    }

    private func loadImages() async {
        isLoadingImages = true
        defer { isLoadingImages = false }
        onlineImages = (try? await SiapApiClient.shared.fetchImages(kodeTiket: pib.kodeTiket, nokon: selectedNokon)) ?? []
    }
}

// MARK: - Reusable Category Strip Row (Dashed "+" Box + Horizontal Uploaded Thumbnails)

private struct FotoCategoryStripRow: View {
    let title: String
    let photos: [OnlineImageItem]
    let colors: SiapColors
    let onTapAdd: () -> Void
    let onTapPhoto: (OnlineImageItem) -> Void
    let onDeletePhoto: (OnlineImageItem) -> Void

    private var tileSize: CGFloat { 96 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.isDark ? colors.textPrimary : Color(hex: 0x0F2638))
                if !photos.isEmpty {
                    Text("(\(photos.count))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(colors.textHint)
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Photo "+" Tile with Dashed Inner Frame (Matches Screenshot)
                    Button(action: onTapAdd) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colors.isDark ? colors.surfaceElevated : Color(hex: 0xF0F1F4))
                                .frame(width: tileSize, height: tileSize)
                                .shadow(color: Color.black.opacity(colors.isDark ? 0.22 : 0.10), radius: 5, x: 0, y: 2)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(
                                    colors.isDark ? colors.textHint.opacity(0.85) : Color(hex: 0x3D4F6F),
                                    style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])
                                )
                                .frame(width: tileSize - 18, height: tileSize - 18)

                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(colors.isDark ? SiapColors.brandAmber : Color.white)
                                .shadow(color: Color.black.opacity(colors.isDark ? 0 : 0.08), radius: 1, y: 1)
                        }
                        .padding(.vertical, 3)
                        .padding(.leading, 2)
                    }
                    .buttonStyle(.plain)

                    // Uploaded Photos in Matching White/Surface Rounded Frames
                    ForEach(photos) { item in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                onTapPhoto(item)
                            } label: {
                                Group {
                                    if let url = item.resolvedURL {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img.resizable().scaledToFill()
                                            case .failure:
                                                ZStack {
                                                    colors.surfaceElevated
                                                    Image(systemName: "photo")
                                                        .foregroundStyle(colors.textHint)
                                                }
                                            default:
                                                ZStack {
                                                    colors.surfaceElevated
                                                    ProgressView().scaleEffect(0.75)
                                                }
                                            }
                                        }
                                    } else {
                                        colors.surfaceElevated
                                    }
                                }
                                .frame(width: tileSize - 8, height: tileSize - 8)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(4)
                                .background(colors.isDark ? colors.surfaceElevated : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color.black.opacity(colors.isDark ? 0.25 : 0.12), radius: 5, x: 0, y: 2)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)

                            Button {
                                onDeletePhoto(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(colors.danger)
                                    .background(Circle().fill(colors.surface).padding(1))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 3, y: -1)
                        }
                    }
                }
                .padding(.trailing, 6)
            }
        }
    }
}

// MARK: - Authentic Radio Button Row (Yellow-Gold Selected Ring)

private struct SiapRadioRow: View {
    let label: String
    let selected: Bool
    let colors: SiapColors
    let action: () -> Void

    private let activeGold = Color(hex: 0xEAB308)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(selected ? activeGold : colors.outline, lineWidth: 2)
                        .frame(width: 21, height: 21)
                    if selected {
                        Circle()
                            .fill(activeGold.opacity(0.22))
                            .frame(width: 17, height: 17)
                        Circle()
                            .fill(activeGold)
                            .frame(width: 9, height: 9)
                    }
                }
                Text(label)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Foto Barang & Detail Barang Sheet ("Tambah Barang >" — Format CEISA 4.0)

private struct FotoBarangSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let pib: PibDocument
    let nokon: String
    let ukuran: String
    let onlineImages: [OnlineImageItem]
    @ObservedObject var locMgr: LocationManager
    @Binding var watermarkEnabled: Bool
    let pelLorong: String
    let alasanLorong: String
    let teknikPeriksa: String
    let colors: SiapColors
    let onReloadImages: () async -> Void
    let onDeleteImage: (OnlineImageItem) -> Void

    @State private var activeStep: StepOption = StepOption.barangPhotoSteps[0]
    @State private var showSourceDialog = false
    @State private var showCameraCover = false
    @State private var activeSheet: BarangPanelSheet?
    @State private var capturedDraftTemp: PendingPhotoUpload?

    // CEISA 4.0 #detail__Barang form fields
    @State private var seriBarang = "1"
    @State private var uraianBarang = ""
    @State private var jumlahJenisKemasan = ""
    @State private var satuanBarang = "PCE"
    @State private var negaraAsal = ""
    @State private var negaraOptions: [String] = []
    @State private var kondisiBaru = true
    @State private var merk = ""
    @State private var model = ""
    @State private var tipe = ""

    private let quickUnits = ["PCE", "SET", "UNT", "KGM", "CTN", "PK"]

    private var sectionHeaderColor: Color {
        colors.isDark ? SiapColors.brandSky : Color(hex: 0x163A63)
    }

    private var navyActionColor: Color {
        colors.isDark ? Color(hex: 0x1E4B8A) : Color(hex: 0x0A2D63)
    }

    private var composedSpesifikasi: String {
        var parts: [String] = []
        let m = merk.trimmingCharacters(in: .whitespacesAndNewlines)
        let md = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let tp = tipe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { parts.append("Merek: \(m)") }
        if !md.isEmpty { parts.append("Model: \(md)") }
        if !tp.isEmpty { parts.append("Tipe: \(tp)") }
        parts.append("Kondisi: \(kondisiBaru ? "BARU" : "BUKAN BARU")")
        return parts.joined(separator: " | ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // SECTION 1: Foto Barang (CEISA 4.0 dashed '+' card layout)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Foto Barang")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(sectionHeaderColor)
                            .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(StepOption.barangPhotoSteps) { step in
                                let stepPhotos = onlineImages.filter { step.matches($0.ketPraPemeriksaan) }
                                FotoCategoryStripRow(
                                    title: step.sectionTitle,
                                    photos: stepPhotos,
                                    colors: colors,
                                    onTapAdd: {
                                        activeStep = step
                                        showSourceDialog = true
                                    },
                                    onTapPhoto: { item in
                                        activeSheet = .fullscreen(item)
                                    },
                                    onDeletePhoto: { item in
                                        onDeleteImage(item)
                                    }
                                )
                            }
                        }
                        .padding(14)
                        .background(colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(colors.isDark ? colors.cardBorder : Color.black.opacity(0.05), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.black.opacity(colors.isDark ? 0.25 : 0.08), radius: 8, x: 0, y: 3)
                        .padding(.horizontal, 14)
                    }
                    .padding(.top, 10)

                    // SECTION 2: Detail Barang (Format CEISA 4.0)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Detail Barang (Format CEISA 4.0)")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(sectionHeaderColor)
                            .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 12) {
                            // Seri Barang
                            HStack(spacing: 10) {
                                Text("Seri Barang")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.textHint)
                                Spacer()
                                HStack(spacing: 6) {
                                    Button {
                                        let cur = Int(seriBarang) ?? 1
                                        seriBarang = "\(max(1, cur - 1))"
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 12, weight: .bold))
                                            .frame(width: 30, height: 30)
                                            .background(colors.surfaceElevated)
                                            .foregroundStyle(colors.textPrimary)
                                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    TextField("1", text: $seriBarang)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(colors.textPrimary)
                                        .frame(width: 52, height: 30)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                    Button {
                                        let cur = Int(seriBarang) ?? 0
                                        seriBarang = "\(cur + 1)"
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                            .frame(width: 30, height: 30)
                                            .background(colors.surfaceElevated)
                                            .foregroundStyle(colors.textPrimary)
                                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Uraian Barang (multiline seperti textarea CEISA 4.0)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Uraian Barang")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(colors.textHint)
                                ZStack(alignment: .topLeading) {
                                    if uraianBarang.isEmpty {
                                        Text("Contoh: Barang berbentuk ..., berbahan menyerupai ..., berwarna ...")
                                            .font(.system(size: 13))
                                            .foregroundStyle(colors.textHint.opacity(0.7))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 10)
                                    }
                                    TextEditor(text: $uraianBarang)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(colors.textPrimary)
                                        .frame(minHeight: 74)
                                        .scrollContentBackground(.hidden)
                                        .padding(6)
                                }
                                .background(colors.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(colors.cardBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }

                            // Jumlah & Jenis Kemasan
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Jumlah & Jenis Kemasan")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(colors.textHint)
                                TextField("Contoh: 10 CT - Carton / 5 PK - Package", text: $jumlahJenisKemasan)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(colors.textPrimary)
                                    .padding(10)
                                    .background(colors.surfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(colors.cardBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }

                            // Satuan Barang
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Satuan Barang")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(colors.textHint)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(quickUnits, id: \.self) { u in
                                            let active = satuanBarang.uppercased() == u
                                            Button { satuanBarang = u } label: {
                                                Text(u)
                                                    .font(.system(size: 11.5, weight: .bold))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(active ? navyActionColor : colors.surfaceElevated)
                                                    .foregroundStyle(active ? .white : colors.textSecondary)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                TextField("Kode satuan (PCE / SET / KGM / UNT)", text: $satuanBarang)
                                    .textInputAutocapitalization(.characters)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(colors.textPrimary)
                                    .padding(10)
                                    .background(colors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }

                            Divider().overlay(colors.divider)

                            // Unsur Barang: Asal Negara & Kondisi Barang (CEISA 4.0)
                            Text("Unsur Barang")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(colors.textPrimary)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Asal Negara")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(colors.textHint)
                                if !negaraOptions.isEmpty {
                                    Menu {
                                        Button("Sesuai Dokumen (Kosong)") { negaraAsal = "" }
                                        ForEach(negaraOptions.prefix(80), id: \.self) { neg in
                                            Button(neg) { negaraAsal = neg }
                                        }
                                    } label: {
                                        HStack {
                                            Text(negaraAsal.isEmpty ? "Sesuai Dokumen / Pilih Negara Asal..." : negaraAsal)
                                                .font(.system(size: 13.5))
                                                .foregroundStyle(negaraAsal.isEmpty ? colors.textHint : colors.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(colors.textHint)
                                        }
                                        .padding(10)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    }
                                } else {
                                    TextField("Contoh: CHINA (kosongkan bila tidak tertera Made in)", text: $negaraAsal)
                                        .textInputAutocapitalization(.characters)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(colors.textPrimary)
                                        .padding(10)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Kondisi Barang")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(colors.textHint)
                                HStack(spacing: 16) {
                                    SiapRadioRow(label: "1 - BARU", selected: kondisiBaru, colors: colors) {
                                        kondisiBaru = true
                                    }
                                    SiapRadioRow(label: "2 - BUKAN BARU", selected: !kondisiBaru, colors: colors) {
                                        kondisiBaru = false
                                    }
                                }
                            }

                            Divider().overlay(colors.divider)

                            // Tabel Spesifikasi (Merek / Model / Tipe — Format CEISA 4.0)
                            Text("Spesifikasi (Merek / Model / Tipe)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(colors.textPrimary)

                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Merek").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                                    TextField("-", text: $merk)
                                        .font(.system(size: 13))
                                        .padding(9)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Model").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                                    TextField("-", text: $model)
                                        .font(.system(size: 13))
                                        .padding(9)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tipe").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                                    TextField("-", text: $tipe)
                                        .font(.system(size: 13))
                                        .padding(9)
                                        .background(colors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            // Watermark toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Watermark GPS + WIB")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(colors.textPrimary)
                                    Text("GPS: \(locMgr.coordinateText)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(colors.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $watermarkEnabled)
                                    .labelsHidden()
                                    .tint(navyActionColor)
                            }
                            .padding(.top, 2)

                            // Quick Capture Buttons (directly attaches all CEISA 4.0 fields!)
                            Button {
                                activeStep = StepOption.barangPhotoSteps[0]
                                openCameraDirect()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                    Text("AMBIL FOTO BARANG (KAMERA)")
                                        .font(.system(size: 13.5, weight: .bold))
                                        .tracking(0.3)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13.5)
                                .background(navyActionColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button {
                                activeStep = StepOption.barangPhotoSteps[0]
                                activeSheet = .gallery
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                    Text("PILIH FOTO BARANG DARI GALERI")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundStyle(navyActionColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colors.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(navyActionColor.opacity(0.4), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(colors.isDark ? colors.cardBorder : Color.black.opacity(0.05), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.black.opacity(colors.isDark ? 0.25 : 0.08), radius: 8, x: 0, y: 3)
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(colors.backdrop.ignoresSafeArea())
            .navigationTitle("Tambah Barang : \(nokon)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tutup") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                }
            }
        }
        .task {
            let list = await SiapApiClient.shared.fetchNegaraAsal()
            if !list.isEmpty { negaraOptions = list }
        }
        .confirmationDialog("Tambah \(activeStep.label)", isPresented: $showSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Ambil Foto (Kamera)") { openCameraAfterDialog() }
            }
            Button("Pilih dari Galeri") { openGalleryAfterDialog() }
            Button("Batal", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCameraCover, onDismiss: {
            flushCapturedDraft()
        }) {
            ZStack {
                Color.black.ignoresSafeArea()
                ImagePicker(sourceType: .camera) { img in
                    capturedDraftTemp = PendingPhotoUpload(step: activeStep, image: img)
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            flushCapturedDraft()
        }) { sheet in
            switch sheet {
            case .gallery:
                ImagePicker(sourceType: .photoLibrary) { img in
                    capturedDraftTemp = PendingPhotoUpload(step: activeStep, image: img)
                }
            case .confirm(let draft):
                UploadPhotoConfirmSheet(
                    pib: pib,
                    nokon: nokon,
                    ukuran: ukuran,
                    step: draft.step,
                    image: draft.image,
                    existingCount: onlineImages.count,
                    locMgr: locMgr,
                    watermarkEnabled: $watermarkEnabled,
                    pelLorong: pelLorong,
                    alasanLorong: alasanLorong,
                    teknikPeriksa: teknikPeriksa,
                    initialSeriBarang: seriBarang,
                    initialUraianBarang: uraianBarang,
                    initialJumlahKemasan: jumlahJenisKemasan,
                    initialSatuanBarang: satuanBarang,
                    initialNegaraAsal: negaraAsal,
                    initialSpesifikasi: composedSpesifikasi,
                    colors: colors,
                    onOcrContainerDetected: { _ in },
                    onUploaded: {
                        Task { await onReloadImages() }
                    }
                )
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
            case .fullscreen(let item):
                FotoFullscreenSheet(
                    item: item,
                    onClose: { activeSheet = nil },
                    onRequestDelete: {
                        let target = item
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onDeleteImage(target)
                        }
                    }
                )
            }
        }
    }

    private func openCameraDirect() {
        Task { @MainActor in
            let granted = await CameraPermissionHelper.ensureCameraAccess()
            if granted {
                showCameraCover = true
            } else {
                app.showToast("Izin kamera belum aktif — buka Pengaturan > SIAP NEO > Kamera")
            }
        }
    }

    private func openCameraAfterDialog() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            let granted = await CameraPermissionHelper.ensureCameraAccess()
            if granted {
                showCameraCover = true
            } else {
                app.showToast("Izin kamera belum aktif — buka Pengaturan > SIAP NEO > Kamera")
            }
        }
    }

    private func openGalleryAfterDialog() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            activeSheet = .gallery
        }
    }

    private func flushCapturedDraft() {
        guard let draft = capturedDraftTemp else { return }
        capturedDraftTemp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            activeSheet = .confirm(draft)
        }
    }
}

// MARK: - Upload Photo Preview & Confirmation Sheet

private struct UploadPhotoConfirmSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let pib: PibDocument
    let nokon: String
    let ukuran: String
    let step: StepOption
    let image: UIImage
    let existingCount: Int
    @ObservedObject var locMgr: LocationManager
    @Binding var watermarkEnabled: Bool
    let pelLorong: String
    let alasanLorong: String
    let teknikPeriksa: String
    var initialSeriBarang: String = ""
    var initialUraianBarang: String = ""
    var initialJumlahKemasan: String = ""
    var initialSatuanBarang: String = ""
    var initialNegaraAsal: String = ""
    var initialSpesifikasi: String = ""
    let colors: SiapColors
    let onOcrContainerDetected: (String) -> Void
    let onUploaded: () -> Void

    @State private var seriBarang = ""
    @State private var deskripsi = ""
    @State private var jumlahKemasan = ""
    @State private var satuanBarang = ""
    @State private var negaraAsal = ""
    @State private var spesifikasi = ""
    @State private var isUploading = false
    @State private var isOcrRunning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(colors.primaryAction)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.sectionTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(colors.textPrimary)
                            Text("Kontainer \(nokon) • \(step.label)")
                                .font(.system(size: 12))
                                .foregroundStyle(colors.textHint)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 270)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Watermark GPS + WIB")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(colors.textPrimary)
                                Text("GPS: \(locMgr.coordinateText)")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(colors.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $watermarkEnabled)
                                .labelsHidden()
                                .tint(colors.primaryAction)
                        }

                        if step.isBarangStep {
                            HStack(spacing: 8) {
                                TextField("Seri barang", text: $seriBarang)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 13.5))
                                    .padding(10)
                                    .background(colors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                TextField("Satuan (PCE/SET)", text: $satuanBarang)
                                    .textInputAutocapitalization(.characters)
                                    .font(.system(size: 13.5))
                                    .padding(10)
                                    .background(colors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }

                            TextField("Jumlah & jenis kemasan (opsional)", text: $jumlahKemasan)
                                .font(.system(size: 13.5))
                                .padding(10)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                            TextField("Asal negara (opsional)", text: $negaraAsal)
                                .textInputAutocapitalization(.characters)
                                .font(.system(size: 13.5))
                                .padding(10)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                            TextField("Spesifikasi (Merek / Model / Tipe / Kondisi)", text: $spesifikasi)
                                .font(.system(size: 13))
                                .padding(10)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        TextField(step.isBarangStep ? "Uraian barang (format CEISA 4.0)" : "Keterangan foto (opsional)", text: $deskripsi)
                            .font(.system(size: 13.5))
                            .foregroundStyle(colors.textPrimary)
                            .padding(11)
                            .background(colors.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(colors.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if !step.isBarangStep {
                            SiapOutlinedButton(
                                isOcrRunning ? "Memindai OCR..." : "OCR Nomor Kontainer",
                                icon: "viewfinder",
                                color: colors.secondary,
                                bg: colors.surfaceElevated
                            ) {
                                Task { await runOcr() }
                            }
                            .disabled(isOcrRunning)
                        }

                        SiapFilledButton(
                            isUploading ? "Mengunggah ke FTP & SIAP..." : "Unggah Foto Sekarang",
                            icon: "icloud.and.arrow.up.fill",
                            bg: Color(hex: 0x4BD367),
                            fg: .white,
                            isLoading: isUploading
                        ) {
                            Task { await performUpload() }
                        }
                        .disabled(isUploading)
                    }
                    .padding(14)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(14)
            }
            .background(colors.backdrop.ignoresSafeArea())
            .navigationTitle("Unggah Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Batal") { dismiss() }
                }
            }
            .onAppear {
                if seriBarang.isEmpty { seriBarang = initialSeriBarang }
                if deskripsi.isEmpty { deskripsi = initialUraianBarang }
                if jumlahKemasan.isEmpty { jumlahKemasan = initialJumlahKemasan }
                if satuanBarang.isEmpty { satuanBarang = initialSatuanBarang }
                if negaraAsal.isEmpty { negaraAsal = initialNegaraAsal }
                if spesifikasi.isEmpty { spesifikasi = initialSpesifikasi }
            }
        }
    }

    private func runOcr() async {
        isOcrRunning = true
        defer { isOcrRunning = false }
        if let found = await ContainerOcrScanner.scanContainerNumber(from: image) {
            onOcrContainerDetected(found)
            app.showToast("OCR Kontainer terdeteksi: \(found)")
        } else {
            app.showToast("Nomor kontainer tidak terdeteksi di foto")
        }
    }

    private func performUpload() async {
        isUploading = true
        defer { isUploading = false }
        let monthFolder = SiapCrypto.currentMonthYear()
        let waktu = SiapCrypto.currentExifTimestamp()
        let isLcl = pib.isLclDefault || nokon.uppercased() == "LCL"
        let fileName = SiapCrypto.buildInspectionFileName(
            kodeTiket: pib.kodeTiket,
            isLcl: isLcl,
            nokon: nokon,
            waktuFoto: waktu,
            stepLabel: step.label,
            stepCode: step.code,
            urutanBarang: "\(existingCount + 1)",
            ext: "jpg"
        )
        guard let jpegData = ImageWatermarkProcessor.process(
            image: image,
            watermark: watermarkEnabled,
            noPib: pib.noPib,
            nokon: nokon,
            stepLabel: step.label,
            lokasi: locMgr.coordinateText
        ) else {
            app.showToast("Gagal memproses gambar")
            return
        }
        do {
            _ = try await SiapFtpClient.shared.upload(remoteDir: monthFolder, remoteFilename: fileName, data: jpegData)
            _ = try await SiapApiClient.shared.insertImage(
                isLcl: isLcl,
                kodeTiket: pib.kodeTiket,
                nokon: nokon,
                urlImage: "\(monthFolder)/\(fileName)",
                stepLabel: step.label,
                seriBarang: seriBarang,
                ketSeriBarang: deskripsi,
                lokasi: locMgr.coordinateText,
                ukuran: ukuran,
                waktuFoto: waktu,
                uraianBarang: deskripsi,
                jumlahJenisKemasan: jumlahKemasan,
                pelLorong: pelLorong,
                alasanLorong: alasanLorong,
                teknikPeriksa: teknikPeriksa,
                satuanBarang: satuanBarang,
                negaraAsal: negaraAsal,
                spesifikasi: spesifikasi
            )
            app.showToast("Foto \(step.sectionTitle) berhasil diunggah!")
            onUploaded()
            dismiss()
        } catch {
            app.showToast("Upload gagal: \(error.localizedDescription)")
        }
    }
}

// MARK: - Fullscreen Image Preview Sheet

private struct FotoFullscreenSheet: View {
    let item: OnlineImageItem
    let onClose: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = item.resolvedURL {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.ketPraPemeriksaan.isEmpty ? "Foto #\(item.id)" : item.ketPraPemeriksaan)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        if !item.ketSeriBarang.isEmpty && item.ketSeriBarang != "-" {
                            Text(item.ketSeriBarang)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Spacer()
                    Button(action: onRequestDelete) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .bold))
                            .padding(10)
                            .background(Color.red.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    Button(action: onClose) {
                        Text("Tutup")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.22))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(16)
                .background(Color.black.opacity(0.45))
                Spacer()
            }
        }
    }
}

// MARK: - Dedicated TTD PJ Modal Sheet (High-Contrast Dark/Light!)

struct TtdPjModalSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let pib: PibDocument
    let colors: SiapColors

    @StateObject private var sigStore = SignatureStrokeStore()
    @State private var namaPj = ""
    @State private var isUploading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tanda Tangan PJ (PPJK / Importir)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("PIB \(pib.noPib) • \(pib.importir)")
                        .font(.system(size: 12))
                        .foregroundStyle(SiapColors.hintOnNavy)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Tutup")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(colors.headerGradient)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nama Pengurus (PJ)")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(colors.textSecondary)
                        TextField("Masukkan nama pengurus / PJ", text: $namaPj)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                            .padding(12)
                            .background(colors.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(colors.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Goreskan Tanda Tangan di Area Putih")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(colors.textSecondary)

                        SignaturePadView(store: sigStore)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(colors.primaryAction.opacity(0.6), lineWidth: 1.5)
                            )
                    }

                    HStack(spacing: 10) {
                        SiapOutlinedButton("Hapus", icon: "eraser.fill", color: colors.danger, bg: colors.danger.opacity(0.1)) {
                            sigStore.clear()
                        }
                        .frame(width: 115)

                        SiapFilledButton(
                            isUploading ? "Mengunggah..." : "Upload TTD PJ",
                            icon: "checkmark.circle.fill",
                            bg: colors.primaryAction,
                            fg: colors.onPrimaryAction,
                            isLoading: isUploading
                        ) {
                            Task { await uploadTtd() }
                        }
                        .disabled(isUploading || namaPj.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(16)
            }
            .background(colors.backdrop)
        }
        .onAppear {
            if namaPj.isEmpty && pib.namaPj != "-" {
                namaPj = pib.namaPj
            }
        }
    }

    private func uploadTtd() async {
        let cleanName = namaPj.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            app.showToast("Nama Pengurus wajib diisi")
            return
        }
        guard !sigStore.strokes.isEmpty else {
            app.showToast("Silakan tanda tangan terlebih dahulu")
            return
        }
        isUploading = true
        defer { isUploading = false }
        let monthFolder = SiapCrypto.currentMonthYear()
        let fileName = "ttd_\(SiapCrypto.sanitizeToken(pib.kodeTiket))_\(Int(Date().timeIntervalSince1970)).png"
        guard let pngData = sigStore.renderImage().pngData() else { return }
        do {
            _ = try await SiapFtpClient.shared.upload(remoteDir: monthFolder, remoteFilename: fileName, data: pngData)
            try await SiapApiClient.shared.insertTtdPj(kodeTiket: pib.kodeTiket, namaPj: cleanName, relUrl: "\(monthFolder)/\(fileName)")
            app.showToast("TTD PJ berhasil diunggah!")
            dismiss()
        } catch {
            app.showToast("Gagal upload TTD PJ: \(error.localizedDescription)")
        }
    }
}

// MARK: - Native Authenticated Dokap / Lampiran PDF Viewer (Matches Android DocumentViewerKt)

struct DokapViewerPanel: View {
    @EnvironmentObject var app: AppState
    let target: DokapTarget
    let colors: SiapColors

    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var downloaded: SiapApiClient.DownloadedDocument?
    @State private var rotation = 0
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 0) {
            // Document Toolbar (Rotate 90°, Reload, Share/Save PDF)
            HStack(spacing: 8) {
                Button {
                    rotation = (rotation + 90) % 360
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rotate.right")
                        Text("Putar")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.surfaceElevated)
                    .foregroundStyle(colors.textPrimary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(downloaded == nil)

                Button {
                    Task { await loadDocument() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Muat Ulang")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.surfaceElevated)
                    .foregroundStyle(colors.textPrimary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                if downloaded != nil {
                    Button {
                        showShare = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Bagikan")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(colors.primaryAction)
                        .foregroundStyle(colors.onPrimaryAction)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(colors.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(colors.divider).frame(height: 0.75)
            }

            // Document Content
            ZStack {
                colors.backdrop.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(colors.primaryAction).scaleEffect(1.2)
                        Text("Mengunduh \(target.title)...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                        Text("Menggunakan sesi terautentikasi SIAP 3.0")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.textHint)
                    }
                } else if let errorMsg {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.badge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(colors.danger)
                        Text("Gagal Memuat Dokumen")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                        Text(errorMsg)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        HStack(spacing: 10) {
                            SiapFilledButton("Coba Lagi", icon: "arrow.clockwise", bg: colors.primaryAction, fg: colors.onPrimaryAction) {
                                Task { await loadDocument() }
                            }
                            .frame(width: 140)
                            SiapOutlinedButton("Buka Safari", icon: "safari", color: colors.secondary) {
                                UIApplication.shared.open(target.url)
                            }
                            .frame(width: 140)
                        }
                    }
                } else if let doc = downloaded {
                    if doc.isImage, let img = UIImage(contentsOfFile: doc.localURL.path) {
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .rotationEffect(.degrees(Double(rotation)))
                                .padding()
                        }
                    } else {
                        SiapPdfKitView(url: doc.localURL, rotationDegrees: rotation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: target.id) {
            await loadDocument()
        }
        .sheet(isPresented: $showShare) {
            if let url = downloaded?.localURL {
                SiapShareSheet(items: [url])
            }
        }
    }

    private func loadDocument() async {
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        let user = app.session?.username ?? ""
        let pass = app.session?.password ?? ""
        let email = app.session?.usernameEmail ?? ""
        do {
            downloaded = try await SiapApiClient.shared.downloadDocumentFile(
                urlStr: target.url.absoluteString,
                username: user,
                password: pass,
                fallbackEmail: email
            )
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Manual PIB Modal Sheet

struct ManualPibSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let colors: SiapColors

    @State private var noPib = ""
    @State private var tglDate = Date()
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tambah Dokumen PIB Manual")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Tutup")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(colors.headerGradient)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nomor PIB (6 digit)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textSecondary)
                    TextField("Masukkan Nomor PIB...", text: $noPib)
                        .keyboardType(.numberPad)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(colors.textPrimary)
                        .padding(12)
                        .background(colors.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(colors.cardBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tanggal PIB")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textSecondary)
                    DatePicker("Tanggal PIB", selection: $tglDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(colors.primaryAction)
                        .padding(10)
                        .background(colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                SiapFilledButton(
                    isSaving ? "Menyimpan..." : "Simpan Dokumen Manual",
                    icon: "checkmark.circle.fill",
                    bg: colors.primaryAction,
                    fg: colors.onPrimaryAction,
                    isLoading: isSaving
                ) {
                    Task { await saveManual() }
                }
                .disabled(isSaving || noPib.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(16)
            .background(colors.backdrop)
        }
    }

    private func saveManual() async {
        guard let nip = app.session?.nip else { return }
        isSaving = true
        defer { isSaving = false }
        let df = SiapCrypto.wibFormatter("yyyy-MM-dd")
        do {
            try await SiapApiClient.shared.insertDokManual(
                nip: nip,
                noPib: noPib.trimmingCharacters(in: .whitespacesAndNewlines),
                tglPib: df.string(from: tglDate)
            )
            app.showToast("Dokumen PIB manual ditambahkan!")
            await app.loadPibs()
            dismiss()
        } catch {
            app.showToast("Gagal simpan: \(error.localizedDescription)")
        }
    }
}

// MARK: - Tab 2: Instruksi Pemeriksaan (Daftar IP Sudah Diperiksa + Aju Barcon + Instruksi Lorong)

struct LorongTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @State private var subMode = 0 // 0 = Daftar IP (SIAP 3.0), 1 = Instruksi Lorong
    @State private var ipQuery = ""
    @State private var ipFilter = 0 // 0 = Semua, 1 = Sudah BAP, 2 = Belum BAP
    @State private var lorongQuery = ""

    private var sudahBapCount: Int { app.assignedIps.filter(\.isSudahBap).count }
    private var belumBapCount: Int { app.assignedIps.filter { !$0.isSudahBap }.count }

    private var filteredIps: [AssignedIpItem] {
        let q = ipQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return app.assignedIps.filter { item in
            if ipFilter == 1 && !item.isSudahBap { return false }
            if ipFilter == 2 && item.isSudahBap { return false }
            if q.isEmpty { return true }
            return item.noPib.lowercased().contains(q)
                || item.importir.lowercased().contains(q)
                || item.tps.lowercased().contains(q)
                || item.kodeTiket.lowercased().contains(q)
                || item.status.lowercased().contains(q)
        }
    }

    private var filteredLorong: [InstruksiLorongItem] {
        let q = lorongQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return app.lorongItems }
        return app.lorongItems.filter {
            $0.noContainer.lowercased().contains(q)
                || $0.noPib.lowercased().contains(q)
                || $0.instruksiLorong.lowercased().contains(q)
                || $0.status.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                // Mode Switcher: Daftar IP (Sudah Diperiksa) | Instruksi Lorong
                HStack(spacing: 6) {
                    BrowseSegmentPill(title: "Daftar IP (\(app.assignedIps.count))", active: subMode == 0, colors: colors) {
                        subMode = 0
                        if app.assignedIps.isEmpty { Task { await app.loadAssignedIps(query: ipQuery, reset: true) } }
                    }
                    BrowseSegmentPill(title: "Instruksi Lorong (\(app.lorongItems.count))", active: subMode == 1, colors: colors) {
                        subMode = 1
                        if app.lorongItems.isEmpty { Task { await app.loadLorong() } }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                if subMode == 0 {
                    // Search + Server Search + Refresh
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(colors.textHint)
                            TextField("Cari No PIB, Importir, TPS...", text: $ipQuery)
                                .font(.system(size: 13.5))
                                .foregroundStyle(colors.textPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { Task { await app.loadAssignedIps(query: ipQuery, reset: true) } }
                            if !ipQuery.isEmpty {
                                Button {
                                    ipQuery = ""
                                    Task { await app.loadAssignedIps(query: "", reset: true) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(colors.textHint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(11)
                        .background(colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        Button {
                            Task { await app.loadAssignedIps(query: ipQuery, reset: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colors.onPrimaryAction)
                                .padding(11)
                                .background(colors.primaryAction)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(app.isLoadingAssignedIps)
                    }
                    .padding(.horizontal, 12)

                    // Status Filter Chips (Semua | Sudah BAP | Belum BAP)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            IpFilterChip(title: "Terbaru (\(app.assignedIps.count))", active: ipFilter == 0, colors: colors) { ipFilter = 0 }
                            IpFilterChip(title: "Sudah BAP (\(sudahBapCount))", active: ipFilter == 1, colors: colors) { ipFilter = 1 }
                            IpFilterChip(title: "Belum BAP (\(belumBapCount))", active: ipFilter == 2, colors: colors) { ipFilter = 2 }
                        }
                        .padding(.horizontal, 12)
                    }

                    if let err = app.assignedIpError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err).font(.system(size: 12))
                        }
                        .foregroundStyle(colors.danger)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.danger.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .padding(.horizontal, 12)
                    }

                    if app.isLoadingAssignedIps && app.assignedIps.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView().tint(colors.primaryAction).scaleEffect(1.1)
                            Text("Memuat Daftar IP Terbaru dari SIAP 3.0...")
                                .font(.system(size: 13))
                                .foregroundStyle(colors.textSecondary)
                        }
                        .padding(.vertical, 42)
                    } else if filteredIps.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundStyle(colors.textHint)
                            Text("Belum ada Daftar IP ditemukan")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(colors.textPrimary)
                            SiapOutlinedButton("Muat Ulang Daftar IP", icon: "arrow.clockwise", color: colors.primaryAction) {
                                Task { await app.loadAssignedIps(query: ipQuery, reset: true) }
                            }
                            .frame(maxWidth: 210)
                        }
                        .padding(26)
                        .frame(maxWidth: .infinity)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 12)
                    } else {
                        ForEach(filteredIps) { item in
                            AssignedIpCardView(item: item, colors: colors)
                                .padding(.horizontal, 12)
                        }

                        if app.assignedIpHasMore {
                            SiapOutlinedButton(
                                app.isLoadingAssignedIps ? "Memuat..." : "Tampilkan 15 IP Lagi",
                                icon: "plus.circle.fill",
                                color: colors.primaryAction,
                                bg: colors.surface
                            ) {
                                Task { await app.loadAssignedIps(query: ipQuery, reset: false) }
                            }
                            .disabled(app.isLoadingAssignedIps)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        }
                    }
                } else {
                    // Secondary Sub-Tab: Instruksi Lorong (detailkontainer_nip)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(colors.textHint)
                        TextField("Cari Kontainer, PIB, Instruksi...", text: $lorongQuery)
                            .font(.system(size: 13.5))
                            .foregroundStyle(colors.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !lorongQuery.isEmpty {
                            Button { lorongQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(colors.textHint)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            Task { await app.loadLorong() }
                        } label: {
                            Image(systemName: "arrow.clockwise").foregroundStyle(colors.primaryAction)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(11)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)

                    if app.isLoadingLorong && app.lorongItems.isEmpty {
                        ProgressView("Memuat Instruksi Lorong...").tint(colors.primaryAction).padding(.top, 40)
                    } else if filteredLorong.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "shippingbox").font(.system(size: 36)).foregroundStyle(colors.textHint)
                            Text("Belum ada Instruksi Lorong").font(.system(size: 15, weight: .bold)).foregroundStyle(colors.textPrimary)
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 12)
                    } else {
                        ForEach(filteredLorong) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.noContainer)
                                        .font(.system(size: 15.5, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(colors.textPrimary)
                                    if !item.ukuranContainer.isEmpty && item.ukuranContainer != "-" {
                                        Text("UK \(item.ukuranContainer)")
                                            .font(.system(size: 11, weight: .bold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(colors.primaryContainer)
                                            .foregroundStyle(colors.onPrimaryContainer)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    SiapStatusChip(text: item.status, colors: colors)
                                }

                                HStack(spacing: 8) {
                                    Text("PIB \(item.noPib) • \(SiapCrypto.formatDisplayDate(item.tglPib))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(colors.textSecondary)
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = item.noContainer
                                        app.showToast("Disalin: \(item.noContainer)")
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12.5, weight: .bold))
                                            .foregroundStyle(colors.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if !item.instruksiLorong.isEmpty && item.instruksiLorong != "-" {
                                    SiapMetaRow(label: "Instruksi", value: item.instruksiLorong, colors: colors)
                                }
                                if !item.pelaksanaanLorong.isEmpty && item.pelaksanaanLorong != "-" {
                                    SiapMetaRow(label: "Pelaksanaan", value: item.pelaksanaanLorong, colors: colors)
                                }
                                if !item.alasanLorong.isEmpty && item.alasanLorong != "-" {
                                    SiapMetaRow(label: "Alasan", value: item.alasanLorong, colors: colors)
                                }
                            }
                            .padding(13)
                            .background(colors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .refreshable {
            if subMode == 0 {
                await app.loadAssignedIps(query: ipQuery, reset: true)
            } else {
                await app.loadLorong()
            }
        }
        .task {
            if app.assignedIps.isEmpty && app.session != nil {
                await app.loadAssignedIps(query: ipQuery, reset: true)
            }
        }
    }
}

struct IpFilterChip: View {
    let title: String
    let active: Bool
    let colors: SiapColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? colors.primaryAction : colors.surface)
                .foregroundStyle(active ? colors.onPrimaryAction : colors.textSecondary)
                .overlay(Capsule().stroke(active ? Color.clear : colors.cardBorder, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Authentic Android AssignedIpCard (Dokumen Sudah Diperiksa + Aju Barcon + Lihat BAP + Kendala)

struct AssignedIpCardView: View {
    @EnvironmentObject var app: AppState
    let item: AssignedIpItem
    let colors: SiapColors

    var body: some View {
        let pibDoc = item.toPibDocument()
        let st = colors.statusBadgeStyle(for: item.status)
        let barconDone = app.isBarconSubmitted(for: pibDoc)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(st.accent)
                    .frame(width: 4.5)

                VStack(alignment: .leading, spacing: 9) {
                    // Tap header to open full Detail PIB / Lampiran / Foto
                    Button {
                        if let existing = app.pibs.first(where: { $0.noPib.filter(\.isNumber) == item.noPib.filter(\.isNumber) }) {
                            app.openPib(existing)
                        } else {
                            app.openPib(pibDoc)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("PIB \(item.noPib)")
                                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                                            .foregroundStyle(colors.textPrimary)

                                        Text(item.jenisKontainer)
                                            .font(.system(size: 10, weight: .heavy))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(colors.primaryContainer)
                                            .foregroundStyle(colors.onPrimaryContainer)
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    }
                                    Text(SiapCrypto.formatDisplayDate(item.tglPib))
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(colors.textHint)
                                }
                                Spacer(minLength: 4)
                                SiapStatusChip(text: item.status, colors: colors)
                            }

                            Text(item.importir)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(colors.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    if !item.tps.isEmpty && item.tps != "-" {
                                        SiapMetaTag(icon: "building.2.fill", text: "TPS \(item.tps)", bg: colors.surfaceElevated, fg: colors.textSecondary)
                                    }
                                    if !item.jumlahKontainer.isEmpty && item.jumlahKontainer != "-" {
                                        SiapMetaTag(icon: "shippingbox", text: item.jumlahKontainer, bg: colors.surfaceElevated, fg: colors.secondary)
                                    }
                                    if !item.waktuIp.isEmpty && item.waktuIp != "-" {
                                        SiapMetaTag(icon: "clock.fill", text: item.waktuIp, bg: colors.surfaceElevated, fg: colors.textHint)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(colors.divider)

                    // Action Buttons Row (Exact Android AssignedIpCard: Aju Barcon | Lihat/Isi BAP | Kendala)
                    HStack(spacing: 7) {
                        Button {
                            app.openBarconForm(for: pibDoc)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: barconDone ? "checkmark.circle.fill" : "shippingbox.fill")
                                    .font(.system(size: 11.5, weight: .bold))
                                Text(barconDone ? "Barcon Diajukan" : "Aju Barcon")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(barconDone ? colors.success.opacity(0.18) : colors.primaryAction)
                            .foregroundStyle(barconDone ? colors.success : colors.onPrimaryAction)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(barconDone ? colors.success.opacity(0.55) : Color.clear, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if item.isSudahBap {
                            Button {
                                if let u = URL(string: item.linkCetakBap), !item.linkCetakBap.isEmpty {
                                    app.activeDokap = DokapTarget(title: "BAP • PIB \(item.noPib)", url: u)
                                } else {
                                    Task { await app.openBapForPib(pibDoc) }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.richtext.fill")
                                        .font(.system(size: 11.5, weight: .bold))
                                    Text("Lihat BAP")
                                        .font(.system(size: 11.5, weight: .bold))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(colors.primaryContainer)
                                .foregroundStyle(colors.onPrimaryContainer)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else if !item.linkBuatBap.isEmpty, let u = URL(string: item.linkBuatBap) {
                            Button {
                                UIApplication.shared.open(u)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 11.5, weight: .bold))
                                    Text("Isi BAP")
                                        .font(.system(size: 11.5, weight: .bold))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(colors.secondary.opacity(0.18))
                                .foregroundStyle(colors.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            app.openKendalaTemuanForm(for: pibDoc)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.bubble.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Kendala")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 9)
                            .background(colors.surfaceElevated)
                            .foregroundStyle(colors.textSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(colors.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(colors.isDark ? 0.22 : 0.05), radius: 5, y: 2)
    }
}

// MARK: - Tab 3: Browse Pendok MK (Lampiran Dokumen) & Browse PIB

struct BrowseTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @State private var mode = 0
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var pibResults: [PibDocument] = []
    @State private var pendokResults: [PendokBrowseItem] = []
    @State private var expandedActionId: String?
    @State private var attachmentsByKode: [String: [PendokDocumentAttachment]] = [:]
    @State private var loadingKode: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Return-to-TPS Banner when launched from Monitoring TPS
                if app.browseReturnToTps {
                    HStack(spacing: 8) {
                        Button {
                            app.browseReturnToTps = false
                            app.activeTab = .tps
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                Text("Kembali ke Monitoring TPS")
                            }
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(colors.onPrimaryContainer)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            app.browseReturnToTps = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(colors.textHint)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(colors.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                }

                // Segmented Pill Switcher
                HStack(spacing: 6) {
                    BrowseSegmentPill(title: "Pendok MK (Lampiran)", active: mode == 0, colors: colors) {
                        mode = 0
                        if pendokResults.isEmpty || !query.isEmpty { Task { await search() } }
                    }
                    BrowseSegmentPill(title: "Browse PIB", active: mode == 1, colors: colors) {
                        mode = 1
                        if !query.isEmpty { Task { await search() } }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, app.browseReturnToTps ? 2 : 10)

                // Search Row
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(colors.textHint)
                        TextField(mode == 0 ? "Cari No PIB / Importir / Aju..." : "Masukkan No. PIB...", text: $query)
                            .font(.system(size: 13.5))
                            .foregroundStyle(colors.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await search() } }
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(colors.textHint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(11)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Button {
                        Task { await search() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                            Text("Cari")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(colors.primaryAction)
                        .foregroundStyle(colors.onPrimaryAction)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
                .padding(.horizontal, 12)

                if let errorMsg {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMsg).font(.system(size: 12.5))
                    }
                    .foregroundStyle(colors.danger)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.danger.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .padding(.horizontal, 12)
                }

                if isLoading {
                    ProgressView(mode == 0 ? "Memuat Pendok MK SIAP 3.0..." : "Mencari PIB...")
                        .tint(colors.primaryAction)
                        .padding(.top, 30)
                } else if mode == 0 {
                    if pendokResults.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundStyle(colors.textHint)
                            Text("Belum ada data Pendok MK ditampilkan.")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colors.textPrimary)
                            SiapOutlinedButton("Muat Data Pendok MK", icon: "arrow.clockwise", color: colors.primaryAction) {
                                Task { await search() }
                            }
                            .frame(maxWidth: 220)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 12)
                    } else {
                        ForEach(pendokResults) { item in
                            let isExpanded = expandedActionId == item.actionId
                            let atts = attachmentsByKode[item.actionId]
                            PendokBrowseCardView(
                                item: item,
                                colors: colors,
                                isExpanded: isExpanded,
                                isLoadingAttachments: loadingKode == item.actionId,
                                attachments: atts,
                                onToggleAttachments: {
                                    if isExpanded {
                                        expandedActionId = nil
                                    } else {
                                        expandedActionId = item.actionId
                                        if atts == nil {
                                            Task { await loadAttachments(for: item) }
                                        }
                                    }
                                },
                                onOpenAttachment: { att in
                                    if let u = URL(string: att.fileUrl) {
                                        app.activeDokap = DokapTarget(title: "\(att.namaDokumen) • PIB \(item.noPib)", url: u)
                                    }
                                }
                            )
                            .padding(.horizontal, 12)
                        }
                    }
                } else {
                    if pibResults.isEmpty {
                        Text("Masukkan nomor PIB lalu tekan Cari.")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textHint)
                            .padding(.top, 30)
                    } else {
                        ForEach(pibResults) { doc in
                            PibGridCardView(
                                doc: doc,
                                colors: colors,
                                isCompact: app.isCompact,
                                onTap: { app.openPib(doc) },
                                onWhatsAppPfpd: { app.openWhatsApp(phone: doc.noHpPfpd, message: "Konfirmasi PIB \(doc.noPib)") },
                                onWhatsAppPj: { app.openWhatsApp(phone: doc.hpPj, message: "Konfirmasi PIB \(doc.noPib)") },
                                onBatal: {}
                            )
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .task {
            if let pending = app.pendingBrowseQuery, !pending.isEmpty {
                let autoExpand = app.pendingBrowseAutoExpand
                app.pendingBrowseQuery = nil
                app.pendingBrowseAutoExpand = false
                mode = 0
                query = pending
                await search(autoExpandFirst: autoExpand)
            } else if mode == 0 && pendokResults.isEmpty && app.session != nil {
                await search()
            }
        }
        .onChange(of: app.pendingBrowseQuery) { newVal in
            guard let pending = newVal, !pending.isEmpty else { return }
            let autoExpand = app.pendingBrowseAutoExpand
            app.pendingBrowseQuery = nil
            app.pendingBrowseAutoExpand = false
            mode = 0
            query = pending
            Task { await search(autoExpandFirst: autoExpand) }
        }
    }

    private func search(autoExpandFirst: Bool = false) async {
        guard let sess = app.session else { return }
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if mode == 0 {
                let results = try await SiapApiClient.shared.browsePendok(
                    username: sess.username,
                    password: sess.password,
                    fallbackEmail: sess.usernameEmail,
                    query: q,
                    start: 0,
                    length: 30
                )
                pendokResults = results
                if autoExpandFirst, let first = results.first {
                    expandedActionId = first.actionId
                    await loadAttachments(for: first)
                }
            } else {
                pibResults = try await SiapApiClient.shared.browsePibData(nip: sess.nip, noPib: q)
            }
        } catch {
            errorMsg = error.localizedDescription
            app.showToast("Gagal memuat: \(error.localizedDescription)")
        }
    }

    private func loadAttachments(for item: PendokBrowseItem) async {
        guard let sess = app.session else { return }
        loadingKode = item.actionId
        defer { if loadingKode == item.actionId { loadingKode = nil } }
        do {
            let list = try await SiapApiClient.shared.fetchPendokAttachments(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                kodePelayanan: item.actionId
            )
            attachmentsByKode[item.actionId] = list
            if list.isEmpty {
                app.showToast("Belum ada lampiran PDF di SIAP 3.0 untuk PIB \(item.noPib)")
            }
        } catch {
            app.showToast("Gagal ambil lampiran: \(error.localizedDescription)")
        }
    }
}

struct PendokBrowseCardView: View {
    let item: PendokBrowseItem
    let colors: SiapColors
    let isExpanded: Bool
    let isLoadingAttachments: Bool
    let attachments: [PendokDocumentAttachment]?
    let onToggleAttachments: () -> Void
    let onOpenAttachment: (PendokDocumentAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("PIB \(item.noPib)")
                            .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        if !item.jalur.isEmpty && item.jalur != "-" {
                            Text(item.jalur)
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colors.primaryContainer)
                                .foregroundStyle(colors.onPrimaryContainer)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    if !item.tglPib.isEmpty {
                        Text(item.tglPib)
                            .font(.system(size: 11.5))
                            .foregroundStyle(colors.textHint)
                    }
                }
                Spacer()
                SiapStatusChip(text: item.status, colors: colors)
            }

            if !item.namaImportir.isEmpty {
                Text(item.namaImportir)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if !item.pfpd.isEmpty && item.pfpd != "-" {
                    SiapMetaTag(icon: "person.fill", text: item.pfpd, bg: colors.surfaceElevated, fg: colors.textSecondary)
                }
                if !item.actionId.isEmpty {
                    SiapMetaTag(icon: "number", text: "Kode \(item.actionId)", bg: colors.surfaceElevated, fg: colors.textHint)
                }
            }

            if item.isDitolak && !item.alasanPenolakan.isEmpty {
                Text(item.alasanPenolakan)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(colors.danger)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.danger.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button(action: onToggleAttachments) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text(isExpanded ? "Tutup Lampiran Dokumen" : "Lihat Lampiran Dokumen")
                    Spacer()
                    if isLoadingAttachments {
                        ProgressView().tint(colors.onPrimaryAction).scaleEffect(0.8)
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                .font(.system(size: 12.5, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isExpanded ? colors.primaryContainer : colors.primaryAction)
                .foregroundStyle(isExpanded ? colors.onPrimaryContainer : colors.onPrimaryAction)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isLoadingAttachments {
                    HStack(spacing: 8) {
                        ProgressView().tint(colors.primaryAction)
                        Text("Mengambil daftar lampiran dokumen...")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .padding(.vertical, 6)
                } else if let list = attachments, !list.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(list) { att in
                            Button {
                                onOpenAttachment(att)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.richtext.fill")
                                        .foregroundStyle(colors.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(att.namaDokumen)
                                            .font(.system(size: 12.5, weight: .bold))
                                            .foregroundStyle(colors.textPrimary)
                                            .lineLimit(2)
                                        if !att.tglUpload.isEmpty {
                                            Text(att.tglUpload)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(colors.textHint)
                                        }
                                    }
                                    Spacer()
                                    Text("Buka PDF")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(colors.secondary.opacity(0.18))
                                        .foregroundStyle(colors.secondary)
                                        .clipShape(Capsule())
                                }
                                .padding(9)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    Text("Tidak ada file lampiran untuk dokumen ini.")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textHint)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(13)
        .background(colors.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct BrowseSegmentPill: View {
    let title: String
    let active: Bool
    let colors: SiapColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? colors.primaryAction : colors.surface)
                .foregroundStyle(active ? colors.onPrimaryAction : colors.textSecondary)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(active ? Color.clear : colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 4: TPS Monitoring Hub (Matches TpsMonitoringScreensKt)

struct TpsTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @State private var source: TpsSource = .graha
    @State private var items: [TpsMonitorItem] = []
    @State private var isLoading = false
    @State private var onlyMyTasks = false
    @State private var searchText = ""
    @State private var lampiranSheetItem: TpsMonitorItem?

    private var myTaskCount: Int { items.filter(\.isMyTask).count }

    private var filtered: [TpsMonitorItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { it in
            if onlyMyTasks && !it.isMyTask { return false }
            if q.isEmpty { return true }
            return it.container.lowercased().contains(q)
                || it.pib.lowercased().contains(q)
                || it.importir.lowercased().contains(q)
                || it.summary.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact TPS Ribbon Bar (GRAHA | NPCT1 | TPSL)
            HStack(spacing: 6) {
                ForEach(TpsSource.allCases) { s in
                    let active = source == s
                    Button {
                        source = s
                    } label: {
                        Text(s.rawValue)
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(active ? colors.primaryAction : colors.surfaceElevated)
                            .foregroundStyle(active ? colors.onPrimaryAction : colors.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(colors.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(colors.divider).frame(height: 0.75)
            }

            ScrollView {
                LazyVStack(spacing: 9) {
                    // Search + Tugas Saya ★ + Refresh
                    HStack(spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(colors.textHint)
                            TextField("Cari Kontainer / PIB...", text: $searchText)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.textPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            onlyMyTasks.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: onlyMyTasks ? "star.fill" : "star")
                                Text("Tugas (\(myTaskCount))")
                            }
                            .font(.system(size: 11.5, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(onlyMyTasks ? colors.myTaskBg : colors.surface)
                            .foregroundStyle(onlyMyTasks ? colors.myTaskText : colors.textSecondary)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(onlyMyTasks ? colors.myTaskBorder : colors.cardBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colors.primaryAction)
                                .padding(9)
                                .background(colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    HStack {
                        Text("Tot: \(filtered.count) kontainer")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(colors.textHint)
                        Spacer()
                    }
                    .padding(.horizontal, 14)

                    if isLoading {
                        ProgressView("Memuat \(source.rawValue)...").tint(colors.primaryAction).padding(.top, 36)
                    } else if filtered.isEmpty {
                        Text("Tidak ada data antrian di \(source.rawValue).")
                            .font(.system(size: 13.5))
                            .foregroundStyle(colors.textHint)
                            .padding(.top, 36)
                    } else {
                        ForEach(filtered) { item in
                            let browseTarget = !item.pib.isEmpty ? item.pib : (!item.importir.isEmpty ? item.importir : item.container)
                            let browseLabel = !item.pib.isEmpty ? "Cari PIB \(item.pib) di Browse" : "Cari di Browse"

                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    app.openPibFromTps(noPib: item.pib, fallbackQuery: browseTarget)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            if item.isMyTask {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(SiapColors.brandAmber)
                                            }
                                            Text(item.container)
                                                .font(.system(size: 14.5, weight: .heavy, design: .monospaced))
                                                .foregroundStyle(item.isMyTask ? colors.myTaskText : colors.textPrimary)
                                            Spacer()
                                            if !item.pib.isEmpty {
                                                Text("PIB \(item.pib)")
                                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 3)
                                                    .background(colors.primaryContainer)
                                                    .foregroundStyle(colors.onPrimaryContainer)
                                                    .clipShape(Capsule())
                                            }
                                        }

                                        if !item.importir.isEmpty {
                                            Text(item.importir)
                                                .font(.system(size: 12.5, weight: .bold))
                                                .foregroundStyle(colors.textPrimary)
                                                .lineLimit(1)
                                        }

                                        Text(item.summary)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(colors.textSecondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Divider().overlay(colors.divider)

                                // Action Row: Cari PIB di Browse + Lampiran PDF (Exact Android RowSearchButton + Quick Lampiran!)
                                HStack(spacing: 8) {
                                    Button {
                                        app.searchPibInBrowse(query: browseTarget, fromTps: true)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "doc.text.magnifyingglass")
                                                .font(.system(size: 11.5, weight: .bold))
                                            Text(browseLabel)
                                                .font(.system(size: 11.5, weight: .bold))
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 9)
                                        .background(colors.primaryContainer)
                                        .foregroundStyle(colors.onPrimaryContainer)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    if !item.pib.isEmpty || !item.importir.isEmpty {
                                        Button {
                                            lampiranSheetItem = item
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "paperclip")
                                                    .font(.system(size: 11.5, weight: .bold))
                                                Text("Lampiran")
                                                    .font(.system(size: 11.5, weight: .bold))
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 11)
                                            .background(colors.primaryAction)
                                            .foregroundStyle(colors.onPrimaryAction)
                                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(12)
                            .background(item.isMyTask ? colors.myTaskBg : colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(item.isMyTask ? colors.myTaskBorder : colors.cardBorder, lineWidth: item.isMyTask ? 1.4 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            .refreshable { await load() }
        }
        .onChange(of: source) { _ in Task { await load() } }
        .task { await load() }
        .sheet(item: $lampiranSheetItem) { item in
            TpsDocumentLampiranSheet(item: item, colors: colors)
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let myPibs = Set(app.pibs.map { String($0.noPib.drop(while: { $0 == "0" })) })
        let myConts = Set(app.lorongItems.map { $0.noContainer.uppercased() })
        do {
            items = try await SiapApiClient.shared.fetchTps(source: source, myPibs: myPibs, myContainers: myConts)
        } catch {
            app.showToast("Gagal memuat \(source.rawValue): \(error.localizedDescription)")
        }
    }
}

// MARK: - In-Place Lampiran & Detail Sheet for Any TPS Monitoring Document

struct TpsDocumentLampiranSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let item: TpsMonitorItem
    let colors: SiapColors

    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var pendokMatches: [PendokBrowseItem] = []
    @State private var selectedPendokIdx = 0
    @State private var attachments: [PendokDocumentAttachment] = []
    @State private var siapFbDokap: [(String, URL)] = []
    @State private var bapUrl: String?
    @State private var isSwitchingMatch = false

    private var totalAttachmentCount: Int {
        attachments.count + siapFbDokap.count + (bapUrl != nil ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.pib.isEmpty ? item.container : "Dokumen PIB \(item.pib)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(item.source) • \(item.container)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(SiapColors.hintOnNavy)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Tutup")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(colors.headerGradient)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView().tint(colors.primaryAction).scaleEffect(1.1)
                            Text("Mengambil data Pendok MK, SIAP FB & Lampiran PDF untuk PIB \(item.pib)...")
                                .font(.system(size: 13))
                                .foregroundStyle(colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        if let errorMsg {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(errorMsg).font(.system(size: 12.5))
                            }
                            .foregroundStyle(colors.danger)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.danger.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }

                        // Multi-match selector if SIAP 3.0 returned more than 1 Pendok row
                        if pendokMatches.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(pendokMatches.prefix(6).enumerated()), id: \.offset) { idx, m in
                                        let active = idx == selectedPendokIdx
                                        Button {
                                            selectedPendokIdx = idx
                                            Task { await loadAttachmentsForMatch(m) }
                                        } label: {
                                            Text("PIB \(m.noPib) (\(m.tglPib.isEmpty ? m.actionId : m.tglPib))")
                                                .font(.system(size: 11.5, weight: .bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(active ? colors.primaryAction : colors.surface)
                                                .foregroundStyle(active ? colors.onPrimaryAction : colors.textSecondary)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if selectedPendokIdx < pendokMatches.count {
                            let info = pendokMatches[selectedPendokIdx]
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text("Info Pendok MK (SIAP 3.0)")
                                        .font(.system(size: 13.5, weight: .bold))
                                        .foregroundStyle(colors.textPrimary)
                                    Spacer()
                                    SiapStatusChip(text: info.status, colors: colors)
                                }
                                SiapMetaRow(label: "No. / Tgl PIB", value: "\(info.noPib) / \(info.tglPib)", colors: colors)
                                SiapMetaRow(label: "Importir", value: info.namaImportir, colors: colors)
                                if !info.pfpd.isEmpty {
                                    SiapMetaRow(label: "PFPD", value: info.pfpd, colors: colors)
                                }
                                if !info.jalur.isEmpty {
                                    SiapMetaRow(label: "Jalur", value: info.jalur, colors: colors)
                                }
                                if !info.actionId.isEmpty {
                                    SiapMetaRow(label: "Kode Layanan", value: info.actionId, colors: colors)
                                }
                            }
                            .padding(13)
                            .background(colors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }

                        // Lampiran Dokumen List (SIAP 3.0 + SIAP FB Dokap + BAP)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Lampiran Dokumen (\(totalAttachmentCount))")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(colors.textPrimary)
                                Spacer()
                                if isSwitchingMatch {
                                    ProgressView().tint(colors.primaryAction).scaleEffect(0.8)
                                }
                            }

                            if totalAttachmentCount == 0 {
                                VStack(spacing: 8) {
                                    Text("Belum ada file lampiran PDF ditemukan untuk PIB \(item.pib).")
                                        .font(.system(size: 13))
                                        .foregroundStyle(colors.textHint)
                                        .multilineTextAlignment(.center)
                                    Text("Pastikan akun SIAP 3.0 di tab Akun sudah aktif atau coba cari manual di tab Browse.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                ForEach(attachments) { att in
                                    Button {
                                        if let u = URL(string: att.fileUrl) {
                                            dismiss()
                                            app.activeDokap = DokapTarget(title: "\(att.namaDokumen) • PIB \(item.pib)", url: u)
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "doc.richtext.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(colors.primaryAction)
                                                .frame(width: 34, height: 34)
                                                .background(colors.primaryContainer)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(att.namaDokumen)
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(colors.textPrimary)
                                                    .lineLimit(2)
                                                Text(att.tglUpload.isEmpty ? att.jenisDokumen : "\(att.jenisDokumen) • \(att.tglUpload)")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(colors.textHint)
                                            }
                                            Spacer()
                                            Text("Buka PDF")
                                                .font(.system(size: 11.5, weight: .bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(colors.primaryAction)
                                                .foregroundStyle(colors.onPrimaryAction)
                                                .clipShape(Capsule())
                                        }
                                        .padding(11)
                                        .background(colors.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }

                                ForEach(siapFbDokap, id: \.1.absoluteString) { label, url in
                                    Button {
                                        dismiss()
                                        app.activeDokap = DokapTarget(title: "\(label) • PIB \(item.pib)", url: url)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "doc.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(colors.secondary)
                                                .frame(width: 34, height: 34)
                                                .background(colors.surfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(label)
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(colors.textPrimary)
                                                Text("Lampiran SIAP FB")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(colors.textHint)
                                            }
                                            Spacer()
                                            Text("Buka PDF")
                                                .font(.system(size: 11.5, weight: .bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(colors.secondary)
                                                .foregroundStyle(colors.onSecondary)
                                                .clipShape(Capsule())
                                        }
                                        .padding(11)
                                        .background(colors.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }

                                if let bap = bapUrl, let u = URL(string: bap) {
                                    Button {
                                        dismiss()
                                        app.activeDokap = DokapTarget(title: "BAP • PIB \(item.pib)", url: u)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(colors.success)
                                                .frame(width: 34, height: 34)
                                                .background(colors.success.opacity(0.16))
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Berita Acara Pemeriksaan (BAP)")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(colors.textPrimary)
                                                Text("Cetak BAP SIAP 3.0")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(colors.textHint)
                                            }
                                            Spacer()
                                            Text("Buka PDF")
                                                .font(.system(size: 11.5, weight: .bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(colors.success)
                                                .foregroundStyle(colors.isDark ? Color(hex: 0x052E16) : .white)
                                                .clipShape(Capsule())
                                        }
                                        .padding(11)
                                        .background(colors.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        SiapOutlinedButton("Buka Lengkap di Tab Browse", icon: "doc.text.magnifyingglass", color: colors.secondary, bg: colors.surface) {
                            dismiss()
                            app.searchPibInBrowse(query: item.pib.isEmpty ? item.importir : item.pib, fromTps: true)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
            }
            .background(colors.backdrop)
        }
        .task {
            await loadLampiran()
        }
    }

    private func loadAttachmentsForMatch(_ match: PendokBrowseItem) async {
        guard let sess = app.session, !match.actionId.isEmpty else { return }
        isSwitchingMatch = true
        defer { isSwitchingMatch = false }
        if let list = try? await SiapApiClient.shared.fetchPendokAttachments(
            username: sess.username,
            password: sess.password,
            fallbackEmail: sess.usernameEmail,
            kodePelayanan: match.actionId
        ) {
            attachments = list
        }
    }

    private func loadLampiran() async {
        guard let sess = app.session else { return }
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }

        // 1. Query SIAP 3.0 Pendok MK with flexible PIB variants + Importir fallback
        do {
            let found = try await SiapApiClient.shared.searchPendokFlexible(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                noPib: item.pib,
                importirHint: item.importir
            )
            pendokMatches = found
            selectedPendokIdx = 0
            if let first = found.first, !first.actionId.isEmpty {
                attachments = try await SiapApiClient.shared.fetchPendokAttachments(
                    username: sess.username,
                    password: sess.password,
                    fallbackEmail: sess.usernameEmail,
                    kodePelayanan: first.actionId
                )
            }
        } catch {
            errorMsg = error.localizedDescription
        }

        // 2. Also merge SIAP FB Dokap (browse_data -> get_dokumen) so documents missing from Pendok MK still appear!
        let digits = item.pib.filter(\.isNumber)
        if !digits.isEmpty {
            if let fbDocs = try? await SiapApiClient.shared.browsePibData(nip: sess.nip, noPib: digits),
               let firstFb = fbDocs.first, !firstFb.kodeTiket.isEmpty,
               let dokMap = try? await SiapApiClient.shared.fetchDokumen(kodeTiket: firstFb.kodeTiket) {
                let existingUrls = Set(attachments.map(\.fileUrl))
                var extra: [(String, URL)] = []
                for (k, v) in dokMap.sorted(by: { $0.key < $1.key }) {
                    let absStr = SiapApiClient.shared.absolutizeSiap3(v)
                    if !existingUrls.contains(absStr), let u = URL(string: absStr) {
                        extra.append((k, u))
                    }
                }
                siapFbDokap = extra
            }
            // 3. Also check BAP cetak_bap URL
            bapUrl = try? await SiapApiClient.shared.fetchBapUrlForPib(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                noPib: item.pib
            )
        }
    }
}

// MARK: - Authentic Android Aju Barcon & Kendala/Temuan Sheet

struct AjuBarconFormSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let target: BarconFormTarget
    let colors: SiapColors

    var body: some View {
        let barconDone = app.isBarconSubmitted(for: target.pib)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("PIB \(target.pib.noPib) • \(target.pib.importir)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(SiapColors.hintOnNavy)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    UIApplication.shared.open(target.formUrl)
                } label: {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text("Tutup")
                        .font(.system(size: 12.5, weight: .bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(colors.headerGradient)

            // 1-Tap Quick Copy Helper Chips for Fast Google Form Entry
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    QuickCopyChip(label: "PIB: \(target.pib.noPib)", value: target.pib.noPib, colors: colors, app: app)
                    QuickCopyChip(label: "Tgl: \(SiapCrypto.formatDisplayDate(target.pib.tglPib))", value: SiapCrypto.formatDisplayDate(target.pib.tglPib), colors: colors, app: app)
                    QuickCopyChip(label: "TPS: \(target.pib.kodeTps)", value: target.pib.kodeTps, colors: colors, app: app)
                    QuickCopyChip(label: "Importir", value: target.pib.importir, colors: colors, app: app)
                    if let sess = app.session {
                        QuickCopyChip(label: "NIP", value: sess.nip, colors: colors, app: app)
                        QuickCopyChip(label: "Nama", value: sess.displayName, colors: colors, app: app)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(colors.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(colors.divider).frame(height: 0.75)
            }

            SiapWebView(url: target.formUrl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !target.isKendalaTemuan {
                HStack(spacing: 10) {
                    SiapFilledButton(
                        barconDone ? "✓ Sudah Diajukan (Tap untuk Batal)" : "Tandai Aju Barcon Selesai",
                        icon: barconDone ? "checkmark.seal.fill" : "checkmark.circle",
                        bg: barconDone ? colors.success : colors.primaryAction,
                        fg: barconDone ? (colors.isDark ? Color(hex: 0x052E16) : .white) : colors.onPrimaryAction
                    ) {
                        app.toggleBarconSubmitted(for: target.pib)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(colors.surface)
                .overlay(alignment: .top) {
                    Rectangle().fill(colors.divider).frame(height: 0.75)
                }
            }
        }
    }
}

struct QuickCopyChip: View {
    let label: String
    let value: String
    let colors: SiapColors
    let app: AppState

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            app.showToast("Disalin: \(value)")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(colors.primaryContainer)
            .foregroundStyle(colors.onPrimaryContainer)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 5: Profil & Pengaturan (Matches Android UserScreenKt)

struct UserTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @StateObject private var ttdStore = SignatureStrokeStore()
    @State private var isUploadingTtd = false
    @State private var isTestingDiag = false
    @State private var diagResults: [(String, Bool, String)] = []
    @State private var showLogoutConfirm = false
    @State private var siap3User = UserDefaults.standard.string(forKey: "siapneo_siap3_user") ?? ""
    @State private var siap3Pass = UserDefaults.standard.string(forKey: "siapneo_siap3_pass") ?? ""
    @State private var isTestingSiap3 = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Hero Profile Card (SiapCardBrush)
                HStack(spacing: 14) {
                    SiapUserAvatarBadge(session: app.session, size: 62)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.session?.displayName ?? "-")
                            .font(.system(size: 16.5, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("NIP \(app.session?.nip ?? "-")")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(SiapColors.brandAmber)
                        if let jab = app.session?.jabatan, !jab.isEmpty {
                            Text(jab)
                                .font(.system(size: 12))
                                .foregroundStyle(SiapColors.hintOnNavy)
                        }
                        if let email = app.session?.usernameEmail, !email.isEmpty {
                            Text(email)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(colors.cardGradient)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 10)

                // Theme & UI Density Card (Matches Android ThemeOptionChip + UiDensityOptionChip)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tampilan & Tema")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mode Tema").font(.system(size: 12)).foregroundStyle(colors.textHint)
                        HStack(spacing: 8) {
                            ForEach(SiapThemeMode.allCases) { mode in
                                let active = app.themeMode == mode
                                Button {
                                    app.themeMode = mode
                                } label: {
                                    Text(mode.label)
                                        .font(.system(size: 12.5, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(active ? colors.primaryAction : colors.surfaceElevated)
                                        .foregroundStyle(active ? colors.onPrimaryAction : colors.textPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kepadatan Kartu").font(.system(size: 12)).foregroundStyle(colors.textHint)
                        HStack(spacing: 8) {
                            ForEach(SiapUiDensity.allCases) { d in
                                let active = app.uiDensity == d
                                Button {
                                    app.uiDensity = d
                                } label: {
                                    Text(d.label)
                                        .font(.system(size: 12.5, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(active ? colors.primaryAction : colors.surfaceElevated)
                                        .foregroundStyle(active ? colors.onPrimaryAction : colors.textPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(14)
                .background(colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 12)

                // TTD Pemeriksa (PPF) Card
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tanda Tangan Pemeriksa (TTD PPF)")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)

                    if let nip = app.session?.nip, !nip.isEmpty,
                       let url = URL(string: "\(SiapCrypto.ttdPpfAssetsBase)/\(SiapCrypto.sanitizeToken(nip)).png") {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit()
                                    .frame(maxHeight: 80)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }

                    SignaturePadView(store: ttdStore)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))

                    HStack(spacing: 10) {
                        SiapOutlinedButton("Hapus", icon: "eraser.fill", color: colors.danger) {
                            ttdStore.clear()
                        }
                        .frame(width: 110)

                        SiapFilledButton(
                            isUploadingTtd ? "Mengunggah..." : "Simpan TTD PPF",
                            icon: "signature",
                            bg: colors.primaryAction,
                            fg: colors.onPrimaryAction,
                            isLoading: isUploadingTtd
                        ) {
                            Task { await uploadTtdPpf() }
                        }
                        .disabled(isUploadingTtd)
                    }
                }
                .padding(14)
                .background(colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 12)

                // Kredensial SIAP 3.0 (Lampiran Dokumen & BAP)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Kredensial SIAP 3.0 (Lampiran & BAP)")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Text("Kosongkan jika sama dengan akun login SIAP NEO. Isi manual hanya jika akun web SIAP 3.0 berbeda.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(colors.textHint)

                    TextField("Username / NIP SIAP 3.0 (opsional)", text: $siap3User)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13.5))
                        .foregroundStyle(colors.textPrimary)
                        .padding(11)
                        .background(colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    SecureField("Password SIAP 3.0 (opsional)", text: $siap3Pass)
                        .font(.system(size: 13.5))
                        .foregroundStyle(colors.textPrimary)
                        .padding(11)
                        .background(colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 8) {
                        SiapOutlinedButton("Simpan", icon: "checkmark", color: colors.secondary) {
                            UserDefaults.standard.set(siap3User.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "siapneo_siap3_user")
                            UserDefaults.standard.set(siap3Pass, forKey: "siapneo_siap3_pass")
                            SiapApiClient.shared.invalidateSiap3Session()
                            app.showToast("Kredensial SIAP 3.0 disimpan")
                        }
                        SiapFilledButton(
                            isTestingSiap3 ? "Menguji..." : "Tes Login SIAP 3.0",
                            icon: "key.fill",
                            bg: colors.primaryAction,
                            fg: colors.onPrimaryAction,
                            isLoading: isTestingSiap3
                        ) {
                            UserDefaults.standard.set(siap3User.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "siapneo_siap3_user")
                            UserDefaults.standard.set(siap3Pass, forKey: "siapneo_siap3_pass")
                            Task {
                                isTestingSiap3 = true
                                defer { isTestingSiap3 = false }
                                do {
                                    try await SiapApiClient.shared.ensureSiap3Login(
                                        username: app.session?.username ?? "",
                                        password: app.session?.password ?? "",
                                        fallbackEmail: app.session?.usernameEmail ?? "",
                                        force: true
                                    )
                                    app.showToast("Login SIAP 3.0 Berhasil! Lampiran siap dibuka.")
                                } catch {
                                    app.showToast("SIAP 3.0 gagal: \(error.localizedDescription)")
                                }
                            }
                        }
                        .disabled(isTestingSiap3)
                    }
                }
                .padding(14)
                .background(colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 12)

                // Pembaruan Otomatis (TrollStore 1-Tap Updater — Mirror Android AppUpdater)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Pembaruan Otomatis")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Text("v\(app.currentAppVersion) (\(app.currentAppBuild))")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(colors.secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: app.isTrollStoreUrlSchemeReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(app.isTrollStoreUrlSchemeReady ? colors.success : colors.warningBoxText)
                        Text(app.isTrollStoreUrlSchemeReady
                             ? "TrollStore 1-Tap Siap (URL Scheme Aktif)"
                             : "Aktifkan URL Scheme di TrollStore → Settings untuk 1-Tap Update")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(app.isTrollStoreUrlSchemeReady ? colors.success : colors.warningBoxText)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(app.isTrollStoreUrlSchemeReady ? colors.success.opacity(0.14) : colors.warningBoxBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Toggle(isOn: $app.autoCheckUpdates) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cek Update Otomatis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(colors.textPrimary)
                            Text(app.lastUpdateCheckText.isEmpty
                                 ? "Otomatis cek server update setiap buka aplikasi"
                                 : "Server update aktif • \(app.lastUpdateCheckText)")
                                .font(.system(size: 11))
                                .foregroundStyle(colors.textHint)
                        }
                    }
                    .tint(colors.secondary)

                    HStack(spacing: 8) {
                        SiapOutlinedButton(
                            app.isCheckingUpdate ? "Memeriksa..." : "Cek Sekarang",
                            icon: "arrow.triangle.2.circlepath",
                            color: colors.secondary
                        ) {
                            Task { await app.checkForAppUpdate(silent: false, force: true) }
                        }
                        .disabled(app.isCheckingUpdate)

                        SiapFilledButton(
                            app.availableUpdate != nil ? "Update v\(app.availableUpdate!.remoteVersion)" : "Install Latest",
                            icon: "arrow.down.circle.fill",
                            bg: colors.primaryAction,
                            fg: colors.onPrimaryAction
                        ) {
                            if app.availableUpdate != nil {
                                app.showUpdatePromptSheet = true
                            } else {
                                let info = AppUpdateInfo(
                                    remoteVersion: app.currentAppVersion,
                                    remoteBuild: app.currentAppBuild,
                                    ipaDownloadUrl: "https://github.com/rianpermana7io/SiapNEO/releases/download/latest/SIAPNeo-iOS.ipa",
                                    ipaSizeBytes: 0,
                                    publishedAt: "",
                                    notes: "",
                                    mandatory: false
                                )
                                app.triggerTrollStoreUpdate(info)
                            }
                        }
                    }
                }
                .padding(14)
                .background(colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 12)

                // Diagnostik Server Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Diagnostik Koneksi")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Button {
                            Task { await runDiagnostics() }
                        } label: {
                            Text(isTestingDiag ? "Menguji..." : "Uji Server")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(colors.primaryContainer)
                                .foregroundStyle(colors.onPrimaryContainer)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isTestingDiag)
                    }

                    if !diagResults.isEmpty {
                        ForEach(diagResults, id: \.0) { name, ok, detail in
                            HStack {
                                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(ok ? colors.success : colors.danger)
                                Text(name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.textPrimary)
                                Spacer()
                                Text(detail)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                    }
                }
                .padding(14)
                .background(colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 12)

                // Logout Button
                SiapOutlinedButton(
                    "Keluar Akun SIAP NEO",
                    icon: "rectangle.portrait.and.arrow.right",
                    color: colors.danger,
                    bg: colors.danger.opacity(0.1)
                ) {
                    showLogoutConfirm = true
                }
                .padding(.horizontal, 12)

                Text("SIAP NEO iOS Native v1.19.8 • KPU BC Tipe A Tanjung Priok")
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textHint)
                    .padding(.bottom, 14)
            }
        }
        .alert("Keluar Akun?", isPresented: $showLogoutConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Keluar", role: .destructive) { app.logout() }
        } message: {
            Text("Anda yakin ingin keluar dari akun SIAP NEO?")
        }
    }

    private func uploadTtdPpf() async {
        guard let nip = app.session?.nip, !nip.isEmpty else { return }
        guard !ttdStore.strokes.isEmpty else {
            app.showToast("Silakan tanda tangan terlebih dahulu")
            return
        }
        isUploadingTtd = true
        defer { isUploadingTtd = false }
        let fileName = "\(SiapCrypto.sanitizeToken(nip)).png"
        guard let pngData = ttdStore.renderImage().pngData() else { return }
        do {
            _ = try await SiapFtpClient.shared.upload(remoteDir: "ttd_ppf", remoteFilename: fileName, data: pngData)
            try await SiapApiClient.shared.insertTtdPpf(nip: nip)
            app.showToast("TTD Pemeriksa berhasil disimpan!")
        } catch {
            app.showToast("Gagal simpan TTD PPF: \(error.localizedDescription)")
        }
    }

    private func runDiagnostics() async {
        isTestingDiag = true
        defer { isTestingDiag = false }
        let targets: [(String, String)] = [
            ("SIAP FB API", "https://bcpriok.net/siap/siapfb/"),
            ("SIAP 3.0", "https://bcpriok.net/siap3.0/auth/login"),
            ("TPS Graha", "http://103.130.242.88/tpft/MON_SIAP_PERIKSA/"),
            ("TPS NPCT1", "https://bos.multiterminal.co.id/tpk_ipc/cgis/application.php/display/list_antrian")
        ]
        var res: [(String, Bool, String)] = []
        for (name, url) in targets {
            let (ok, detail) = await SiapApiClient.shared.pingEndpoint(url)
            res.append((name, ok, detail))
        }
        diagResults = res
    }
}

// MARK: - Android-Style Auto-Update Prompt Sheet

struct UpdatePromptSheet: View {
    @EnvironmentObject var app: AppState
    let info: AppUpdateInfo
    let colors: SiapColors

    private var cleanChangelogLines: [String] {
        let raw = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return ["Perbaikan performa, stabilitas, dan pembaruan fitur SIAP NEO iOS."]
        }
        return raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("VERSION=") }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Hero Card
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(SiapColors.brandAmber.opacity(0.18))
                                .frame(width: 68, height: 68)
                            Image("SiapLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                        }

                        Text(info.mandatory ? "Pembaruan Wajib Tersedia" : "Pembaruan SIAP NEO Tersedia")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 8) {
                            Text("v\(app.currentAppVersion)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.14))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())

                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SiapColors.brandAmber)

                            Text("v\(info.remoteVersion) (Build \(info.remoteBuild))")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(SiapColors.brandAmber)
                                .foregroundStyle(Color(hex: 0x0B131D))
                                .clipShape(Capsule())
                        }

                        if !info.formattedSize.isEmpty {
                            Text("Ukuran paket IPA: \(info.formattedSize)")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(SiapColors.hintOnNavy)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                    .background(SiapColors.light.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // TrollStore Status Pill
                    HStack(spacing: 8) {
                        Image(systemName: app.isTrollStoreUrlSchemeReady ? "bolt.shield.fill" : "info.circle.fill")
                            .foregroundStyle(app.isTrollStoreUrlSchemeReady ? colors.success : colors.warningBoxText)
                        Text(app.isTrollStoreUrlSchemeReady
                             ? "TrollStore URL Scheme aktif — ketuk tombol di bawah untuk unduh & pasang otomatis 1-tap."
                             : "Tips: Nyalakan TrollStore → Settings → URL Scheme Enabled agar update bisa langsung 1-tap tanpa Safari.")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(app.isTrollStoreUrlSchemeReady ? colors.success : colors.warningBoxText)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.isTrollStoreUrlSchemeReady ? colors.success.opacity(0.14) : colors.warningBoxBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Apa yang Baru / Changelog
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apa yang Baru")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(cleanChangelogLines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(colors.secondary)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    Text(line.hasPrefix("- ") || line.hasPrefix("• ") ? String(line.dropFirst(2)) : line)
                                        .font(.system(size: 13))
                                        .foregroundStyle(colors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Action Buttons
                    VStack(spacing: 10) {
                        Button {
                            app.triggerTrollStoreUpdate(info)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Perbarui Otomatis via TrollStore")
                            }
                            .font(.system(size: 14.5, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SiapColors.brandAmber)
                            .foregroundStyle(Color(hex: 0x0B131D))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            SiapOutlinedButton("Unduh via Safari", icon: "safari", color: colors.secondary) {
                                app.openDirectIpaDownload(info)
                            }
                            if !info.mandatory {
                                SiapOutlinedButton("Nanti Saja", icon: "clock", color: colors.textHint) {
                                    app.dismissUpdatePrompt(snoozeBuild: true)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(colors.backdrop.ignoresSafeArea())
            .navigationTitle("Pembaruan SIAP NEO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !info.mandatory {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Tutup") {
                            app.dismissUpdatePrompt(snoozeBuild: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Authentic Android Redist Sheet (Daftar Redist + Ajukan Redist)

struct RedistSheetView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let colors: SiapColors

    @State private var showForm = false
    @State private var isLoading = false
    @State private var errorMsg: String?

    // Form state
    @State private var schema = RedistHoldFormSchema(
        clusters: RedistHoldFormSchema.defaultClusters,
        alasanOptions: RedistHoldFormSchema.defaultRedistAlasan
    )
    @State private var kodeTiket = ""
    @State private var selectedCluster = "GSRA"
    @State private var selectedAlasan = "Off"
    @State private var keterangan = ""
    @State private var pickedImage: UIImage?
    @State private var showCameraPicker = false
    @State private var showGalleryPicker = false
    @State private var isSubmitting = false
    @State private var formError: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Mode Switcher Pill (Riwayat Redist | Ajukan Redist)
                HStack(spacing: 8) {
                    Button {
                        showForm = false
                    } label: {
                        Text("Riwayat Redist (\(app.redistHistory.count))")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(!showForm ? SiapColors.brandAmber : colors.surfaceElevated)
                            .foregroundStyle(!showForm ? Color(hex: 0x0B131D) : colors.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showForm = true
                        Task { await loadSchema() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                            Text("Ajukan Redist")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(showForm ? SiapColors.brandAmber : colors.surfaceElevated)
                        .foregroundStyle(showForm ? Color(hex: 0x0B131D) : colors.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(colors.surface)

                if showForm {
                    redistFormContent
                } else {
                    redistHistoryContent
                }
            }
            .background(colors.backdrop.ignoresSafeArea())
            .navigationTitle("Redistribusi (Redist)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
                if !showForm {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await loadHistory() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCameraPicker) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ImagePicker(sourceType: .camera) { img in pickedImage = img }
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showGalleryPicker) {
                ImagePicker(sourceType: .photoLibrary) { img in pickedImage = img }
            }
            .task {
                if app.redistHistory.isEmpty {
                    await loadHistory()
                }
                await loadSchema()
            }
        }
    }

    private var redistHistoryContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if isLoading {
                    ProgressView("Memuat riwayat Redist...")
                        .padding(.top, 40)
                } else if let err = errorMsg {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(colors.warning)
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                        SiapFilledButton("Coba Lagi", icon: "arrow.clockwise", bg: colors.primaryAction, fg: colors.onPrimaryAction) {
                            Task { await loadHistory() }
                        }
                    }
                    .padding(24)
                } else if app.redistHistory.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(colors.textHint)
                        Text("Belum ada riwayat permohonan Redist")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.textSecondary)
                        SiapFilledButton("Ajukan Redist Baru", icon: "plus.circle.fill", bg: SiapColors.brandAmber, fg: Color(hex: 0x0B131D)) {
                            showForm = true
                        }
                        .frame(maxWidth: 220)
                    }
                    .padding(.top, 50)
                } else {
                    ForEach(app.redistHistory) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("PIB \(item.noPib.isEmpty ? "-" : item.noPib)")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(colors.textPrimary)
                                Spacer()
                                redistStatusPill(item.status)
                            }
                            if !item.importir.isEmpty && item.importir != "-" {
                                Text(item.importir)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.textSecondary)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 8) {
                                if !item.kodeTiket.isEmpty {
                                    Text("Tiket: \(item.kodeTiket)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(colors.textHint)
                                }
                                if !item.tps.isEmpty && item.tps != "-" {
                                    Text("• TPS \(item.tps)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(colors.secondary)
                                }
                                if !item.cluster.isEmpty {
                                    Text("• \(item.cluster)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(SiapColors.brandAmber)
                                }
                            }
                            if !item.alasan.isEmpty {
                                Text("Alasan: \(item.alasan)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(colors.textPrimary)
                            }
                            if !item.tanggalPengajuan.isEmpty {
                                Text("Diajukan: \(item.tanggalPengajuan)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(colors.textHint)
                            }
                        }
                        .padding(13)
                        .background(colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(14)
        }
    }

    private var redistFormContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !app.pibs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pilih Cepat dari Daftar PIB Beranda")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(colors.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(app.pibs) { doc in
                                    let selected = kodeTiket == doc.kodeTiket
                                    Button {
                                        kodeTiket = doc.kodeTiket
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("PIB \(doc.noPib)")
                                                .font(.system(size: 12, weight: .bold))
                                            Text(doc.kodeTiket)
                                                .font(.system(size: 10, design: .monospaced))
                                                .opacity(0.8)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(selected ? SiapColors.brandAmber : colors.surfaceElevated)
                                        .foregroundStyle(selected ? Color(hex: 0x0B131D) : colors.textPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Kode Tiket *")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    TextField("Masukkan Kode Tiket PIB", text: $kodeTiket)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(11)
                        .background(colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cluster *")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Picker("Cluster", selection: $selectedCluster) {
                        ForEach(schema.clusters) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Alasan Redist *")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Picker("Alasan", selection: $selectedAlasan) {
                        ForEach(schema.alasanOptions) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Keterangan")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    TextEditor(text: $keterangan)
                        .frame(minHeight: 80)
                        .padding(6)
                        .background(colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lampiran Foto Permohonan * (Wajib, maks 10 MB)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)

                    if let img = pickedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        SiapOutlinedButton("Kamera", icon: "camera.fill", color: colors.secondary) {
                            Task { @MainActor in
                                if await CameraPermissionHelper.ensureCameraAccess() {
                                    showCameraPicker = true
                                } else {
                                    app.showToast("Izin kamera belum aktif — buka Pengaturan > SIAP NEO > Kamera")
                                }
                            }
                        }
                        SiapOutlinedButton("Galeri", icon: "photo.on.rectangle", color: SiapColors.brandAmber) {
                            showGalleryPicker = true
                        }
                    }
                }

                if let ferr = formError {
                    Text(ferr)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.danger)
                }

                Button {
                    Task { await submitForm() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(Color(hex: 0x0B131D)) }
                        Text(isSubmitting ? "Mengirim..." : "Kirim Permohonan Redist")
                    }
                    .font(.system(size: 14.5, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SiapColors.brandAmber)
                    .foregroundStyle(Color(hex: 0x0B131D))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
            .padding(14)
        }
    }

    private func redistStatusPill(_ status: String) -> some View {
        let low = status.lowercased()
        let tint: Color = (low.contains("setuju") || low.contains("approve") || low.contains("selesai"))
            ? colors.success
            : ((low.contains("tolak") || low.contains("reject")) ? colors.danger : SiapColors.brandAmber)
        return Text(status.isEmpty ? "PROSES" : status.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func loadHistory() async {
        guard let sess = app.session else { return }
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        do {
            app.redistHistory = try await SiapApiClient.shared.fetchRedistHistory(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail
            )
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func loadSchema() async {
        guard let sess = app.session else { return }
        let loaded = await SiapApiClient.shared.loadRedistFormSchema(
            username: sess.username,
            password: sess.password,
            fallbackEmail: sess.usernameEmail
        )
        schema = loaded
        if !loaded.clusters.contains(where: { $0.value == selectedCluster }), let first = loaded.clusters.first {
            selectedCluster = first.value
        }
        if !loaded.alasanOptions.contains(where: { $0.value == selectedAlasan }), let first = loaded.alasanOptions.first {
            selectedAlasan = first.value
        }
        if kodeTiket.isEmpty, let firstPib = app.pibs.first {
            kodeTiket = firstPib.kodeTiket
        }
    }

    private func submitForm() async {
        guard let sess = app.session else { return }
        let tiket = kodeTiket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tiket.isEmpty else {
            formError = "Kode Tiket wajib diisi."
            return
        }
        guard let img = pickedImage, let jpgData = img.jpegData(compressionQuality: 0.82) else {
            formError = "Lampiran foto permohonan Redist wajib dipilih."
            return
        }
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }
        do {
            let msg = try await SiapApiClient.shared.submitRedist(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                kodeTiket: tiket,
                cluster: selectedCluster,
                alasan: selectedAlasan,
                keterangan: keterangan,
                imageData: jpgData,
                filename: "redist_\(SiapCrypto.sanitizeToken(tiket)).jpg"
            )
            app.showToast(msg)
            pickedImage = nil
            keterangan = ""
            showForm = false
            await loadHistory()
        } catch {
            formError = error.localizedDescription
        }
    }
}

// MARK: - Authentic Android Hold Sheet (Daftar Hold + Ajukan Hold)

struct HoldSheetView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let colors: SiapColors

    @State private var showForm = false
    @State private var isLoading = false
    @State private var errorMsg: String?

    // Form state
    @State private var schema = RedistHoldFormSchema(
        clusters: RedistHoldFormSchema.defaultClusters,
        alasanOptions: RedistHoldFormSchema.defaultHoldAlasan
    )
    @State private var selectedCluster = "GSRA"
    @State private var selectedAlasan = "Off"
    @State private var tanggalDate = Date()
    @State private var waktuMulaiDate: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()
    @State private var waktuSelesaiDate: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 17
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()
    @State private var keterangan = ""
    @State private var isSubmitting = false
    @State private var formError: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Mode Switcher Pill (Riwayat Hold | Ajukan Hold)
                HStack(spacing: 8) {
                    Button {
                        showForm = false
                    } label: {
                        Text("Riwayat Hold (\(app.holdHistory.count))")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(!showForm ? SiapColors.brandSky : colors.surfaceElevated)
                            .foregroundStyle(!showForm ? Color(hex: 0x0B131D) : colors.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showForm = true
                        Task { await loadSchema() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                            Text("Ajukan Hold")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(showForm ? SiapColors.brandSky : colors.surfaceElevated)
                        .foregroundStyle(showForm ? Color(hex: 0x0B131D) : colors.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(colors.surface)

                if showForm {
                    holdFormContent
                } else {
                    holdHistoryContent
                }
            }
            .background(colors.backdrop.ignoresSafeArea())
            .navigationTitle("Permohonan Hold / Izin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
                if !showForm {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await loadHistory() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .task {
                if app.holdHistory.isEmpty {
                    await loadHistory()
                }
                await loadSchema()
            }
        }
    }

    private var holdHistoryContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if isLoading {
                    ProgressView("Memuat riwayat Hold...")
                        .padding(.top, 40)
                } else if let err = errorMsg {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(colors.warning)
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                        SiapFilledButton("Coba Lagi", icon: "arrow.clockwise", bg: colors.primaryAction, fg: colors.onPrimaryAction) {
                            Task { await loadHistory() }
                        }
                    }
                    .padding(24)
                } else if app.holdHistory.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "pause.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(colors.textHint)
                        Text("Belum ada riwayat permohonan Hold")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.textSecondary)
                        SiapFilledButton("Ajukan Hold Baru", icon: "plus.circle.fill", bg: SiapColors.brandSky, fg: Color(hex: 0x0B131D)) {
                            showForm = true
                        }
                        .frame(maxWidth: 220)
                    }
                    .padding(.top, 50)
                } else {
                    ForEach(app.holdHistory) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(item.alasan.isEmpty ? "Permohonan Hold" : item.alasan)
                                    .font(.system(size: 14.5, weight: .bold))
                                    .foregroundStyle(colors.textPrimary)
                                    .lineLimit(2)
                                Spacer()
                                holdStatusPill(item.status)
                            }
                            HStack(spacing: 8) {
                                if !item.cluster.isEmpty {
                                    Text("Cluster \(item.cluster)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundStyle(SiapColors.brandSky)
                                }
                                if !item.tanggalPengajuan.isEmpty {
                                    Text("• \(item.tanggalPengajuan)")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(colors.textHint)
                                }
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(colors.secondary)
                                Text("\(item.waktuMulai) — \(item.waktuSelesai)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                        .padding(13)
                        .background(colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(14)
        }
    }

    private var holdFormContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cluster *")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Picker("Cluster", selection: $selectedCluster) {
                        ForEach(schema.clusters) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Alasan Hold *")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Picker("Alasan", selection: $selectedAlasan) {
                        ForEach(schema.alasanOptions) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("Tanggal Hold", selection: $tanggalDate, displayedComponents: .date)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)

                    HStack(spacing: 12) {
                        DatePicker("Mulai", selection: $waktuMulaiDate, displayedComponents: .hourAndMinute)
                            .font(.system(size: 13, weight: .semibold))
                        DatePicker("Selesai", selection: $waktuSelesaiDate, displayedComponents: .hourAndMinute)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(12)
                .background(colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !app.pibs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sisipkan PIB Tanggungan ke Keterangan (Opsional)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(colors.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(app.pibs) { doc in
                                    Button {
                                        let snippet = "PIB \(doc.noPib) (\(doc.kodeTps))"
                                        if keterangan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            keterangan = snippet
                                        } else if !keterangan.contains(doc.noPib) {
                                            keterangan += ", \(snippet)"
                                        }
                                    } label: {
                                        Text("+ PIB \(doc.noPib)")
                                            .font(.system(size: 11.5, weight: .bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(colors.primaryContainer)
                                            .foregroundStyle(colors.onPrimaryContainer)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Keterangan *")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    TextEditor(text: $keterangan)
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let ferr = formError {
                    Text(ferr)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.danger)
                }

                Button {
                    Task { await submitForm() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(Color(hex: 0x0B131D)) }
                        Text(isSubmitting ? "Mengirim..." : "Kirim Permohonan Hold")
                    }
                    .font(.system(size: 14.5, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SiapColors.brandSky)
                    .foregroundStyle(Color(hex: 0x0B131D))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
            .padding(14)
        }
    }

    private func holdStatusPill(_ status: String) -> some View {
        let low = status.lowercased()
        let tint: Color = (low.contains("setuju") || low.contains("approve") || low.contains("selesai"))
            ? colors.success
            : ((low.contains("tolak") || low.contains("reject")) ? colors.danger : SiapColors.brandSky)
        return Text(status.isEmpty ? "PROSES" : status.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func loadHistory() async {
        guard let sess = app.session else { return }
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        do {
            app.holdHistory = try await SiapApiClient.shared.fetchHoldHistory(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail
            )
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func loadSchema() async {
        guard let sess = app.session else { return }
        let loaded = await SiapApiClient.shared.loadHoldFormSchema(
            username: sess.username,
            password: sess.password,
            fallbackEmail: sess.usernameEmail
        )
        schema = loaded
        if !loaded.clusters.contains(where: { $0.value == selectedCluster }), let first = loaded.clusters.first {
            selectedCluster = first.value
        }
        if !loaded.alasanOptions.contains(where: { $0.value == selectedAlasan }), let first = loaded.alasanOptions.first {
            selectedAlasan = first.value
        }
    }

    private func submitForm() async {
        guard let sess = app.session else { return }
        let ket = keterangan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ket.isEmpty else {
            formError = "Keterangan permohonan Hold wajib diisi."
            return
        }
        let tglStr = SiapCrypto.wibFormatter("yyyy-MM-dd").string(from: tanggalDate)
        let mulaiStr = SiapCrypto.wibFormatter("HH:mm").string(from: waktuMulaiDate)
        let selesaiStr = SiapCrypto.wibFormatter("HH:mm").string(from: waktuSelesaiDate)
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }
        do {
            let msg = try await SiapApiClient.shared.submitHold(
                username: sess.username,
                password: sess.password,
                fallbackEmail: sess.usernameEmail,
                cluster: selectedCluster,
                alasan: selectedAlasan,
                keterangan: ket,
                tanggal: tglStr,
                wkMulai: mulaiStr,
                wkSelesai: selesaiStr
            )
            app.showToast(msg)
            keterangan = ""
            showForm = false
            await loadHistory()
        } catch {
            formError = error.localizedDescription
        }
    }
}
