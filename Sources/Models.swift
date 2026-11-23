import Foundation

struct UserSession: Codable, Equatable {
    let username: String
    let password: String
    let nip: String
    let nama: String
    let email: String
}

struct PibDocument: Identifiable, Hashable {
    var id: String { kodeTiket.isEmpty ? "\(noPib)_\(tglPib)" : kodeTiket }
    let kodeTiket: String
    let noPib: String
    let tglPib: String
    let namaImportir: String
    let status: String
    let noContainer: String
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
        return URL(string: "https://bcpriok.net/siap/assets/apfb/\(urlImage)")
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

struct PendokItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

struct TpsMonitorItem: Identifiable {
    let id = UUID()
    let source: String
    let container: String
    let pib: String
    let summary: String
    let isMyTask: Bool
}

enum TpsSource: String, CaseIterable, Identifiable {
    case graha = "Graha"
    case npct = "NPCT1"
    case tpsl = "TPSL"

    var id: String { rawValue }
}
