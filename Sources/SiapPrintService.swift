import SwiftUI
import UIKit
import PDFKit

// MARK: - Authentic Android SIAP Print Models (Port of PrinterConnectionConfig, PrintOptions, PrinterApiClient)

enum PrinterConnectionMode: String, CaseIterable, Identifiable, Codable {
    case auto = "AUTO"
    case funnel = "FUNNEL"
    case tailscale = "TAILSCALE"
    case lan = "LAN"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Otomatis (coba semua jalur)"
        case .funnel: return "Tailscale Funnel (HTTPS)"
        case .tailscale: return "Tailscale IP"
        case .lan: return "IP Lokal / Wi-Fi Kantor"
        }
    }
}

struct PrinterConnectionConfig: Codable, Equatable {
    static let defaultPort = 1234
    static let defaultFunnelUrl = "https://fqrbc.taile81f15.ts.net"
    static let storageKey = "siapneo_ios_printer_config_v1"

    var mode: PrinterConnectionMode = .auto
    var funnelUrl: String = defaultFunnelUrl
    var tailscaleIp: String = ""
    var lanIp: String = ""
    var port: Int = defaultPort
    var printerName: String = ""

    var isConfigured: Bool {
        !funnelUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !tailscaleIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !lanIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load() -> PrinterConnectionConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var cfg = try? JSONDecoder().decode(PrinterConnectionConfig.self, from: data) else {
            return PrinterConnectionConfig()
        }
        // Match Android SessionManager.getPrinterConfig(): fallback to DEFAULT_PRINTER_SERVER_URL if blank
        if !cfg.isConfigured {
            cfg.funnelUrl = defaultFunnelUrl
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func candidateBaseUrls() -> [(mode: PrinterConnectionMode, url: String)] {
        var out: [(PrinterConnectionMode, String)] = []
        var seen = Set<String>()

        func append(_ m: PrinterConnectionMode, _ u: String) {
            let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            out.append((m, trimmed))
        }

        let normFunnel = SiapPrinterApiClient.normalizeFunnel(funnelUrl)
        let normTs = SiapPrinterApiClient.normalizeHost(tailscaleIp, port: port)
        let normLan = SiapPrinterApiClient.normalizeHost(lanIp, port: port)

        switch mode {
        case .funnel:
            append(.funnel, normFunnel)
        case .tailscale:
            append(.tailscale, normTs)
        case .lan:
            append(.lan, normLan)
        case .auto:
            // Exact Android PrinterConnectionConfig.candidateBaseUrls() priority: FUNNEL -> TAILSCALE -> LAN
            append(.funnel, normFunnel)
            append(.tailscale, normTs)
            append(.lan, normLan)
        }
        return out
    }
}

enum SiapPrintPaper: String, CaseIterable, Identifiable, Codable {
    case `default` = "DEFAULT"
    case a4 = "A4"
    case f4 = "F4"

    var id: String { rawValue }
    var code: String {
        switch self {
        case .default: return ""
        case .a4: return "A4"
        case .f4: return "F4"
        }
    }
    var label: String {
        switch self {
        case .default: return "Bawaan"
        case .a4: return "A4"
        case .f4: return "F4"
        }
    }
}

struct SiapPrintOptions: Codable, Equatable {
    static let storageKey = "siapneo_ios_print_options_v1"
    static let marginChoices: [Int?] = [nil, 5, 10, 15, 20, 25]

    var paper: SiapPrintPaper = .default
    var marginMm: Int? = nil
    var pages: String = ""

    static func loadLast() -> SiapPrintOptions {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var opts = try? JSONDecoder().decode(SiapPrintOptions.self, from: data) else {
            return SiapPrintOptions()
        }
        opts.pages = ""
        return opts
    }

    func saveLast() {
        var toSave = self
        toSave.pages = ""
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

struct SiapPrinterEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isDefault: Bool
    let status: String?
    let statusDescription: String?
    let isOffline: Bool?
}

struct SiapPrinterServerInfo {
    let port: Int?
    let tailscaleIp: String
    let tailscaleFunnelDomain: String
    let localIp: String
    let selectedPrinter: String
    let version: String
    let features: Set<String>
}

struct SiapPrintJobResult {
    let success: Bool
    let jobId: String
    let status: String
    let printer: String
    let pages: Int
    let message: String
}

// MARK: - Wire-Compatible SIAP Print PC Client (Port of Android PrinterApiClient.kt)

final class SiapPrinterApiClient {
    static let shared = SiapPrinterApiClient()

    private let probeSession: URLSession
    private let printSession: URLSession

    private init() {
        let pCfg = URLSessionConfiguration.default
        pCfg.timeoutIntervalForRequest = 6
        pCfg.timeoutIntervalForResource = 8
        self.probeSession = URLSession(configuration: pCfg)

        let prCfg = URLSessionConfiguration.default
        prCfg.timeoutIntervalForRequest = 45
        prCfg.timeoutIntervalForResource = 60
        self.printSession = URLSession(configuration: prCfg)
    }

    static func normalizeFunnel(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if s.isEmpty { return "" }
        if s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://") {
            return s
        }
        return "https://\(s)"
    }

    static func normalizeHost(_ raw: String, port: Int) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if s.isEmpty { return "" }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://\(s)"
        }
        let afterScheme = s.components(separatedBy: "://").dropFirst().joined(separator: "://")
        let hostPart = afterScheme.components(separatedBy: "/").first ?? afterScheme
        if hostPart.range(of: ":\\d{2,5}$", options: .regularExpression) != nil {
            return s
        }
        let usePort = port > 0 ? port : PrinterConnectionConfig.defaultPort
        return "\(s):\(usePort)"
    }

    static func sanitizePrinterName(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("{"), let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = obj["name"] as? String {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    func ping(baseUrl: String) async -> Bool {
        // Exact Android PrinterApiClient.ping(): GET {baseUrl}/ping first, fallback to {baseUrl}/
        for suffix in ["/ping", "/"] {
            guard let url = URL(string: "\(baseUrl)\(suffix)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            do {
                let (data, resp) = try await probeSession.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                if body.localizedCaseInsensitiveContains("SIAP Print") || (suffix == "/ping" && http.statusCode == 200) {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    func resolveReachableBaseUrl(config: PrinterConnectionConfig) async throws -> String {
        let candidates = config.candidateBaseUrls()
        guard !candidates.isEmpty else {
            throw SiapApiError.message("Alamat SIAP Print belum diisi. Buka Pengaturan Printer terlebih dahulu.")
        }
        for (_, baseUrl) in candidates {
            if await ping(baseUrl: baseUrl) {
                return baseUrl
            }
        }
        throw SiapApiError.message("Server SIAP Print di PC tidak dapat dijangkau. Pastikan SIAP Print PC sedang ONLINE.")
    }

    func getServerInfo(baseUrl: String) async throws -> SiapPrinterServerInfo {
        guard let url = URL(string: "\(baseUrl)/info") else {
            throw SiapApiError.message("URL server printer tidak valid")
        }
        let (data, resp) = try await probeSession.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SiapApiError.message("Gagal membaca info server SIAP Print")
        }
        func str(_ k: String) -> String {
            guard let v = obj[k], !(v is NSNull) else { return "" }
            let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.lowercased() == "null" ? "" : s
        }
        let portNum = (obj["port"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        let featArr = (obj["features"] as? [String]) ?? []
        return SiapPrinterServerInfo(
            port: portNum,
            tailscaleIp: str("tailscaleIp"),
            tailscaleFunnelDomain: str("tailscaleFunnelDomain"),
            localIp: str("localIp"),
            selectedPrinter: str("selectedPrinter"),
            version: str("version"),
            features: Set(featArr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        )
    }

    func getAvailablePrinters(baseUrl: String) async throws -> [SiapPrinterEntry] {
        guard let url = URL(string: "\(baseUrl)/printers") else {
            throw SiapApiError.message("URL /printers tidak valid")
        }
        let (data, resp) = try await probeSession.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SiapApiError.message("Gagal mengambil daftar printer dari SIAP Print PC")
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let rawList: [Any]
        if let arr = parsed as? [Any] {
            rawList = arr
        } else if let dict = parsed as? [String: Any], let arr = dict["printers"] as? [Any] {
            rawList = arr
        } else {
            return []
        }

        var entries: [SiapPrinterEntry] = []
        for item in rawList {
            if let dict = item as? [String: Any],
               let nameRaw = dict["name"] as? String {
                let name = nameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { continue }
                let isDef = (dict["is_default"] as? Bool) ?? (dict["isDefault"] as? Bool) ?? false
                let st = (dict["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let stDesc = (dict["status_description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let offline = dict["is_offline"] as? Bool
                entries.append(SiapPrinterEntry(
                    name: name,
                    isDefault: isDef,
                    status: (st?.isEmpty == false && st?.lowercased() != "null") ? st : nil,
                    statusDescription: (stDesc?.isEmpty == false && stDesc?.lowercased() != "null") ? stDesc : nil,
                    isOffline: offline
                ))
            } else if let s = item as? String {
                let name = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    entries.append(SiapPrinterEntry(name: name, isDefault: false, status: nil, statusDescription: nil, isOffline: nil))
                }
            }
        }
        return entries
    }

    func printDocumentPdf(
        baseUrl: String,
        printerName: String,
        pdfData: Data,
        documentTitle: String,
        options: SiapPrintOptions,
        forcePrint: Bool
    ) async throws -> SiapPrintJobResult {
        guard !pdfData.isEmpty else {
            throw SiapApiError.message("Berkas PDF kosong (0 byte)")
        }
        guard let url = URL(string: "\(baseUrl)/print-pdf") else {
            throw SiapApiError.message("URL /print-pdf tidak valid")
        }

        var safeName = documentTitle.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        if !safeName.lowercased().hasSuffix(".pdf") {
            safeName += ".pdf"
        }

        var payload: [String: Any] = [
            "printerName": Self.sanitizePrinterName(printerName),
            "filename": safeName,
            "pdfBase64": pdfData.base64EncodedString()
        ]
        if forcePrint {
            payload["forcePrint"] = true
        }
        if options.paper != .default {
            payload["paperSize"] = options.paper.code
        }
        if let m = options.marginMm {
            payload["marginsMm"] = ["top": m, "right": m, "bottom": m, "left": m]
        }
        let cleanPages = options.pages.replacingOccurrences(of: " ", with: "")
        if !cleanPages.isEmpty {
            payload["pages"] = cleanPages
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await printSession.data(for: req)
        let httpCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        let okFlag = (json?["success"] as? Bool) ?? (200...299).contains(httpCode)
        let msg = (json?["message"] as? String)
            ?? (json?["error"] as? String)
            ?? (rawBody.isEmpty ? "HTTP \(httpCode)" : String(rawBody.prefix(200)))

        if (200...299).contains(httpCode) && okFlag {
            let jobId = (json?["job_id"] as? String) ?? ""
            let status = (json?["status"] as? String) ?? "printed"
            let prName = (json?["printer"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (printerName.isEmpty ? "printer default PC" : printerName)
            let pages = (json?["pages"] as? Int) ?? 0
            return SiapPrintJobResult(success: true, jobId: jobId, status: status, printer: prName, pages: pages, message: msg)
        }
        throw SiapApiError.message(msg)
    }
}

// MARK: - Native iOS AirPrint Helper (UIPrintInteractionController)

enum AirPrintHelper {
    @MainActor
    static func present(fileURL: URL, jobName: String, onDone: @escaping (Bool, String?) -> Void) {
        guard UIPrintInteractionController.isPrintingAvailable else {
            onDone(false, "AirPrint tidak tersedia di perangkat ini.")
            return
        }
        guard UIPrintInteractionController.canPrint(fileURL) else {
            onDone(false, "Format berkas tidak didukung untuk AirPrint.")
            return
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        info.duplex = .longEdge
        controller.printInfo = info
        controller.printingItem = fileURL
        controller.present(animated: true) { _, completed, error in
            if let error {
                onDone(false, error.localizedDescription)
            } else if completed {
                onDone(true, nil)
            } else {
                onDone(false, nil)
            }
        }
    }
}

// MARK: - BAP Print Preview & Options Sheet (SIAP Print PC + AirPrint iOS)

struct BapPrintSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let title: String
    let fileURL: URL
    let isImage: Bool
    let colors: SiapColors

    @State private var printTab = 0 // 0 = SIAP Print PC, 1 = AirPrint iOS
    @State private var config = PrinterConnectionConfig.load()
    @State private var options = SiapPrintOptions.loadLast()
    @State private var forcePrint = false
    @State private var isProbing = false
    @State private var activeBaseUrl: String?
    @State private var serverInfo: SiapPrinterServerInfo?
    @State private var printers: [SiapPrinterEntry] = []
    @State private var selectedPrinter = ""
    @State private var probeError: String?
    @State private var isPrinting = false
    @State private var printStatusMsg: String?
    @State private var printStatusSuccess = false
    @State private var showSettings = false
    @State private var totalPdfPages = 0

    private var navyActionColor: Color {
        colors.isDark ? Color(hex: 0x1E4B8A) : Color(hex: 0x0A2D63)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Document summary card
                    HStack(spacing: 10) {
                        Image(systemName: "printer.filled.and.paper")
                            .font(.system(size: 22))
                            .foregroundStyle(SiapColors.brandAmber)
                            .frame(width: 40, height: 40)
                            .background(colors.primaryContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundStyle(colors.textPrimary)
                                .lineLimit(2)
                            Text(totalPdfPages > 0 ? "Dokumen PDF • \(totalPdfPages) halaman" : (isImage ? "Dokumen Gambar" : "Dokumen PDF"))
                                .font(.system(size: 12))
                                .foregroundStyle(colors.textHint)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Mode Switcher: SIAP Print PC vs AirPrint iOS
                    Picker("Metode Cetak", selection: $printTab) {
                        Text("SIAP Print PC").tag(0)
                        Text("AirPrint iOS").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if printTab == 0 {
                        siapPrintPcSection
                    } else {
                        airPrintSection
                    }

                    if let statusMsg = printStatusMsg {
                        HStack(spacing: 8) {
                            Image(systemName: printStatusSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(printStatusSuccess ? colors.success : colors.danger)
                            Text(statusMsg)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(printStatusSuccess ? colors.success : colors.danger)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((printStatusSuccess ? colors.success : colors.danger).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(14)
            }
            .background(colors.backdrop.ignoresSafeArea())
            .navigationTitle("Cetak BAP / Dokumen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Tutup") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(SiapColors.brandAmber)
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                config = PrinterConnectionConfig.load()
                if !config.printerName.isEmpty { selectedPrinter = config.printerName }
                Task { await probeServer() }
            }) {
                PrinterSettingsSheet(colors: colors)
                    .environmentObject(app)
                    .preferredColorScheme(app.themeMode.preferredColorScheme)
            }
            .task {
                if !isImage, let pdf = PDFDocument(url: fileURL) {
                    totalPdfPages = pdf.pageCount
                }
                selectedPrinter = config.printerName
                if config.isConfigured {
                    await probeServer()
                }
            }
        }
    }

    private var siapPrintPcSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Connection status box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Server SIAP Print PC")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Spacer()
                    if isProbing {
                        ProgressView().scaleEffect(0.75)
                    } else if activeBaseUrl != nil {
                        Text("ONLINE")
                            .font(.system(size: 10.5, weight: .heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(colors.success.opacity(0.18))
                            .foregroundStyle(colors.success)
                            .clipShape(Capsule())
                    } else {
                        Text("OFFLINE")
                            .font(.system(size: 10.5, weight: .heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(colors.danger.opacity(0.16))
                            .foregroundStyle(colors.danger)
                            .clipShape(Capsule())
                    }
                }

                if let url = activeBaseUrl {
                    Text("\(url)\(serverInfo?.version.isEmpty == false ? " • v\(serverInfo!.version)" : "")")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                    if let curPr = printers.first(where: { $0.name == selectedPrinter }) ?? printers.first,
                       let desc = curPr.statusDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle((curPr.isOffline == true) ? colors.danger : colors.success)
                    }
                } else if let err = probeError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(colors.danger)
                } else {
                    Text("Belum terhubung ke SIAP Print PC. Tekan Atur Server untuk memasukkan IP PC / Tailscale / Funnel.")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textHint)
                }

                HStack(spacing: 8) {
                    SiapOutlinedButton("Atur Server", icon: "slider.horizontal.3", color: SiapColors.brandAmber, bg: colors.surfaceElevated) {
                        showSettings = true
                    }
                    SiapOutlinedButton("Cek Ulang", icon: "arrow.clockwise", color: colors.secondary, bg: colors.surfaceElevated) {
                        Task { await probeServer() }
                    }
                }
            }
            .padding(14)
            .background(colors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Print Options Card (Exact Android PrintOptions: Printer, Paper A4/F4, Margin mm, Pages, Force)
            VStack(alignment: .leading, spacing: 12) {
                Text("Pengaturan Cetak")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(colors.textPrimary)

                // Printer Picker
                VStack(alignment: .leading, spacing: 5) {
                    Text("Printer Tujuan").font(.system(size: 12, weight: .semibold)).foregroundStyle(colors.textHint)
                    if !printers.isEmpty {
                        Menu {
                            ForEach(printers) { pr in
                                Button {
                                    selectedPrinter = pr.name
                                } label: {
                                    Text(pr.isDefault ? "\(pr.name) (Default)" : pr.name)
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedPrinter.isEmpty ? "Printer Default PC" : selectedPrinter)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(colors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(colors.textHint)
                            }
                            .padding(11)
                            .background(colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    } else {
                        TextField("Nama printer (kosong = default PC)", text: $selectedPrinter)
                            .font(.system(size: 13.5))
                            .padding(10)
                            .background(colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }

                // Paper Size Chips (Bawaan / A4 / F4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ukuran Kertas").font(.system(size: 12, weight: .semibold)).foregroundStyle(colors.textHint)
                    HStack(spacing: 8) {
                        ForEach(SiapPrintPaper.allCases) { p in
                            let active = options.paper == p
                            Button { options.paper = p } label: {
                                Text(p.label)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(active ? navyActionColor : colors.surfaceElevated)
                                    .foregroundStyle(active ? .white : colors.textSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Margin Chips (Bawaan / 5 / 10 / 15 / 20 / 25 mm)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Margin (mm)").font(.system(size: 12, weight: .semibold)).foregroundStyle(colors.textHint)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(0..<SiapPrintOptions.marginChoices.count, id: \.self) { idx in
                                let m = SiapPrintOptions.marginChoices[idx]
                                let active = options.marginMm == m
                                Button { options.marginMm = m } label: {
                                    Text(m == nil ? "Bawaan" : "\(m!) mm")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .background(active ? navyActionColor : colors.surfaceElevated)
                                        .foregroundStyle(active ? .white : colors.textSecondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Pages input
                VStack(alignment: .leading, spacing: 5) {
                    Text("Halaman (kosong = semua halaman)").font(.system(size: 12, weight: .semibold)).foregroundStyle(colors.textHint)
                    TextField("Contoh: 1-2 atau 1,3", text: $options.pages)
                        .font(.system(size: 13.5))
                        .padding(10)
                        .background(colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                Toggle("Paksa Cetak (abaikan peringatan status printer)", isOn: $forcePrint)
                    .font(.system(size: 12.5, weight: .medium))
                    .tint(SiapColors.brandAmber)

                Button {
                    Task { await sendToSiapPrintPc() }
                } label: {
                    HStack(spacing: 8) {
                        if isPrinting {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Image(systemName: "printer.fill")
                        }
                        Text(isPrinting ? "MENGIRIM KE PRINTER..." : "CETAK VIA SIAP PRINT PC")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(activeBaseUrl != nil ? Color(hex: 0x4BD367) : colors.outline)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isPrinting || activeBaseUrl == nil)
            }
            .padding(14)
            .background(colors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var airPrintSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cetak Langsung via AirPrint iOS")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text("Gunakan dialog cetak bawaan iPhone untuk mencetak BAP langsung ke printer Wi-Fi AirPrint yang terhubung di jaringan yang sama (mendukung pilihan jumlah salinan, rentang halaman, dan bolak-balik).")
                .font(.system(size: 12.5))
                .foregroundStyle(colors.textSecondary)

            Button {
                AirPrintHelper.present(fileURL: fileURL, jobName: title) { ok, err in
                    if ok {
                        printStatusSuccess = true
                        printStatusMsg = "Dokumen dikirim ke AirPrint iOS!"
                        app.showToast("BAP dikirim ke AirPrint")
                    } else if let err {
                        printStatusSuccess = false
                        printStatusMsg = err
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "printer.fill")
                    Text("BUKA DIALOG AIRPRINT iOS")
                        .font(.system(size: 13.5, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(navyActionColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(colors.surface)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func probeServer() async {
        isProbing = true
        probeError = nil
        defer { isProbing = false }
        do {
            let base = try await SiapPrinterApiClient.shared.resolveReachableBaseUrl(config: config)
            activeBaseUrl = base
            if let info = try? await SiapPrinterApiClient.shared.getServerInfo(baseUrl: base) {
                serverInfo = info
                if selectedPrinter.isEmpty && !info.selectedPrinter.isEmpty {
                    selectedPrinter = info.selectedPrinter
                }
            }
            if let list = try? await SiapPrinterApiClient.shared.getAvailablePrinters(baseUrl: base) {
                printers = list
                if selectedPrinter.isEmpty, let def = list.first(where: \.isDefault) ?? list.first {
                    selectedPrinter = def.name
                }
            }
        } catch {
            activeBaseUrl = nil
            probeError = error.localizedDescription
        }
    }

    private func sendToSiapPrintPc() async {
        guard let base = activeBaseUrl else {
            probeError = "Server SIAP Print PC belum terhubung."
            return
        }
        isPrinting = true
        printStatusMsg = nil
        defer { isPrinting = false }
        options.saveLast()

        do {
            let pdfData: Data
            if isImage, let img = UIImage(contentsOfFile: fileURL.path) {
                let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
                let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
                pdfData = renderer.pdfData { ctx in
                    ctx.beginPage()
                    let aspect = min((pageRect.width - 40) / max(img.size.width, 1), (pageRect.height - 40) / max(img.size.height, 1))
                    let w = img.size.width * aspect
                    let h = img.size.height * aspect
                    img.draw(in: CGRect(x: (pageRect.width - w) / 2, y: (pageRect.height - h) / 2, width: w, height: h))
                }
            } else {
                pdfData = try Data(contentsOf: fileURL)
            }

            let res = try await SiapPrinterApiClient.shared.printDocumentPdf(
                baseUrl: base,
                printerName: selectedPrinter,
                pdfData: pdfData,
                documentTitle: title,
                options: options,
                forcePrint: forcePrint
            )
            var updatedCfg = config
            updatedCfg.printerName = selectedPrinter
            updatedCfg.save()
            printStatusSuccess = true
            printStatusMsg = "Berhasil dikirim ke \(res.printer) (\(res.pages > 0 ? "\(res.pages) hal • " : "")\(res.status))"
            app.showToast("BAP berhasil dikirim ke printer \(res.printer)!")
        } catch {
            printStatusSuccess = false
            printStatusMsg = "Gagal cetak: \(error.localizedDescription)"
        }
    }
}

// MARK: - Printer Settings Sheet (Matches Android Akun > PrinterSettingsDialogKt)

struct PrinterSettingsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let colors: SiapColors

    @State private var config = PrinterConnectionConfig.load()
    @State private var portText = "1234"
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSuccess = false
    @State private var discoveredPrinters: [SiapPrinterEntry] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Mode Koneksi SIAP Print PC")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(colors.textPrimary)

                        Picker("Mode", selection: $config.mode) {
                            ForEach(PrinterConnectionMode.allCases) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("IP Lokal / Wi-Fi Kantor (contoh: 172.16.4.253)").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                            TextField("172.16.x.x atau 192.168.x.x", text: $config.lanIp)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13.5, design: .monospaced))
                                .padding(10)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tailscale IP (contoh: 100.90.255.113)").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                            TextField("100.x.x.x", text: $config.tailscaleIp)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13.5, design: .monospaced))
                                .padding(10)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tailscale Funnel URL (Default Android: https://fqrbc.taile81f15.ts.net)").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                            TextField("https://fqrbc.taile81f15.ts.net", text: $config.funnelUrl)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13.5, design: .monospaced))
                                .padding(10)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port SIAP Print (default: 1234)").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                            TextField("1234", text: $portText)
                                .keyboardType(.numberPad)
                                .font(.system(size: 13.5, design: .monospaced))
                                .padding(10)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        if !discoveredPrinters.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Printer Default").font(.system(size: 11.5)).foregroundStyle(colors.textHint)
                                Picker("Printer", selection: $config.printerName) {
                                    Text("Printer Default PC").tag("")
                                    ForEach(discoveredPrinters) { pr in
                                        Text(pr.name).tag(pr.name)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }

                        if let msg = testMessage {
                            Text(msg)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(testSuccess ? colors.success : colors.danger)
                        }

                        HStack(spacing: 8) {
                            SiapOutlinedButton(
                                isTesting ? "Menguji..." : "Tes Koneksi",
                                icon: "wifi",
                                color: colors.secondary,
                                bg: colors.surfaceElevated
                            ) {
                                Task { await testConnection() }
                            }
                            .disabled(isTesting)

                            SiapFilledButton(
                                "Simpan",
                                icon: "checkmark.circle.fill",
                                bg: colors.primaryAction,
                                fg: colors.onPrimaryAction
                            ) {
                                config.port = Int(portText) ?? PrinterConnectionConfig.defaultPort
                                if !config.isConfigured {
                                    config.funnelUrl = PrinterConnectionConfig.defaultFunnelUrl
                                }
                                config.save()
                                app.showToast("Pengaturan SIAP Print disimpan")
                                dismiss()
                            }
                        }

                        SiapOutlinedButton(
                            "Reset ke Server Default Android (FQRBC)",
                            icon: "arrow.counterclockwise",
                            color: SiapColors.brandAmber,
                            bg: colors.surfaceElevated
                        ) {
                            config = PrinterConnectionConfig()
                            portText = "\(PrinterConnectionConfig.defaultPort)"
                            config.save()
                            Task { await testConnection() }
                        }
                    }
                    .padding(14)
                    .background(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(14)
            }
            .background(colors.backdrop.ignoresSafeArea())
            .navigationTitle("Pengaturan Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Tutup") { dismiss() }
                }
            }
            .onAppear {
                portText = "\(config.port)"
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        testMessage = nil
        defer { isTesting = false }
        config.port = Int(portText) ?? PrinterConnectionConfig.defaultPort
        do {
            let base = try await SiapPrinterApiClient.shared.resolveReachableBaseUrl(config: config)
            let info = try? await SiapPrinterApiClient.shared.getServerInfo(baseUrl: base)
            let list = (try? await SiapPrinterApiClient.shared.getAvailablePrinters(baseUrl: base)) ?? []
            discoveredPrinters = list
            if let info {
                if config.tailscaleIp.isEmpty && !info.tailscaleIp.isEmpty { config.tailscaleIp = info.tailscaleIp }
                if config.lanIp.isEmpty && !info.localIp.isEmpty { config.lanIp = info.localIp }
                if config.funnelUrl.isEmpty && !info.tailscaleFunnelDomain.isEmpty { config.funnelUrl = info.tailscaleFunnelDomain }
                if config.printerName.isEmpty && !info.selectedPrinter.isEmpty { config.printerName = info.selectedPrinter }
            }
            config.save()
            testSuccess = true
            testMessage = "Terhubung ke \(base) (\(list.count) printer terdeteksi)"
        } catch {
            testSuccess = false
            testMessage = error.localizedDescription
        }
    }
}
