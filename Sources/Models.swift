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
struct PibDocument: Identifiable, Hashable {
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

struct AppUpdateInfo: Equatable {
    let remoteVersion: String
    let remoteBuild: Int
    let ipaDownloadUrl: String
    let notes: String
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

struct TpsMonitorItem: Identifiable {
    let id = UUID()
    let source: String
    let container: String
    let pib: String
    let importir: String
    let status: String
    let summary: String
    let isMyTask: Bool
}

enum TpsSource: String, CaseIterable, Identifiable {
    case graha = "Graha"
    case npct = "NPCT1"
    case tpsl = "TPSL"

    var id: String { rawValue }
}

enum HomeStatusFilter: String, CaseIterable, Identifiable {
    case semua = "Semua"
    case siap = "Siap"
    case sedang = "Sedang"
    case selesai = "Selesai"
    case atensi = "Atensi"

    var id: String { rawValue }
}
