import Foundation

struct UserSession: Codable, Equatable {
    let username: String
    let password: String
    let loginMessage: String
    let namaPemeriksa: String
    let usernameEmail: String
    let nip: String
    let idPemeriksa: String
    let jabatan: String
    let phoneNumber: String
    let statusCode: String
    let photoUrl: String

    var displayName: String {
        namaPemeriksa.isEmpty ? username : namaPemeriksa
    }

    /// Exact port of UserSession.Companion.fromPipeResponse(raw) in SIAP NEO v1.19.0
    static func fromPipeResponse(_ raw: String, username: String, password: String) -> UserSession? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 4 else { return nil }
        func part(_ idx: Int) -> String { idx < parts.count ? parts[idx] : "" }
        return UserSession(
            username: username,
            password: password,
            loginMessage: part(0),
            namaPemeriksa: part(1),
            usernameEmail: part(2),
            nip: part(3),
            idPemeriksa: part(4),
            jabatan: part(5),
            phoneNumber: part(6),
            statusCode: part(7),
            photoUrl: part(8)
        )
    }
}

/// Exact 24-field port of PibDocument in SIAP NEO v1.19.0
struct PibDocument: Identifiable, Hashable, Codable {
    var id: String { kodeTiket.isEmpty ? "\(noPib)_\(tglPib)" : kodeTiket }
    let kodeTiket: String
    let noPib: String
    let tglPib: String
    let jenisDokumen: String
    let importir: String
    let kodeTps: String
    let jenisKontainer: String
    let ipCeisa: String
    let namaPfpd: String
    let noHpPfpd: String
    let atensi: String
    let namaPj: String
    let hpPj: String
    let nomorBap: String
    let tglBap: String
    let persentasePeriksa: String
    let status: String
    let jumlahItem: String
    let barcon: String
    let pendampingan: String
    let bidangPendamping: String
    let namaPendamping: String
    let kendala: String
    let cluster: String

    /// Exact port of Android PibDocument.getClientIdentityKey()
    var clientIdentityKey: String {
        let trimmedTiket = kodeTiket.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTiket.isEmpty && trimmedTiket != "-" && trimmedTiket.lowercased() != "null" {
            return "T:\(trimmedTiket.uppercased())"
        }
        let pibPart = noPib.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let tglPart = tglPib.trimmingCharacters(in: .whitespacesAndNewlines)
        return "P:\(pibPart)|\(tglPart)"
    }

    var tglPibFormatted: String {
        SiapCrypto.formatDisplayDate(tglPib)
    }

    var tpsCardText: String {
        let s = kodeTps.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s.isEmpty || s.lowercased() == "null" || s == "-") ? "-" : s
    }

    var pfpdCardText: String {
        let s = namaPfpd.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s.isEmpty || s.lowercased() == "null" || s == "-") ? "Belum ada PFPD" : s
    }

    var cleanedContainerType: String {
        let s = jenisKontainer.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "-" || s.lowercased() == "null" { return "" }
        let up = s.uppercased()
        if up.contains("LCL") { return "LCL" }
        if up.contains("FCL") { return "FCL" }
        return up
    }

    var cleanedNamaPj: String {
        let s = namaPj.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "-" || s.lowercased() == "null" { return "-" }
        let stripped = s.replacingOccurrences(
            of: "\\s*\\((PIC|PJ|PPJK)\\)\\s*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "-" : stripped
    }

    var hasPhonePj: Bool {
        let s = hpPj.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "-" || s.lowercased() == "null" { return false }
        return s.contains(where: \.isNumber)
    }

    var hasAtensi: Bool {
        let s = atensi.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !s.isEmpty && s != "-" && s != "null" && s != "not found" && s != "tidak ada"
    }

    var isLclDefault: Bool {
        jenisKontainer.uppercased().contains("LCL")
    }

    var isSudahBapOrSelesai: Bool {
        let s = status.lowercased()
        let hasBapNo = !nomorBap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nomorBap != "-" && nomorBap.lowercased() != "null"
        return hasBapNo || s.contains("selesai") || s.contains("done") || s.contains("bap")
    }

    var normalizedStatusCategory: String {
        let s = status.lowercased()
        if s.contains("selesai") || s.contains("done") || s.contains("bap") { return "selesai" }
        if s.contains("sedang") || s.contains("proses") || s.contains("progress") { return "sedang" }
        if s.contains("siap") { return "siap" }
        if s.contains("pending") || s.contains("tunda") || s.contains("hold") { return "pending" }
        return "lainnya"
    }
}

/// Exact port of Android NotificationOpenRequest + Hubungi PJ action
struct NotificationOpenRequest: Equatable {
    let id = UUID()
    let kodeTiket: String
    let noPib: String
    let openPibDocument: Bool
    let pib: PibDocument?
    let hubPjPhone: String?
    let hubPjMessage: String?

    static func == (lhs: NotificationOpenRequest, rhs: NotificationOpenRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppUpdateInfo: Identifiable, Equatable {
    var id: String { "\(remoteVersion)_\(remoteBuild)" }
    let remoteVersion: String
    let remoteBuild: Int
    let ipaDownloadUrl: String
    let ipaSizeBytes: Int
    let publishedAt: String
    let notes: String
    let mandatory: Bool

    var formattedSize: String {
        guard ipaSizeBytes > 0 else { return "" }
        let mb = Double(ipaSizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.2f MB", mb)
    }
}

/// Exact port of AssignedIpItem from SIAP 3.0 siapfb_pemeriksa/browse_data
struct AssignedIpItem: Identifiable, Hashable {
    var id: String { "\(kodeTiket)_\(noPib)_\(hashId)" }
    let kodeTiket: String
    let noPib: String
    let tglPib: String
    let importir: String
    let jenisDokumen: String
    let jenisKontainer: String
    let jumlahKontainer: String
    let tps: String
    let waktuIp: String
    let status: String
    let namaPj: String
    let hpPj: String
    let namaPfpd: String
    let hpPfpd: String
    let atensi: String
    let hashId: String
    let linkCetakBap: String
    let linkBuatBap: String

    var isSudahBap: Bool {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.contains("sudah bap") || s == "bap" || s.contains("selesai") || !linkCetakBap.isEmpty
    }

    func toPibDocument() -> PibDocument {
        PibDocument(
            kodeTiket: kodeTiket,
            noPib: noPib,
            tglPib: tglPib,
            jenisDokumen: jenisDokumen,
            importir: importir,
            kodeTps: tps,
            jenisKontainer: jenisKontainer,
            ipCeisa: waktuIp,
            namaPfpd: namaPfpd,
            noHpPfpd: hpPfpd,
            atensi: atensi,
            namaPj: namaPj,
            hpPj: hpPj,
            nomorBap: isSudahBap ? "SUDAH BAP" : "",
            tglBap: "",
            persentasePeriksa: "",
            status: status,
            jumlahItem: jumlahKontainer,
            barcon: "",
            pendampingan: "",
            bidangPendamping: "",
            namaPendamping: "",
            kendala: "",
            cluster: ""
        )
    }
}

struct ContainerItem: Identifiable, Hashable {
    var id: String { noContainer }
    let noContainer: String
    let ukuranContainer: String
    let instruksiLorong: String
    let pelaksanaanLorong: String
    let alasanLorong: String
    let teknikPeriksa: String
}

/// Exact port of InstruksiLorongItem from detailkontainer_nip
struct InstruksiLorongItem: Identifiable, Hashable {
    var id: String { "\(kodeTiket)_\(noContainer)" }
    let kodeTiket: String
    let noContainer: String
    let ukuranContainer: String
    let noPib: String
    let tglPib: String
    let instruksiLorong: String
    let pelaksanaanLorong: String
    let alasanLorong: String
    let teknikPeriksa: String
    let status: String
    let image: String
}

struct OnlineImageItem: Identifiable, Hashable {
    let id: String
    let urlImage: String
    let imageHttpUrl: String
    let ketPraPemeriksaan: String
    let seriBarang: String
    let ketSeriBarang: String

    var resolvedURL: URL? {
        if imageHttpUrl.hasPrefix("http") {
            return URL(string: imageHttpUrl)
        }
        if !urlImage.isEmpty {
            return URL(string: "https://bcpriok.net/siap/assets/apfb/\(urlImage)")
        }
        return nil
    }
}

struct StepOption: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let label: String

    /// Short section title matching the CEISA/SIAP Foto Kontainer card UI
    var sectionTitle: String {
        switch code {
        case "1": return "ID Card PJ"
        case "2": return "Segel"
        case "3": return "Kontainer Tertutup"
        case "4": return "Kontainer Buka Setengah"
        case "5": return "Kontainer Buka Seluruh"
        case "6": return "Foto Barang"
        case "7": return "Lorong"
        case "8": return "Kemasan Barang"
        case "9": return "Barang Contoh"
        default: return label
        }
    }

    var isBarangStep: Bool {
        code == "6" || code == "8" || code == "9"
    }

    func matches(_ ketPraPemeriksaan: String) -> Bool {
        let norm = ketPraPemeriksaan
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if norm == label.lowercased() || norm == sectionTitle.lowercased() {
            return true
        }
        switch code {
        case "2":
            return norm.contains("segel")
        case "3":
            return norm.contains("tertutup")
        case "4":
            return norm.contains("setengah")
        case "5":
            return norm.contains("seluruh") || norm.contains("penuh") || norm.contains("terbuka penuh")
        case "7":
            return norm.contains("lorong")
        case "1":
            return norm.contains("id card") || norm.contains("id_card") || norm.contains("idcard")
        case "8":
            return norm.contains("kemasan")
        case "9":
            return norm.contains("contoh") || norm.contains("barcon")
        case "6":
            return norm.contains("barang") && !norm.contains("kemasan") && !norm.contains("contoh")
        default:
            return false
        }
    }

    static let allSteps: [StepOption] = [
        StepOption(code: "1", label: "ID Card PJ"),
        StepOption(code: "2", label: "Foto Segel"),
        StepOption(code: "3", label: "Foto Kontainer Tertutup"),
        StepOption(code: "4", label: "Foto Kontainer Buka Setengah"),
        StepOption(code: "5", label: "Foto Kontainer Buka Seluruh"),
        StepOption(code: "6", label: "Foto Barang"),
        StepOption(code: "7", label: "Foto Lorong"),
        StepOption(code: "8", label: "Foto Kemasan Barang"),
        StepOption(code: "9", label: "Foto Barang Contoh")
    ]

    /// Ordered categories displayed inside the "Foto Kontainer" card (strictly container photos only)
    static let containerPhotoSteps: [StepOption] = [
        StepOption(code: "2", label: "Foto Segel"),
        StepOption(code: "3", label: "Foto Kontainer Tertutup"),
        StepOption(code: "4", label: "Foto Kontainer Buka Setengah"),
        StepOption(code: "5", label: "Foto Kontainer Buka Seluruh"),
        StepOption(code: "7", label: "Foto Lorong")
    ]

    /// Ordered categories displayed inside the "Tambah Barang" sheet
    static let barangPhotoSteps: [StepOption] = [
        StepOption(code: "6", label: "Foto Barang"),
        StepOption(code: "8", label: "Foto Kemasan Barang"),
        StepOption(code: "9", label: "Foto Barang Contoh")
    ]
}

struct PendokBrowseItem: Identifiable, Hashable {
    var id: String { "\(actionId)_\(noPib)_\(noAju)" }
    let rowId: String
    let noPib: String
    let tglPib: String
    let noAju: String
    let namaImportir: String
    let npwpImportir: String
    let pfpd: String
    let jalur: String
    let status: String
    let isDitolak: Bool
    let waktuStatus: String
    let alasanPenolakan: String
    let disdok: String
    let coo: String
    let actionId: String
    let riwayatTerakhir: String
}

struct PendokDocumentAttachment: Identifiable, Hashable {
    var id: String { "\(rawId)_\(fileUrl)" }
    let rawId: String
    let kodePelayanan: String
    let jenisDokumen: String
    let namaDokumen: String
    let fileUrl: String
    let tglUpload: String
}

// MARK: - TPS Monitoring Models (1:1 Port of Android GrahaMonitorItem, NpctMonitorItem, TpslMonitorItem, TpsMonitorSnapshot)

struct GrahaMonitorItem: Identifiable, Hashable, Codable {
    var id: String { "graha_\(noContainer)_\(noPib)_\(tglPib)_\(lokasi)_\(status)" }
    let noContainer: String
    let size: String
    let lokasi: String
    let noPib: String
    let tglPib: String
    let importir: String
    let status: String
    let isMyTask: Bool

    init(
        noContainer: String,
        size: String,
        lokasi: String,
        noPib: String,
        tglPib: String,
        importir: String,
        status: String,
        isMyTask: Bool = false
    ) {
        self.noContainer = noContainer
        self.size = size
        self.lokasi = lokasi
        self.noPib = noPib
        self.tglPib = tglPib
        self.importir = importir
        self.status = status
        self.isMyTask = isMyTask
    }

    func with(tglPib: String? = nil, importir: String? = nil, isMyTask: Bool? = nil) -> GrahaMonitorItem {
        GrahaMonitorItem(
            noContainer: noContainer,
            size: size,
            lokasi: lokasi,
            noPib: noPib,
            tglPib: tglPib ?? self.tglPib,
            importir: importir ?? self.importir,
            status: status,
            isMyTask: isMyTask ?? self.isMyTask
        )
    }
}

struct NpctMonitorItem: Identifiable, Hashable, Codable {
    var id: String { "npct_\(noContainer)_\(noPib)_\(tglPib)_\(lokasi)" }
    let noContainer: String
    let size: String
    let lokasi: String
    let noPib: String
    let tglPib: String
    let waktuGateIn: String
    let status: String
    let keterangan: String
    let note: String
    let respon: String
    let isMyTask: Bool
    let importir: String
    let waktuSiapPeriksa: String

    init(
        noContainer: String,
        size: String,
        lokasi: String,
        noPib: String,
        tglPib: String,
        waktuGateIn: String = "",
        status: String,
        keterangan: String = "-",
        note: String = "-",
        respon: String = "",
        isMyTask: Bool = false,
        importir: String = "",
        waktuSiapPeriksa: String = ""
    ) {
        self.noContainer = noContainer
        self.size = size
        self.lokasi = lokasi
        self.noPib = noPib
        self.tglPib = tglPib
        self.waktuGateIn = waktuGateIn
        self.status = status
        self.keterangan = keterangan
        self.note = note
        self.respon = respon
        self.isMyTask = isMyTask
        self.importir = importir
        self.waktuSiapPeriksa = waktuSiapPeriksa
    }

    func with(tglPib: String? = nil, importir: String? = nil, isMyTask: Bool? = nil) -> NpctMonitorItem {
        NpctMonitorItem(
            noContainer: noContainer,
            size: size,
            lokasi: lokasi,
            noPib: noPib,
            tglPib: tglPib ?? self.tglPib,
            waktuGateIn: waktuGateIn,
            status: status,
            keterangan: keterangan,
            note: note,
            respon: respon,
            isMyTask: isMyTask ?? self.isMyTask,
            importir: importir ?? self.importir,
            waktuSiapPeriksa: waktuSiapPeriksa
        )
    }
}

struct TpslMonitorItem: Identifiable, Hashable, Codable {
    var id: String { "tpsl_\(cluster)_\(noPib)_\(kodeTiket)_\(pengajuan)_\(antrian)" }
    let pengajuan: String
    let antrian: String
    let kodeTiket: String
    let importir: String
    let noPib: String
    let tglPib: String
    let lokasi: String
    let keputusan: String
    let cluster: String
    let isMyTask: Bool

    init(
        pengajuan: String,
        antrian: String,
        kodeTiket: String,
        importir: String,
        noPib: String,
        tglPib: String,
        lokasi: String,
        keputusan: String,
        cluster: String,
        isMyTask: Bool = false
    ) {
        self.pengajuan = pengajuan
        self.antrian = antrian
        self.kodeTiket = kodeTiket
        self.importir = importir
        self.noPib = noPib
        self.tglPib = tglPib
        self.lokasi = lokasi
        self.keputusan = keputusan
        self.cluster = cluster
        self.isMyTask = isMyTask
    }

    func with(isMyTask: Bool) -> TpslMonitorItem {
        TpslMonitorItem(
            pengajuan: pengajuan,
            antrian: antrian,
            kodeTiket: kodeTiket,
            importir: importir,
            noPib: noPib,
            tglPib: tglPib,
            lokasi: lokasi,
            keputusan: keputusan,
            cluster: cluster,
            isMyTask: isMyTask
        )
    }
}

struct TpsMonitorSnapshot: Equatable, Codable {
    var grahaRows: [GrahaMonitorItem] = []
    var npctRows: [NpctMonitorItem] = []
    var tpslRows: [TpslMonitorItem] = []
    var lastUpdated: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var failedSources: [String] = []

    var hasAnyData: Bool {
        !grahaRows.isEmpty || !npctRows.isEmpty || !tpslRows.isEmpty
    }
}

enum TpsSource: String, CaseIterable, Identifiable {
    case graha = "Graha"
    case npct = "NPCT1"
    case tpsl = "TPSL"

    var id: String { rawValue }
}

enum TpsFilterStatus: Int, CaseIterable, Identifiable {
    case all = 0
    case siap = 1
    case sedang = 2
    case ppk = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .all: return "SEMUA"
        case .siap: return "SIAP"
        case .sedang: return "PROSES"
        case .ppk: return "PPK"
        }
    }
}

enum GrahaSortOption: String, CaseIterable, Identifiable {
    case `default` = "Siap Periksa (Terbaru)"
    case lokasiAsc = "Lokasi (A-Z)"
    case containerAsc = "No. Kontainer (A-Z)"
    case pibAsc = "No. PIB (A-Z)"

    var id: String { rawValue }
    var label: String { rawValue }
}

enum NpctSortOption: String, CaseIterable, Identifiable {
    case siapPeriksaDesc = "Siap Periksa (Terbaru)"
    case siapPeriksaAsc = "Siap Periksa (Terlama)"
    case containerAsc = "No. Kontainer (A-Z)"
    case pibAsc = "No. PIB (A-Z)"

    var id: String { rawValue }
    var label: String { rawValue }
}

enum TpslSortOption: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case tpsAsc = "Berdasarkan TPS (A-Z)"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Lightweight target for opening the quick Lampiran sheet from any TPS card (Graha / NPCT1 / TPSL)
struct TpsLampiranTarget: Identifiable, Hashable {
    var id: String { "\(source)_\(container)_\(pib)_\(lokasi)" }
    let source: String
    let container: String
    let pib: String
    let importir: String
    let status: String
    let lokasi: String
    let isMyTask: Bool
}

enum HomeStatusFilter: String, CaseIterable, Identifiable {
    case semua = "Semua"
    case siap = "Siap"
    case sedang = "Sedang"
    case selesai = "Selesai"
    case atensi = "Atensi"

    var id: String { rawValue }
}

// MARK: - Redist & Hold Models (1:1 Port of Android RedistHoldTableParser & RedistFormSchema)

struct RedistHistoryItem: Identifiable, Hashable {
    var id: String { "\(kodeTiket)_\(noPib)_\(tanggalPengajuan)_\(status)" }
    let kodeTiket: String
    let importir: String
    let noPib: String
    let tglPib: String
    let tps: String
    let cluster: String
    let alasan: String
    let tanggalPengajuan: String
    let status: String
}

struct HoldHistoryItem: Identifiable, Hashable {
    var id: String { "\(tanggalPengajuan)_\(cluster)_\(waktuMulai)_\(waktuSelesai)_\(status)" }
    let tanggalPengajuan: String
    let cluster: String
    let alasan: String
    let waktuMulai: String
    let waktuSelesai: String
    let status: String
}

struct SiapSelectOption: Identifiable, Hashable {
    var id: String { value }
    let value: String
    let label: String
}

struct RedistHoldFormSchema: Equatable {
    let clusters: [SiapSelectOption]
    let alasanOptions: [SiapSelectOption]

    static let defaultClusters: [SiapSelectOption] = [
        SiapSelectOption(value: "GSRA", label: "GRAHA"),
        SiapSelectOption(value: "NCT1", label: "NPCT1"),
        SiapSelectOption(value: "ZONA1", label: "ZONA1"),
        SiapSelectOption(value: "ZONA2", label: "ZONA2"),
        SiapSelectOption(value: "ZONA3", label: "ZONA3"),
        SiapSelectOption(value: "JI", label: "JOINT INSPECTION"),
        SiapSelectOption(value: "LCL", label: "LCL")
    ]

    static let defaultRedistAlasan: [SiapSelectOption] = [
        SiapSelectOption(value: "Off", label: "Off"),
        SiapSelectOption(value: "Periksa Mendalam >1 Dokumen", label: "Periksa Mendalam >1 Dokumen"),
        SiapSelectOption(value: "Cuti", label: "Cuti"),
        SiapSelectOption(value: "Izin", label: "Izin"),
        SiapSelectOption(value: "ST", label: "ST")
    ]

    static let defaultHoldAlasan: [SiapSelectOption] = [
        SiapSelectOption(value: "Off", label: "Off"),
        SiapSelectOption(value: "Periksa Mendalam", label: "Periksa Mendalam"),
        SiapSelectOption(value: "Cuti", label: "Cuti"),
        SiapSelectOption(value: "Izin", label: "Izin"),
        SiapSelectOption(value: "ST", label: "ST"),
        SiapSelectOption(value: "Menyelesaikan Dokumen", label: "Menyelesaikan Tanggungan Dokumen")
    ]
}
