import SwiftUI

// MARK: - Authentic SIAP NEO Color Palette (from ColorKt.java)

enum SiapPalette {
    static let navyDark = Color(red: 0.059, green: 0.149, blue: 0.220)        // #0F2638
    static let navy = Color(red: 0.122, green: 0.239, blue: 0.322)            // #1F3D52
    static let teal = Color(red: 0.114, green: 0.290, blue: 0.314)            // #1D4A50
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)           // #F59E0B
    static let sky = Color(red: 0.220, green: 0.741, blue: 0.973)             // #38BDF8
    static let danger = Color(red: 0.608, green: 0.110, blue: 0.110)          // #9B1C1C
    static let success = Color(red: 0.086, green: 0.396, blue: 0.204)         // #166534

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [navyDark, navy, teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func statusColors(for status: String) -> (bg: Color, fg: Color, accent: Color) {
        let s = status.lowercased()
        if s.contains("selesai") || s.contains("done") || s.contains("bap") {
            return (Color(red: 0.05, green: 0.29, blue: 0.43).opacity(0.18), Color(red: 0.05, green: 0.45, blue: 0.68), sky)
        }
        if s.contains("sedang") || s.contains("proses") || s.contains("progress") {
            return (Color(red: 0.08, green: 0.50, blue: 0.24).opacity(0.18), Color(red: 0.08, green: 0.55, blue: 0.28), Color.green)
        }
        if s.contains("siap") || s.contains("tolak") {
            return (Color(red: 0.75, green: 0.14, blue: 0.14).opacity(0.16), Color(red: 0.80, green: 0.18, blue: 0.18), Color.red)
        }
        if s.contains("pending") || s.contains("tunda") || s.contains("hold") {
            return (Color(red: 0.85, green: 0.55, blue: 0.05).opacity(0.18), Color(red: 0.78, green: 0.45, blue: 0.04), amber)
        }
        return (Color.gray.opacity(0.16), Color.secondary, Color.gray)
    }
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
    @Published var toastMessage: String?

    private let sessionKey = "siapneo_ios_session_v2"
    private let rememberedUserKey = "siapneo_ios_remembered_user"

    var rememberedUsername: String {
        get { UserDefaults.standard.string(forKey: rememberedUserKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: rememberedUserKey) }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let saved = try? JSONDecoder().decode(UserSession.self, from: data),
           !saved.nip.isEmpty {
            self.session = saved
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
        self.lorongItems = []
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

// MARK: - Login View (Authentic SIAP NEO Navy-Teal Style)

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var rememberUser = true
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            SiapPalette.headerGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 44)

                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 82, height: 82)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                                )
                            Text("SN")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Text("SIAP NEO")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("KPU Bea dan Cukai Tipe A Tanjung Priok")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.82))
                        Text("iOS Native Edition v1.19.1")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(SiapPalette.amber.opacity(0.22))
                            .foregroundStyle(SiapPalette.amber)
                            .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Masuk Akun Pemeriksa")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username / Email SIAP").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Image(systemName: "person.fill").foregroundStyle(.secondary)
                                TextField("Masukkan username SIAP", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                if showPassword {
                                    TextField("Masukkan password", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("Masukkan password", text: $password)
                                }
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }

                        Toggle("Ingat Username", isOn: $rememberUser)
                            .font(.subheadline)
                            .tint(SiapPalette.navy)

                        if let errorMsg {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(errorMsg).font(.footnote)
                            }
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(10)
                        }

                        Button {
                            Task { await performLogin() }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading { ProgressView().tint(.white) }
                                Text(isLoading ? "Menghubungkan ke SIAP..." : "Masuk")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SiapPalette.headerGradient)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isLoading || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    }
                    .padding(20)
                    .background(Color(.systemBackground))
                    .cornerRadius(22)
                    .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
                    .padding(.horizontal, 18)

                    Spacer(minLength: 30)
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

// MARK: - Tab 1: Beranda (Authentic SIAP NEO Homescreen)

struct HomeTabView: View {
    @EnvironmentObject var app: AppState
    @State private var searchText = ""
    @State private var filter: HomeStatusFilter = .semua
    @State private var selectedPib: PibDocument?
    @State private var showManualSheet = false

    private var siapCount: Int { app.pibs.filter { $0.normalizedStatusCategory == "siap" }.count }
    private var sedangCount: Int { app.pibs.filter { $0.normalizedStatusCategory == "sedang" }.count }
    private var selesaiCount: Int { app.pibs.filter { $0.normalizedStatusCategory == "selesai" }.count }

    private var filteredPibs: [PibDocument] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return app.pibs.filter { doc in
            let matchFilter: Bool
            switch filter {
            case .semua:   matchFilter = true
            case .siap:    matchFilter = doc.normalizedStatusCategory == "siap"
            case .sedang:  matchFilter = doc.normalizedStatusCategory == "sedang"
            case .selesai: matchFilter = doc.normalizedStatusCategory == "selesai"
            }
            if !matchFilter { return false }
            guard !q.isEmpty else { return true }
            return doc.noPib.lowercased().contains(q)
                || doc.kodeTiket.lowercased().contains(q)
                || doc.importir.lowercased().contains(q)
                || doc.kodeTps.lowercased().contains(q)
                || doc.namaPj.lowercased().contains(q)
                || doc.cluster.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    heroHeaderCard

                    // Search + Manual Button
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Cari PIB, Importir, TPS, PJ...", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)

                        Button {
                            showManualSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Manual")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(SiapPalette.navy)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 14)

                    // Status Filter Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HomeStatusFilter.allCases) { item in
                                let active = filter == item
                                Button {
                                    filter = item
                                } label: {
                                    Text(filterLabel(item))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 7)
                                        .background(active ? SiapPalette.navy : Color(.secondarySystemBackground))
                                        .foregroundStyle(active ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    // PIB List
                    if app.isLoadingPibs && app.pibs.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Mengambil data PIB dari bcpriok.net...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                    } else if let err = app.lastPibError, app.pibs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            Button("Coba Muat Ulang") {
                                Task { await app.loadPibs() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(24)
                    } else if filteredPibs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(app.pibs.isEmpty ? "Belum ada tugas PIB aktif untuk NIP \(app.session?.nip ?? "-")." : "Tidak ada PIB yang cocok dengan filter.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(36)
                    } else {
                        ForEach(filteredPibs) { doc in
                            PibRichCard(doc: doc, onTap: {
                                selectedPib = doc
                            }, onWaPj: {
                                app.openWhatsApp(
                                    phone: doc.hpPj,
                                    message: "Halo \(doc.namaPj), terkait pemeriksaan fisik PIB \(doc.noPib) (\(doc.importir)) di TPS \(doc.kodeTps). Mohon kesiapannya."
                                )
                            })
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await app.loadPibs()
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedPib) { pib in
                PibDetailSheet(pib: pib)
            }
            .sheet(isPresented: $showManualSheet) {
                ManualDocSheet()
            }
            .task {
                if app.pibs.isEmpty {
                    await app.loadPibs()
                }
            }
        }
    }

    private func filterLabel(_ f: HomeStatusFilter) -> String {
        switch f {
        case .semua:   return "Semua (\(app.pibs.count))"
        case .siap:    return "Siap (\(siapCount))"
        case .sedang:  return "Sedang (\(sedangCount))"
        case .selesai: return "Selesai (\(selesaiCount))"
        }
    }

    private var heroHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // Avatar
                Group {
                    if let urlStr = app.session?.photoUrl, urlStr.hasPrefix("http"), let url = URL(string: urlStr) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            initialsAvatar
                        }
                    } else {
                        initialsAvatar
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.session?.displayName ?? "Pemeriksa")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("NIP \(app.session?.nip ?? "-")")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.white.opacity(0.85))
                    if let jab = app.session?.jabatan, !jab.isEmpty {
                        Text(jab)
                            .font(.caption2)
                            .foregroundStyle(SiapPalette.amber)
                            .lineLimit(1)
                    }
                }
                Spacer()

                Button {
                    Task { await app.loadPibs() }
                } label: {
                    if app.isLoadingPibs {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.16))
                .clipShape(Circle())
            }

            // 4 KPI Mini Cards
            HStack(spacing: 8) {
                kpiBox(title: "Total", value: "\(app.pibs.count)", tint: .white)
                kpiBox(title: "Siap", value: "\(siapCount)", tint: Color(red: 1.0, green: 0.65, blue: 0.65))
                kpiBox(title: "Sedang", value: "\(sedangCount)", tint: Color(red: 0.43, green: 0.91, blue: 0.72))
                kpiBox(title: "Selesai", value: "\(selesaiCount)", tint: SiapPalette.sky)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(SiapPalette.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var initialsAvatar: some View {
        ZStack {
            Color.white.opacity(0.2)
            Text(String((app.session?.displayName ?? "S").prefix(2)).uppercased())
                .font(.headline.bold())
                .foregroundStyle(.white)
        }
    }

    private func kpiBox(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.11))
        .cornerRadius(12)
    }
}

// MARK: - Rich SIAP NEO PIB Card

struct PibRichCard: View {
    let doc: PibDocument
    let onTap: () -> Void
    let onWaPj: () -> Void

    var body: some View {
        let stColor = SiapPalette.statusColors(for: doc.status)

        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(stColor.accent)
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 8) {
                    // Row 1: PIB + Date + Status
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("PIB \(doc.noPib)")
                                    .font(.headline.bold())
                                    .foregroundStyle(.primary)
                                if !doc.jenisKontainer.isEmpty && doc.jenisKontainer != "-" {
                                    Text(doc.jenisKontainer)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(SiapPalette.navy.opacity(0.14))
                                        .foregroundStyle(SiapPalette.navy)
                                        .cornerRadius(5)
                                }
                            }
                            Text("Tgl \(SiapCrypto.formatDisplayDate(doc.tglPib)) • Tiket \(doc.kodeTiket)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(doc.status)
                            .font(.caption2.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(stColor.bg)
                            .foregroundStyle(stColor.fg)
                            .clipShape(Capsule())
                    }

                    // Row 2: Importir
                    if !doc.importir.isEmpty && doc.importir != "-" {
                        Text(doc.importir)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }

                    // Row 3: TPS / Cluster / Persentase / Item
                    HStack(spacing: 8) {
                        if doc.kodeTps != "-" {
                            miniChip(icon: "building.2.fill", text: doc.kodeTps)
                        }
                        if doc.persentasePeriksa != "-" {
                            miniChip(icon: "percent", text: doc.persentasePeriksa)
                        }
                        if doc.jumlahItem != "-" {
                            miniChip(icon: "shippingbox.fill", text: "\(doc.jumlahItem) item")
                        }
                        if doc.cluster != "-" {
                            miniChip(icon: "square.grid.2x2.fill", text: doc.cluster)
                        }
                    }

                    // Row 4: Atensi highlight
                    if doc.hasAtensi {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Atensi: \(doc.atensi)")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(8)
                    }

                    // Row 5: PJ + BAP + Quick WA
                    HStack {
                        if doc.namaPj != "-" {
                            Label(doc.namaPj, systemImage: "person.badge.shield.checkmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if doc.namaPfpd != "-" {
                            Label("PFPD: \(doc.namaPfpd)", systemImage: "person.text.rectangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if !doc.nomorBap.isEmpty && doc.nomorBap != "-" {
                            Text("BAP: \(doc.nomorBap)")
                                .font(.caption2.bold())
                                .foregroundStyle(SiapPalette.sky)
                        }
                        if !doc.hpPj.isEmpty && doc.hpPj != "not found" && doc.hpPj != "-" {
                            Button(action: onWaPj) {
                                Label("WA PJ", systemImage: "message.fill")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.16))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func miniChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color(.secondarySystemBackground))
        .foregroundStyle(.secondary)
        .cornerRadius(6)
    }
}

// MARK: - Tab 2: Instruksi Lorong (detailkontainer_nip)

struct LorongTabView: View {
    @EnvironmentObject var app: AppState
    @State private var searchText = ""

    private var filtered: [InstruksiLorongItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return app.lorongItems }
        return app.lorongItems.filter {
            $0.noContainer.lowercased().contains(q)
                || $0.noPib.lowercased().contains(q)
                || $0.instruksiLorong.lowercased().contains(q)
                || $0.status.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if app.isLoadingLorong && app.lorongItems.isEmpty {
                    ProgressView("Memuat daftar kontainer & instruksi lorong...")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filtered.isEmpty {
                    Text("Belum ada data instruksi lorong aktif.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { item in
                        let st = SiapPalette.statusColors(for: item.status)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.noContainer)
                                    .font(.headline.monospaced())
                                if item.ukuranContainer != "-" {
                                    Text("\(item.ukuranContainer)ft")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.14))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(5)
                                }
                                Spacer()
                                Text(item.status)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(st.bg)
                                    .foregroundStyle(st.fg)
                                    .clipShape(Capsule())
                            }
                            Text("PIB \(item.noPib) • Tgl \(SiapCrypto.formatDisplayDate(item.tglPib)) • Tiket \(item.kodeTiket)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Label("Lorong: \(item.instruksiLorong)", systemImage: "arrow.triangle.branch")
                                Label("Pel: \(item.pelaksanaanLorong)", systemImage: "checkmark.circle")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            if item.teknikPeriksa != "-" {
                                Text("Teknik: \(item.teknikPeriksa)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Cari Kontainer / PIB / Lorong")
            .refreshable { await app.loadLorong() }
            .navigationTitle("Instruksi Lorong")
            .task {
                if app.lorongItems.isEmpty { await app.loadLorong() }
            }
        }
    }
}

// MARK: - Tab 3: Browse (Browse PIB SIAP FB + Pendok SIAP 3.0)

struct BrowseTabView: View {
    @EnvironmentObject var app: AppState
    @State private var mode = 0 // 0 = Browse PIB, 1 = Pendok SIAP 3.0
    @State private var query = ""
    @State private var pibResults: [PibDocument] = []
    @State private var pendokResults: [PendokItem] = []
    @State private var selectedPib: PibDocument?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Browse PIB").tag(0)
                    Text("Pendok SIAP 3.0").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                List {
                    if isLoading {
                        ProgressView("Mencari data...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if mode == 0 {
                        if pibResults.isEmpty {
                            Text("Masukkan nomor PIB lalu tekan Cari untuk browse data di SIAP FB.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pibResults) { doc in
                                Button {
                                    selectedPib = doc
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("PIB \(doc.noPib)").font(.headline).foregroundStyle(.primary)
                                            Spacer()
                                            Text(doc.status).font(.caption.bold()).foregroundStyle(.blue)
                                        }
                                        Text(doc.importir).font(.subheadline).foregroundStyle(.primary)
                                        Text("Tiket: \(doc.kodeTiket) • TPS: \(doc.kodeTps) • Tgl: \(SiapCrypto.formatDisplayDate(doc.tglPib))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                    } else {
                        if pendokResults.isEmpty {
                            Text("Cari nomor PIB atau importir di SIAP 3.0.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pendokResults) { it in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(it.title).font(.headline)
                                        Spacer()
                                        if !it.status.isEmpty {
                                            Text(it.status).font(.caption2.bold()).foregroundStyle(.blue)
                                        }
                                    }
                                    Text(it.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .searchable(text: $query, prompt: mode == 0 ? "Nomor PIB (mis. 123456)" : "Cari PIB / Importir di SIAP 3.0")
                .onSubmit(of: .search) { Task { await runSearch() } }
            }
            .navigationTitle("Browse & Pendok")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cari") { Task { await runSearch() } }
                }
            }
            .sheet(item: $selectedPib) { doc in
                PibDetailSheet(pib: doc)
            }
        }
    }

    private func runSearch() async {
        guard let sess = app.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if mode == 0 {
                pibResults = try await SiapApiClient.shared.browsePibData(nip: sess.nip, noPib: query)
            } else {
                pendokResults = try await SiapApiClient.shared.browsePendok(username: sess.username, password: sess.password, query: query)
            }
        } catch {
            app.showToast(error.localizedDescription)
        }
    }
}

// MARK: - PIB Detail & Camera Upload Sheet

struct PibDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let pib: PibDocument

    @StateObject private var locationMgr = LocationManager()
    @StateObject private var pjSig = SignatureStrokeStore()

    @State private var dokInfo: [String: String] = [:]
    @State private var containers: [ContainerItem] = []
    @State private var selectedNokon = ""
    @State private var isLcl = false
    @State private var selectedStep = StepOption.allSteps[5]
    @State private var seriBarang = ""
    @State private var ketSeri = ""
    @State private var uraianBarang = ""
    @State private var jmlKemasan = ""
    @State private var useWatermark = true

    @State private var pickedImage: UIImage?
    @State private var pickerSource: UIImagePickerController.SourceType?
    @State private var isUploading = false
    @State private var onlineImages: [OnlineImageItem] = []

    @State private var namaPj = ""
    @State private var isBusyAction = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Informasi PIB & Pemeriksaan") {
                    LabeledContent("No PIB", value: pib.noPib)
                    LabeledContent("Tanggal PIB", value: SiapCrypto.formatDisplayDate(pib.tglPib))
                    LabeledContent("Kode Tiket", value: pib.kodeTiket)
                    LabeledContent("Importir", value: dokInfo["importir"]?.isEmpty == false ? dokInfo["importir"]! : pib.importir)
                    LabeledContent("TPS / Cluster", value: "\(pib.kodeTps) • \(pib.cluster)")
                    LabeledContent("Status / Persentase", value: "\(pib.status) (\(pib.persentasePeriksa))")
                    if pib.hasAtensi {
                        Text("Atensi: \(pib.atensi)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if pib.namaPj != "-" {
                        LabeledContent("PJ", value: "\(pib.namaPj) \(pib.hpPj.isEmpty || pib.hpPj == "not found" ? "" : "(\(pib.hpPj))")")
                    }
                    if pib.namaPfpd != "-" {
                        LabeledContent("PFPD", value: pib.namaPfpd)
                    }
                }

                Section("Kontainer & Mode") {
                    Toggle("Mode LCL (Tanpa Kontainer)", isOn: $isLcl)
                    if !isLcl && !containers.isEmpty {
                        Picker("Pilih Kontainer", selection: $selectedNokon) {
                            ForEach(containers) { c in
                                Text("\(c.noContainer) \(c.ukuranContainer.isEmpty ? "" : "(\(c.ukuranContainer)ft)")")
                                    .tag(c.noContainer)
                            }
                        }
                        if let activeC = containers.first(where: { $0.noContainer == selectedNokon }) {
                            Text("Lorong: \(activeC.instruksiLorong) | Pelaksanaan: \(activeC.pelaksanaanLorong) | Teknik: \(activeC.teknikPeriksa)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Ambil & Upload Foto Pemeriksaan") {
                    Picker("Tahap Foto", selection: $selectedStep) {
                        ForEach(StepOption.allSteps) { step in
                            Text("\(step.code). \(step.label)").tag(step)
                        }
                    }
                    TextField("Seri Barang (opsional)", text: $seriBarang)
                    TextField("Keterangan Seri", text: $ketSeri)
                    TextField("Uraian Barang (opsional)", text: $uraianBarang)
                    TextField("Jumlah/Jenis Kemasan (mis. 10 CTN)", text: $jmlKemasan)
                    Toggle("Watermark GPS + WIB", isOn: $useWatermark)
                    Text("GPS: \(locationMgr.coordinateText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            pickerSource = .camera
                        } label: {
                            Label("Kamera", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SiapPalette.navy)

                        Button {
                            pickerSource = .photoLibrary
                        } label: {
                            Label("Galeri", systemImage: "photo.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let img = pickedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .cornerRadius(10)

                        HStack(spacing: 10) {
                            Button {
                                Task { await scanOcr(img) }
                            } label: {
                                Label("OCR Kontainer", systemImage: "text.viewfinder")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await uploadPhoto(img) }
                            } label: {
                                HStack {
                                    if isUploading { ProgressView().tint(.white) }
                                    Text(isUploading ? "Mengunggah..." : "Upload ke SIAP")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(isUploading)
                        }
                    }
                }

                Section("Foto Online (\(onlineImages.count))") {
                    if onlineImages.isEmpty {
                        Text("Belum ada foto online.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(onlineImages) { item in
                            HStack(spacing: 12) {
                                if let url = item.resolvedURL {
                                    AsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .cornerRadius(8)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.ketPraPemeriksaan).font(.subheadline.bold())
                                    if !item.seriBarang.isEmpty {
                                        Text("Seri: \(item.seriBarang) \(item.ketSeriBarang)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if !item.id.isEmpty {
                                    Button(role: .destructive) {
                                        Task { await deleteOnlinePhoto(item.id) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Tanda Tangan PJ (PPJK/Importir)") {
                    TextField("Nama Lengkap PJ", text: $namaPj)
                    SignaturePadView(store: pjSig)
                    HStack {
                        Button("Hapus") { pjSig.clear() }.buttonStyle(.bordered)
                        Spacer()
                        Button("Upload TTD PJ") {
                            Task { await uploadTtdPj() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SiapPalette.navy)
                        .disabled(isBusyAction)
                    }
                }

                Section("Aksi Dokumen") {
                    Button {
                        Task { await selesaiPeriksa() }
                    } label: {
                        Label("Tandai Selesai Periksa", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isBusyAction)

                    Button(role: .destructive) {
                        Task { await batalPeriksa() }
                    } label: {
                        Label("Batalkan Pemeriksaan", systemImage: "xmark.octagon.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isBusyAction)
                }
            }
            .navigationTitle("PIB \(pib.noPib)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tutup") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { pickerSource.map { SourceWrapper(type: $0) } },
                set: { pickerSource = $0?.type }
            )) { wrap in
                ImagePicker(sourceType: wrap.type) { img in
                    pickedImage = img
                }
            }
            .task {
                isLcl = pib.isLclDefault
                if pib.namaPj != "-" { namaPj = pib.namaPj }
                locationMgr.request()
                await loadDetail()
            }
            .onChange(of: selectedNokon) { _ in
                Task { await loadPhotos() }
            }
        }
    }

    private struct SourceWrapper: Identifiable {
        let id = UUID()
        let type: UIImagePickerController.SourceType
    }

    private func loadDetail() async {
        do {
            dokInfo = try await SiapApiClient.shared.fetchDokumen(kodeTiket: pib.kodeTiket)
            containers = try await SiapApiClient.shared.fetchContainers(kodeTiket: pib.kodeTiket)
            if let first = containers.first {
                selectedNokon = first.noContainer
                isLcl = false
            } else {
                isLcl = true
            }
            await loadPhotos()
        } catch {
            app.showToast("Gagal memuat detail: \(error.localizedDescription)")
        }
    }

    private func loadPhotos() async {
        do {
            onlineImages = try await SiapApiClient.shared.fetchImages(
                kodeTiket: pib.kodeTiket,
                nokon: isLcl ? "" : selectedNokon
            )
        } catch {
            app.showToast("Gagal memuat galeri: \(error.localizedDescription)")
        }
    }

    private func scanOcr(_ img: UIImage) async {
        if let found = await ContainerOcrScanner.scanContainerNumber(from: img) {
            if containers.contains(where: { $0.noContainer.uppercased() == found }) {
                selectedNokon = found
                isLcl = false
                app.showToast("Kontainer terdeteksi & dipilih: \(found)")
            } else {
                ketSeri = found
                app.showToast("OCR terbaca: \(found)")
            }
        } else {
            app.showToast("Nomor kontainer tidak terdeteksi pada foto.")
        }
    }

    private func uploadPhoto(_ img: UIImage) async {
        isUploading = true
        defer { isUploading = false }
        let waktu = SiapCrypto.currentExifTimestamp()
        let bulanTahun = SiapCrypto.currentMonthYear()
        let activeC = containers.first(where: { $0.noContainer == selectedNokon })
        let filename = SiapCrypto.buildInspectionFileName(
            kodeTiket: pib.kodeTiket,
            isLcl: isLcl,
            nokon: selectedNokon,
            waktuFoto: waktu,
            stepLabel: selectedStep.label,
            stepCode: selectedStep.code,
            urutanBarang: seriBarang
        )
        guard let jpegData = ImageWatermarkProcessor.process(
            image: img,
            watermark: useWatermark,
            noPib: pib.noPib,
            nokon: isLcl ? "LCL" : selectedNokon,
            stepLabel: selectedStep.label,
            lokasi: locationMgr.coordinateText
        ) else {
            app.showToast("Gagal memproses gambar.")
            return
        }

        do {
            _ = try await SiapFtpClient.shared.upload(remoteDir: bulanTahun, remoteFilename: filename, data: jpegData)
            let relUrl = "\(bulanTahun)/\(filename)"
            _ = try await SiapApiClient.shared.insertImage(
                isLcl: isLcl,
                kodeTiket: pib.kodeTiket,
                nokon: selectedNokon,
                urlImage: relUrl,
                stepLabel: selectedStep.label,
                seriBarang: seriBarang,
                ketSeriBarang: ketSeri,
                lokasi: locationMgr.coordinateText,
                ukuran: activeC?.ukuranContainer ?? "",
                waktuFoto: waktu,
                uraianBarang: uraianBarang,
                jumlahJenisKemasan: jmlKemasan
            )
            pickedImage = nil
            app.showToast("Upload foto berhasil (\(jpegData.count / 1024) KB)!")
            await loadPhotos()
        } catch {
            app.showToast("Upload gagal: \(error.localizedDescription)")
        }
    }

    private func deleteOnlinePhoto(_ id: String) async {
        do {
            try await SiapApiClient.shared.deleteImage(imageId: id)
            app.showToast("Foto berhasil dihapus.")
            await loadPhotos()
        } catch {
            app.showToast(error.localizedDescription)
        }
    }

    private func uploadTtdPj() async {
        guard !namaPj.trimmingCharacters(in: .whitespaces).isEmpty else {
            app.showToast("Isi Nama PJ terlebih dahulu.")
            return
        }
        guard !pjSig.isEmpty else {
            app.showToast("Silakan gambar tanda tangan PJ.")
            return
        }
        isBusyAction = true
        defer { isBusyAction = false }
        let bulanTahun = SiapCrypto.currentMonthYear()
        let filename = "ttd_pj_\(SiapCrypto.sanitizeToken(pib.kodeTiket))_\(Int(Date().timeIntervalSince1970)).jpg"
        guard let jpg = pjSig.renderImage().jpegData(compressionQuality: 0.9) else { return }
        do {
            _ = try await SiapFtpClient.shared.upload(remoteDir: bulanTahun, remoteFilename: filename, data: jpg)
            try await SiapApiClient.shared.insertTtdPj(kodeTiket: pib.kodeTiket, namaPj: namaPj, relUrl: "\(bulanTahun)/\(filename)")
            pjSig.clear()
            app.showToast("TTD PJ berhasil diunggah!")
        } catch {
            app.showToast(error.localizedDescription)
        }
    }

    private func selesaiPeriksa() async {
        isBusyAction = true
        defer { isBusyAction = false }
        do {
            try await SiapApiClient.shared.updateSelesaiPeriksa(kodeTiket: pib.kodeTiket)
            app.showToast("Status diperbarui: Selesai Periksa!")
            await app.loadPibs()
            dismiss()
        } catch {
            app.showToast(error.localizedDescription)
        }
    }

    private func batalPeriksa() async {
        isBusyAction = true
        defer { isBusyAction = false }
        do {
            try await SiapApiClient.shared.updateBatalPeriksa(kodeTiket: pib.kodeTiket)
            app.showToast("Pemeriksaan dibatalkan.")
            await app.loadPibs()
            dismiss()
        } catch {
            app.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Manual Doc Sheet

struct ManualDocSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var noPib = ""
    @State private var tglPib = Date()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nomor PIB (6 digit)", text: $noPib)
                    .keyboardType(.numberPad)
                DatePicker("Tanggal PIB", selection: $tglPib, displayedComponents: .date)
                Button {
                    Task { await save() }
                } label: {
                    Text(isSaving ? "Menyimpan..." : "Simpan Dokumen Manual")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SiapPalette.navy)
                .disabled(noPib.isEmpty || isSaving)
            }
            .navigationTitle("Tambah Dokumen Manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Tutup") { dismiss() } }
            }
        }
    }

    private func save() async {
        guard let nip = app.session?.nip else { return }
        isSaving = true
        defer { isSaving = false }
        let df = SiapCrypto.wibFormatter("yyyy-MM-dd")
        do {
            try await SiapApiClient.shared.insertDokManual(nip: nip, noPib: noPib, tglPib: df.string(from: tglPib))
            app.showToast("Dokumen manual ditambahkan!")
            await app.loadPibs()
            dismiss()
        } catch {
            app.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Tab 4: TPS Monitoring

struct TpsTabView: View {
    @EnvironmentObject var app: AppState
    @State private var source: TpsSource = .graha
    @State private var searchText = ""
    @State private var onlyMine = false
    @State private var items: [TpsMonitorItem] = []
    @State private var isLoading = false

    private var filtered: [TpsMonitorItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if onlyMine && !item.isMyTask { return false }
            guard !q.isEmpty else { return true }
            return item.container.lowercased().contains(q)
                || item.pib.lowercased().contains(q)
                || item.importir.lowercased().contains(q)
                || item.summary.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sumber TPS", selection: $source) {
                    ForEach(TpsSource.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: source) { _ in Task { await load() } }

                HStack {
                    Toggle("Hanya Tugas Saya", isOn: $onlyMine)
                        .font(.caption.weight(.semibold))
                        .tint(SiapPalette.navy)
                    Spacer()
                    Text("\(filtered.count) data")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                List {
                    if isLoading {
                        ProgressView("Mengambil antrean \(source.rawValue)...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if filtered.isEmpty {
                        Text("Tidak ada data antrean.").foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.container).font(.headline.monospaced())
                                    Spacer()
                                    Text(item.isMyTask ? "Tugas Saya" : item.source)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(item.isMyTask ? Color.green.opacity(0.2) : SiapPalette.navy.opacity(0.15))
                                        .foregroundStyle(item.isMyTask ? .green : SiapPalette.navy)
                                        .clipShape(Capsule())
                                }
                                if !item.importir.isEmpty {
                                    Text(item.importir).font(.subheadline.weight(.medium))
                                }
                                Text(item.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Filter Kontainer / PIB / Importir")
                .refreshable { await load() }
            }
            .navigationTitle("Monitoring TPS")
            .task {
                if items.isEmpty { await load() }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let myPibs = Set(app.pibs.map { String($0.noPib.drop(while: { $0 == "0" })) }.filter { !$0.isEmpty })
        let myConts = Set(app.lorongItems.map { $0.noContainer.uppercased() }.filter { !$0.isEmpty && $0 != "-" })
        do {
            items = try await SiapApiClient.shared.fetchTps(source: source, myPibs: myPibs, myContainers: myConts)
        } catch {
            app.showToast("Gagal memuat \(source.rawValue): \(error.localizedDescription)")
        }
    }
}

// MARK: - Tab 5: User Profile, Diagnostics & TTD PPF

struct UserTabView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var ppfSig = SignatureStrokeStore()
    @State private var waPhone = ""
    @State private var waMsg = "Selamat pagi/siang, mohon kesiapan pemeriksaan fisik untuk PIB/Kontainer terkait di lokasi TPS. Terima kasih."
    @State private var isUploading = false
    @State private var diagResults: [(String, Bool, String)] = []
    @State private var isCheckingDiag = false

    var body: some View {
        NavigationStack {
            Form {
                if let sess = app.session {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sess.displayName)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                            Text("NIP: \(sess.nip)")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(Color.white.opacity(0.9))
                            if !sess.jabatan.isEmpty {
                                Text(sess.jabatan)
                                    .font(.caption)
                                    .foregroundStyle(SiapPalette.amber)
                            }
                            if !sess.usernameEmail.isEmpty {
                                Text(sess.usernameEmail)
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.8))
                            }
                            if !sess.phoneNumber.isEmpty {
                                Text("HP: \(sess.phoneNumber)")
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.8))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(SiapPalette.headerGradient)
                }

                Section("Tanda Tangan PPF (ttd_ppf/<NIP>.png)") {
                    if let nip = app.session?.nip, !nip.isEmpty,
                       let url = URL(string: "\(SiapCrypto.ttdPpfAssetsBase)/\(SiapCrypto.sanitizeToken(nip)).png") {
                        HStack {
                            Text("TTD Tersimpan:").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFit().frame(height: 50)
                            } placeholder: {
                                Text("-").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    SignaturePadView(store: ppfSig)
                    HStack {
                        Button("Hapus") { ppfSig.clear() }.buttonStyle(.bordered)
                        Spacer()
                        Button(isUploading ? "Mengunggah..." : "Upload TTD PPF") {
                            Task { await uploadPpf() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SiapPalette.navy)
                        .disabled(isUploading)
                    }
                }

                Section("Diagnostik Koneksi Server") {
                    Button {
                        Task { await runDiagnostics() }
                    } label: {
                        HStack {
                            if isCheckingDiag { ProgressView() }
                            Label(isCheckingDiag ? "Memeriksa..." : "Cek Koneksi SIAP & TPS", systemImage: "network")
                        }
                    }
                    ForEach(diagResults, id: \.0) { name, ok, detail in
                        HStack {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? .green : .red)
                            Text(name).font(.subheadline)
                            Spacer()
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("WhatsApp Cepat") {
                    TextField("Nomor WA (mis. 62812...)", text: $waPhone)
                        .keyboardType(.phonePad)
                    TextEditor(text: $waMsg)
                        .frame(height: 75)
                    Button {
                        app.openWhatsApp(phone: waPhone, message: waMsg)
                    } label: {
                        Label("Buka di WhatsApp", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }

                Section {
                    Button(role: .destructive) {
                        app.logout()
                    } label: {
                        Text("Keluar (Logout)").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Akun")
        }
    }

    private func runDiagnostics() async {
        isCheckingDiag = true
        defer { isCheckingDiag = false }
        let targets = [
            ("SIAP FB API", "https://bcpriok.net/siap/siapfb/"),
            ("SIAP 3.0 Web", "https://bcpriok.net/siap3.0/"),
            ("Graha TPS", "http://103.130.242.88/tpft/MON_SIAP_PERIKSA/")
        ]
        var res: [(String, Bool, String)] = []
        for (label, url) in targets {
            let (ok, info) = await SiapApiClient.shared.pingEndpoint(url)
            res.append((label, ok, info))
        }
        diagResults = res
    }

    private func uploadPpf() async {
        guard let nip = app.session?.nip else { return }
        guard !ppfSig.isEmpty else {
            app.showToast("Silakan gambar tanda tangan PPF.")
            return
        }
        isUploading = true
        defer { isUploading = false }
        guard let png = ppfSig.renderImage().pngData() else { return }
        let filename = "\(SiapCrypto.sanitizeToken(nip)).png"
        do {
            _ = try await SiapFtpClient.shared.upload(remoteDir: "ttd_ppf", remoteFilename: filename, data: png)
            try await SiapApiClient.shared.insertTtdPpf(nip: nip)
            app.showToast("TTD PPF berhasil diunggah (\(filename))!")
        } catch {
            app.showToast(error.localizedDescription)
        }
    }
}
