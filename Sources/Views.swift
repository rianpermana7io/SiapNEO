import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var session: UserSession?
    @Published var pibs: [PibDocument] = []
    @Published var isLoadingPibs = false
    @Published var toastMessage: String?

    private let sessionKey = "siapneo_ios_session_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let saved = try? JSONDecoder().decode(UserSession.self, from: data) {
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
        guard let nip = session?.nip else { return }
        isLoadingPibs = true
        defer { isLoadingPibs = false }
        do {
            pibs = try await SiapApiClient.shared.fetchHomescreen(nip: nip)
        } catch {
            showToast("Gagal memuat PIB: \(error.localizedDescription)")
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.blue)
                    Text("SIAP NEO")
                        .font(.largeTitle.bold())
                    Text("Native iOS Edition • BC Tanjung Priok")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    TextField("Username / NIP", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)

                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)

                    if let errorMsg {
                        Text(errorMsg)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await performLogin() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text(isLoading ? "Menghubungkan..." : "Masuk ke SIAP NEO")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading || username.isEmpty || password.isEmpty)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
    }

    private func performLogin() async {
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        do {
            let sess = try await SiapApiClient.shared.login(username: username, password: password)
            app.saveSession(sess)
            await app.loadPibs()
            app.showToast("Selamat datang, \(sess.nama)!")
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Tab 1: Home (PIB List)

struct HomeTabView: View {
    @EnvironmentObject var app: AppState
    @State private var searchText = ""
    @State private var selectedPib: PibDocument?
    @State private var showManualSheet = false

    private var filteredPibs: [PibDocument] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return app.pibs }
        return app.pibs.filter {
            $0.noPib.lowercased().contains(q)
                || $0.kodeTiket.lowercased().contains(q)
                || $0.namaImportir.lowercased().contains(q)
                || $0.noContainer.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if app.isLoadingPibs && app.pibs.isEmpty {
                    ProgressView("Memuat daftar PIB...")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filteredPibs.isEmpty {
                    Text("Belum ada dokumen PIB aktif.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredPibs) { pib in
                        Button {
                            selectedPib = pib
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("PIB \(pib.noPib)")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(pib.status)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.16))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(8)
                                }
                                if !pib.namaImportir.isEmpty {
                                    Text(pib.namaImportir)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                                HStack(spacing: 12) {
                                    Text("Tiket: \(pib.kodeTiket)")
                                    Text("Tgl: \(pib.tglPib)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Cari No PIB / Tiket / Kontainer")
            .refreshable { await app.loadPibs() }
            .navigationTitle("Tugas Pemeriksaan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showManualSheet = true } label: {
                        Label("Manual", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(item: $selectedPib) { pib in
                PibDetailSheet(pib: pib)
            }
            .sheet(isPresented: $showManualSheet) {
                ManualDocSheet()
            }
            .task {
                if app.pibs.isEmpty { await app.loadPibs() }
            }
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
    @State private var selectedStep = StepOption.allSteps[5] // Foto Barang
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
                Section("Informasi PIB") {
                    LabeledContent("No PIB", value: pib.noPib)
                    LabeledContent("Kode Tiket", value: pib.kodeTiket)
                    LabeledContent("Tanggal", value: pib.tglPib)
                    LabeledContent("Importir", value: dokInfo["nama_importir"] ?? dokInfo["importir"] ?? pib.namaImportir)
                    if let tps = dokInfo["lokasi_periksa"] ?? dokInfo["gudang"] ?? dokInfo["tps"], !tps.isEmpty {
                        LabeledContent("Lokasi / TPS", value: tps)
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
                                    .frame(width: 60, height: 60)
                                    .clipped()
                                    .cornerRadius(8)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.ketPraPemeriksaan).font(.subheadline.bold())
                                    if !item.seriBarang.isEmpty {
                                        Text("Seri: \(item.seriBarang)").font(.caption).foregroundStyle(.secondary)
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

// MARK: - Tab 2: Pendok Browse

struct PendokTabView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var items: [PendokItem] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView("Memuat Pendok SIAP 3.0...")
                } else if items.isEmpty {
                    Text("Cari nomor PIB atau importir untuk memuat data SIAP 3.0.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { it in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(it.title).font(.headline)
                            Text(it.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .searchable(text: $query, prompt: "Cari PIB / Importir di SIAP 3.0")
            .onSubmit(of: .search) { Task { await load() } }
            .refreshable { await load() }
            .navigationTitle("Browse Pendok")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cari") { Task { await load() } }
                }
            }
        }
    }

    private func load() async {
        guard let sess = app.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await SiapApiClient.shared.browsePendok(username: sess.username, password: sess.password, query: query)
        } catch {
            app.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Tab 3: TPS Monitoring

struct TpsTabView: View {
    @EnvironmentObject var app: AppState
    @State private var source: TpsSource = .graha
    @State private var searchText = ""
    @State private var items: [TpsMonitorItem] = []
    @State private var isLoading = false

    private var filtered: [TpsMonitorItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.container.lowercased().contains(q)
                || $0.pib.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
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
                .padding(.vertical, 8)
                .onChange(of: source) { _ in Task { await load() } }

                List {
                    if isLoading {
                        ProgressView("Mengambil antrean \(source.rawValue)...")
                    } else if filtered.isEmpty {
                        Text("Tidak ada data antrean.").foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.container).font(.headline)
                                    Spacer()
                                    Text(item.isMyTask ? "Tugas Saya" : item.source)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(item.isMyTask ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                                        .foregroundStyle(item.isMyTask ? .green : .blue)
                                        .cornerRadius(8)
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
        do {
            items = try await SiapApiClient.shared.fetchTps(source: source, myPibs: myPibs)
        } catch {
            app.showToast("Gagal memuat \(source.rawValue): \(error.localizedDescription)")
        }
    }
}

// MARK: - Tab 4: User Profile & TTD PPF

struct UserTabView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var ppfSig = SignatureStrokeStore()
    @State private var waPhone = ""
    @State private var waMsg = "Selamat pagi/siang, mohon kesiapan pemeriksaan fisik untuk PIB/Kontainer terkait di lokasi TPS. Terima kasih."
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            Form {
                if let sess = app.session {
                    Section("Profil Pemeriksa") {
                        LabeledContent("Nama", value: sess.nama)
                        LabeledContent("NIP", value: sess.nip)
                        if !sess.email.isEmpty {
                            LabeledContent("Email", value: sess.email)
                        }
                    }
                }

                Section("Tanda Tangan PPF (ttd_ppf/<NIP>.png)") {
                    SignaturePadView(store: ppfSig)
                    HStack {
                        Button("Hapus") { ppfSig.clear() }.buttonStyle(.bordered)
                        Spacer()
                        Button(isUploading ? "Mengunggah..." : "Upload TTD PPF") {
                            Task { await uploadPpf() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isUploading)
                    }
                }

                Section("WhatsApp Cepat") {
                    TextField("Nomor WA (mis. 62812...)", text: $waPhone)
                        .keyboardType(.phonePad)
                    TextEditor(text: $waMsg)
                        .frame(height: 80)
                    Button {
                        let digits = waPhone.filter(\.isNumber)
                        let enc = waMsg.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let str = digits.isEmpty ? "https://wa.me/?text=\(enc)" : "https://wa.me/\(digits)?text=\(enc)"
                        if let url = URL(string: str) {
                            UIApplication.shared.open(url)
                        }
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
