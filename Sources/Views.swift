import SwiftUI
import UIKit

// MARK: - Upload Navigation Context

struct UploadFotoContext: Equatable {
    let pib: PibDocument
    let nokon: String
    let containers: [ContainerItem]
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var session: UserSession?
    @Published var pibs: [PibDocument] = []
    @Published var lorongItems: [InstruksiLorongItem] = []
    @Published var isLoadingPibs = false
    @Published var isLoadingLorong = false
    @Published var lastPibError: String?
    @Published var lastUpdatedText: String = ""
    @Published var toastMessage: String?

    // Navigation state (Matches Android ScreenHome / HomeSubView)
    @Published var activeTab: SiapBottomTab = .beranda
    @Published var selectedPib: PibDocument?
    @Published var activeUploadContext: UploadFotoContext?
    @Published var activeDokap: DokapTarget?
    @Published var showManualSheet = false

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

        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let saved = try? JSONDecoder().decode(UserSession.self, from: data),
           !saved.nip.isEmpty {
            self.session = saved
        }
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

    func saveSession(_ s: UserSession) {
        self.session = s
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    func logout() {
        self.session = nil
        self.pibs = []
        self.lorongItems = []
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
            pibs = try await SiapApiClient.shared.fetchHomescreen(nip: nip)
            let df = SiapCrypto.wibFormatter("HH:mm")
            lastUpdatedText = "Diperbarui \(df.string(from: Date())) WIB"
        } catch {
            lastPibError = error.localizedDescription
            showToast("Gagal memuat PIB: \(error.localizedDescription)")
        }
    }

    func loadLorong() async {
        guard let nip = session?.nip, !nip.isEmpty else { return }
        isLoadingLorong = true
        defer { isLoadingLorong = false }
        do {
            lorongItems = try await SiapApiClient.shared.fetchDetailKontainerNip(nip: nip)
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

                        Text("Sistem Informasi Pemeriksaan Fisik • v1.19.2")
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
    @State private var containers: [ContainerItem] = []
    @State private var isLoadingContainers = false
    @State private var dokapLinks: [String: String] = [:]
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
                }
                .padding(.bottom, 20)
            }

            // Sticky Bottom Action Bar (Exact port of Android PibDocumentBottomActionBar!)
            VStack(spacing: 8) {
                // Row 1: Dokap Quick Pills (PIB | INV/PL | B/L | BAP)
                HStack(spacing: 6) {
                    DokapPillButton(title: "PIB", icon: "doc.text.fill", available: findDokapUrl(keys: ["pib", "file_pib", "url_pib"]) != nil, colors: colors) {
                        openDokap(title: "Dokumen PIB \(pib.noPib)", keys: ["pib", "file_pib", "url_pib"])
                    }
                    DokapPillButton(title: "INV/PL", icon: "list.bullet.rectangle", available: findDokapUrl(keys: ["pl", "inv", "packing", "invoice"]) != nil, colors: colors) {
                        openDokap(title: "INV / PL • \(pib.noPib)", keys: ["pl", "inv", "packing", "invoice"])
                    }
                    DokapPillButton(title: "B/L", icon: "ferry.fill", available: findDokapUrl(keys: ["bl", "awb", "bill"]) != nil, colors: colors) {
                        openDokap(title: "B/L • \(pib.noPib)", keys: ["bl", "awb", "bill"])
                    }
                    DokapPillButton(title: "BAP", icon: "checkmark.seal.fill", available: findDokapUrl(keys: ["bap", "cetak_bap"]) != nil, colors: colors) {
                        openDokap(title: "BAP • \(pib.noPib)", keys: ["bap", "cetak_bap"])
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

    private func loadDetails() async {
        isLoadingContainers = true
        defer { isLoadingContainers = false }
        async let cTask: [ContainerItem] = (try? await SiapApiClient.shared.fetchContainers(kodeTiket: pib.kodeTiket)) ?? []
        async let dTask: [String: String] = (try? await SiapApiClient.shared.fetchDokumen(kodeTiket: pib.kodeTiket)) ?? [:]
        containers = await cTask
        dokapLinks = await dTask
    }

    private func findDokapUrl(keys: [String]) -> URL? {
        for (k, v) in dokapLinks {
            let kl = k.lowercased()
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "-" || trimmed == "null" { continue }
            if keys.contains(where: { kl.contains($0) }) {
                if trimmed.hasPrefix("http"), let u = URL(string: trimmed) { return u }
                if let u = URL(string: "https://bcpriok.net/\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))") {
                    return u
                }
            }
        }
        return nil
    }

    private func openDokap(title: String, keys: [String]) {
        if let url = findDokapUrl(keys: keys) {
            app.activeDokap = DokapTarget(title: title, url: url)
        } else {
            app.showToast("Link \(title) belum tersedia dari server")
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

// MARK: - Full-Screen Drill-Down: UploadFotoPanel (Matches Android UploadFotoPanel)

struct UploadFotoPanel: View {
    @EnvironmentObject var app: AppState
    let pib: PibDocument
    let initialNokon: String
    let allContainers: [ContainerItem]
    let colors: SiapColors

    @StateObject private var locMgr = LocationManager()
    @State private var selectedNokon = ""
    @State private var selectedStep: StepOption = StepOption.allSteps[0]
    @State private var deskripsi = ""
    @State private var watermarkEnabled = true
    @State private var pickedImage: UIImage?
    @State private var pickerSource: UIImagePickerController.SourceType?
    @State private var isUploading = false
    @State private var isOcrRunning = false
    @State private var onlineImages: [OnlineImageItem] = []
    @State private var isLoadingImages = false
    @State private var fullscreenImage: OnlineImageItem?
    @State private var deleteTarget: OnlineImageItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Container Switcher Pills
                if !allContainers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(allContainers) { c in
                                let active = selectedNokon == c.noContainer
                                Button {
                                    selectedNokon = c.noContainer
                                    Task { await loadImages() }
                                } label: {
                                    Text(c.noContainer)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 11)
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
                    .padding(.top, 10)
                }

                // Step Selector Chips (Matches Android UploadFotoPanel)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tahap Foto Pemeriksaan")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, 14)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(StepOption.allSteps) { step in
                                let active = selectedStep.id == step.id
                                Button { selectedStep = step } label: {
                                    Text("\(step.id). \(step.label)")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(active ? colors.primaryAction : colors.surface)
                                        .foregroundStyle(active ? colors.onPrimaryAction : colors.textPrimary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(active ? Color.clear : colors.cardBorder, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }

                // Capture & Watermark Card
                VStack(alignment: .leading, spacing: 12) {
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

                    TextField("Keterangan / deskripsi foto (opsional)", text: $deskripsi)
                        .font(.system(size: 13.5))
                        .foregroundStyle(colors.textPrimary)
                        .padding(11)
                        .background(colors.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(colors.cardBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 10) {
                        SiapFilledButton(
                            "Kamera",
                            icon: "camera.fill",
                            bg: colors.primaryAction,
                            fg: colors.onPrimaryAction
                        ) {
                            pickerSource = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
                        }

                        SiapOutlinedButton(
                            "Galeri",
                            icon: "photo.on.rectangle.angled",
                            color: colors.secondary,
                            bg: colors.surfaceElevated
                        ) {
                            pickerSource = .photoLibrary
                        }
                    }

                    if let img = pickedImage {
                        VStack(spacing: 10) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            HStack(spacing: 8) {
                                SiapOutlinedButton(
                                    isOcrRunning ? "Memindai..." : "OCR Kontainer",
                                    icon: "viewfinder",
                                    color: colors.secondary,
                                    bg: colors.surfaceElevated
                                ) {
                                    Task { await runOcr(on: img) }
                                }
                                .disabled(isOcrRunning)

                                SiapOutlinedButton("Hapus", icon: "trash", color: colors.danger) {
                                    pickedImage = nil
                                }
                                .frame(width: 105)
                            }

                            SiapFilledButton(
                                isUploading ? "Mengunggah ke FTP & SIAP..." : "Unggah Foto Sekarang",
                                icon: "icloud.and.arrow.up.fill",
                                bg: colors.success,
                                fg: colors.isDark ? Color(hex: 0x052E16) : .white,
                                isLoading: isUploading
                            ) {
                                Task { await uploadPhoto(img) }
                            }
                            .disabled(isUploading)
                        }
                    }
                }
                .padding(14)
                .background(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(colors.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 12)

                // Foto Terunggah Grid
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Foto Terunggah (\(onlineImages.count))")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Button {
                            Task { await loadImages() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(colors.primaryAction)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)

                    if isLoadingImages {
                        ProgressView().tint(colors.primaryAction).frame(maxWidth: .infinity).padding()
                    } else if onlineImages.isEmpty {
                        Text("Belum ada foto terunggah untuk \(selectedNokon).")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textHint)
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(colors.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .padding(.horizontal, 12)
                    } else {
                        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(onlineImages) { item in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        fullscreenImage = item
                                    } label: {
                                        VStack(spacing: 4) {
                                            if let url = item.resolvedURL {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable().scaledToFill()
                                                    } else {
                                                        colors.surfaceElevated
                                                    }
                                                }
                                                .frame(height: 98)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            }
                                            Text(item.ketPraPemeriksaan.isEmpty ? "Foto #\(item.id)" : item.ketPraPemeriksaan)
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(colors.textSecondary)
                                                .lineLimit(1)
                                        }
                                        .padding(6)
                                        .background(colors.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(colors.cardBorder, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        deleteTarget = item
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(colors.danger)
                                            .background(Circle().fill(colors.surface))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            if selectedNokon.isEmpty { selectedNokon = initialNokon }
            locMgr.request()
        }
        .task {
            if selectedNokon.isEmpty { selectedNokon = initialNokon }
            await loadImages()
        }
        .sheet(item: Binding(
            get: { pickerSource.map { SourceTypeWrapper(source: $0) } },
            set: { if $0 == nil { pickerSource = nil } }
        )) { wrapper in
            ImagePicker(sourceType: wrapper.source) { img in
                pickedImage = img
            }
        }
        .sheet(item: $fullscreenImage) { item in
            ZStack(alignment: .topTrailing) {
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
                Button {
                    fullscreenImage = nil
                } label: {
                    Text("Tutup")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(18)
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
            Text("Hapus foto ini dari pemeriksaan?")
        }
    }

    private func loadImages() async {
        isLoadingImages = true
        defer { isLoadingImages = false }
        onlineImages = (try? await SiapApiClient.shared.fetchImages(kodeTiket: pib.kodeTiket, nokon: selectedNokon)) ?? []
    }

    private func runOcr(on image: UIImage) async {
        isOcrRunning = true
        defer { isOcrRunning = false }
        if let found = await ContainerOcrScanner.scanContainerNumber(from: image) {
            selectedNokon = found
            app.showToast("OCR Kontainer terdeteksi: \(found)")
        } else {
            app.showToast("Nomor kontainer tidak terdeteksi di foto")
        }
    }

    private func uploadPhoto(_ raw: UIImage) async {
        isUploading = true
        defer { isUploading = false }
        let monthFolder = SiapCrypto.currentMonthYear()
        let waktu = SiapCrypto.currentExifTimestamp()
        let isLcl = pib.isLclDefault || selectedNokon.uppercased() == "LCL"
        let activeUkuran = allContainers.first(where: { $0.noContainer == selectedNokon })?.ukuranContainer ?? ""
        let fileName = SiapCrypto.buildInspectionFileName(
            kodeTiket: pib.kodeTiket,
            isLcl: isLcl,
            nokon: selectedNokon,
            waktuFoto: waktu,
            stepLabel: selectedStep.label,
            stepCode: selectedStep.code,
            urutanBarang: "\(onlineImages.count + 1)",
            ext: "jpg"
        )
        guard let jpegData = ImageWatermarkProcessor.process(
            image: raw,
            watermark: watermarkEnabled,
            noPib: pib.noPib,
            nokon: selectedNokon,
            stepLabel: selectedStep.label,
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
                nokon: selectedNokon,
                urlImage: "\(monthFolder)/\(fileName)",
                stepLabel: selectedStep.label,
                seriBarang: "",
                ketSeriBarang: deskripsi,
                lokasi: locMgr.coordinateText,
                ukuran: activeUkuran,
                waktuFoto: waktu,
                uraianBarang: deskripsi,
                jumlahJenisKemasan: ""
            )
            pickedImage = nil
            deskripsi = ""
            app.showToast("Foto berhasil diunggah!")
            await loadImages()
        } catch {
            app.showToast("Upload gagal: \(error.localizedDescription)")
        }
    }
}

private struct SourceTypeWrapper: Identifiable {
    let id = UUID()
    let source: UIImagePickerController.SourceType
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

// MARK: - In-App Dokap Viewer (PIB / INV-PL / B/L / BAP)

struct DokapViewerPanel: View {
    let target: DokapTarget
    let colors: SiapColors

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(target.url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(colors.textHint)
                    .lineLimit(1)
                Spacer()
                Button {
                    UIApplication.shared.open(target.url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari.fill")
                        Text("Safari")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(colors.primaryContainer)
                    .foregroundStyle(colors.onPrimaryContainer)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(colors.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(colors.divider).frame(height: 0.75)
            }

            SiapWebView(url: target.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Tab 2: Instruksi Lorong

struct LorongTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors
    @State private var query = ""

    private var filtered: [InstruksiLorongItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(colors.textHint)
                    TextField("Cari Kontainer, PIB, Instruksi...", text: $query)
                        .font(.system(size: 13.5))
                        .foregroundStyle(colors.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
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
                .padding(.top, 10)

                if app.isLoadingLorong && app.lorongItems.isEmpty {
                    ProgressView("Memuat Instruksi Lorong...").tint(colors.primaryAction).padding(.top, 40)
                } else if filtered.isEmpty {
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
                    ForEach(filtered) { item in
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
            .padding(.bottom, 18)
        }
        .refreshable { await app.loadLorong() }
        .task {
            if app.lorongItems.isEmpty && app.session != nil {
                await app.loadLorong()
            }
        }
    }
}

// MARK: - Tab 3: Browse PIB & Pendok MK

struct BrowseTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @State private var mode = 0
    @State private var query = ""
    @State private var isLoading = false
    @State private var pibResults: [PibDocument] = []
    @State private var pendokResults: [PendokItem] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Segmented Pill Switcher
                HStack(spacing: 6) {
                    BrowseSegmentPill(title: "Browse PIB", active: mode == 0, colors: colors) { mode = 0 }
                    BrowseSegmentPill(title: "Pendok MK (SIAP 3.0)", active: mode == 1, colors: colors) { mode = 1 }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                // Search Row
                HStack(spacing: 8) {
                    TextField(mode == 0 ? "Masukkan No. PIB..." : "Cari PIB / Importir Pendok...", text: $query)
                        .font(.system(size: 13.5))
                        .foregroundStyle(colors.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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

                if isLoading {
                    ProgressView("Mencari data...").tint(colors.primaryAction).padding(.top, 30)
                } else if mode == 0 {
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
                } else {
                    if pendokResults.isEmpty {
                        Text("Cari data Pendok MK SIAP 3.0.")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textHint)
                            .padding(.top, 30)
                    } else {
                        ForEach(pendokResults) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(colors.textPrimary)
                                    Spacer()
                                    if !item.status.isEmpty {
                                        SiapStatusChip(text: item.status, colors: colors)
                                    }
                                }
                                Text(item.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(colors.textSecondary)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(colors.cardBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
    }

    private func search() async {
        guard let sess = app.session else { return }
        isLoading = true
        defer { isLoading = false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if mode == 0 {
                pibResults = try await SiapApiClient.shared.browsePibData(nip: sess.nip, noPib: q)
            } else {
                pendokResults = try await SiapApiClient.shared.browsePendok(username: sess.username, password: sess.password, query: q)
            }
        } catch {
            app.showToast("Gagal mencari: \(error.localizedDescription)")
        }
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

// MARK: - Tab 5: Profil & Pengaturan (Matches Android UserScreenKt)

struct UserTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @StateObject private var ttdStore = SignatureStrokeStore()
    @State private var isUploadingTtd = false
    @State private var isTestingDiag = false
    @State private var diagResults: [(String, Bool, String)] = []
    @State private var showLogoutConfirm = false

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

                Text("SIAP NEO iOS Native v1.19.2 • KPU BC Tipe A Tanjung Priok")
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
