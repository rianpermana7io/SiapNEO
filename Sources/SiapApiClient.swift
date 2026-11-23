import Foundation
import CryptoKit

enum SiapCrypto {
    static let apiSecret = "bc2021#PRiokAPFB135"
    static let siapFbBase = "https://bcpriok.net/siap/siapfb"
    static let siap3Base = "https://bcpriok.net/siap3.0"
    static let ttdPpfAssetsBase = "https://bcpriok.net/siap/assets/apfb/ttd_ppf"

    static func apiKey() -> String {
        let digest = Insecure.MD5.hash(data: Data(apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func kodularBase64(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(trimmed.utf8).base64EncodedString() + "\n"
    }

    static func sanitizeToken(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
            allowed.contains($0) ? String($0) : "_"
        }.joined()
    }

    static func wibFormatter(_ pattern: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Asia/Jakarta")
        df.dateFormat = pattern
        return df
    }

    static func currentMonthYear(_ date: Date = Date()) -> String {
        wibFormatter("yyyyMM").string(from: date)
    }

    static func currentExifTimestamp(_ date: Date = Date()) -> String {
        wibFormatter("yyyy:MM:dd HH:mm:ss").string(from: date)
    }

    static func currentDisplayClock(_ date: Date = Date()) -> String {
        wibFormatter("dd-MM-yyyy HH:mm:ss").string(from: date) + " WIB"
    }

    static func formatDisplayDate(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.lowercased() == "null" || t == "-" { return "-" }
        let parts = t.split(separator: "-")
        if parts.count == 3 && parts[0].count == 4 {
            return "\(parts[2])-\(parts[1])-\(parts[0])"
        }
        return t
    }

    static func buildInspectionFileName(
        kodeTiket: String,
        isLcl: Bool,
        nokon: String,
        waktuFoto: String,
        stepLabel: String,
        stepCode: String,
        urutanBarang: String = "",
        ext: String = "jpg"
    ) -> String {
        let contPart: String
        if isLcl {
            contPart = "LCL"
        } else {
            let cleaned = sanitizeToken(nokon)
            contPart = cleaned.isEmpty ? "CONT" : cleaned
        }
        let waktuPart = sanitizeToken(waktuFoto.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: ""))
        let stepPart = sanitizeToken(stepLabel.replacingOccurrences(of: " ", with: "_"))
        let extClean = ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return "\(sanitizeToken(kodeTiket))_\(contPart)_\(waktuPart)_\(sanitizeToken(stepCode))_\(stepPart)\(sanitizeToken(urutanBarang)).\(extClean.isEmpty ? "jpg" : extClean)"
    }
}

final class PermissiveTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

enum SiapApiError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL server tidak valid."
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(120))"
        case .message(let msg): return msg
        }
    }
}

final class SiapApiClient {
    static let shared = SiapApiClient()

    private let session: URLSession
    private let siap3Session: URLSession
    private var siap3LoggedInUser: String?
    private var siap3LoggedInAt: Date = .distantPast
    private let homescreenBypassNips: Set<String> = ["199509182015021003"]

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 45
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
        ]
        self.session = URLSession(configuration: cfg, delegate: PermissiveTLSDelegate(), delegateQueue: nil)

        let cfg3 = URLSessionConfiguration.default
        cfg3.timeoutIntervalForRequest = 25
        cfg3.httpCookieAcceptPolicy = .always
        cfg3.httpShouldSetCookies = true
        cfg3.httpCookieStorage = HTTPCookieStorage.shared
        cfg3.httpAdditionalHeaders = cfg.httpAdditionalHeaders
        self.siap3Session = URLSession(configuration: cfg3, delegate: PermissiveTLSDelegate(), delegateQueue: nil)
    }

    private func formEncode(_ params: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let joined = params.map { key, val in
            let k = (key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key).replacingOccurrences(of: "%20", with: "+")
            let v = (val.addingPercentEncoding(withAllowedCharacters: allowed) ?? val).replacingOccurrences(of: "%20", with: "+")
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(joined.utf8)
    }

    func postForm(endpoint: String, fields: [(String, String)]) async throws -> (Int, Data, String) {
        guard let url = URL(string: "\(SiapCrypto.siapFbBase)/\(endpoint)") else {
            throw SiapApiError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var payload: [(String, String)] = [("key", SiapCrypto.apiKey())]
        payload.append(contentsOf: fields)
        req.httpBody = formEncode(payload)

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(code) else {
            throw SiapApiError.httpError(code, text)
        }
        return (code, data, text)
    }

    private func cleanField(_ dict: [String: Any], _ key: String, fallback: String = "-") -> String {
        guard let val = dict[key], !(val is NSNull) else { return fallback }
        let s = String(describing: val).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.lowercased() == "null" { return fallback }
        return s
    }

    private func parsePibArray(_ data: Data) -> [PibDocument] {
        guard let rawStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawStr.isEmpty, rawStr != "[]", rawStr != "null" else {
            return []
        }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(rawStr.utf8)) else {
            return []
        }
        let arr: [[String: Any]]
        if let direct = obj as? [[String: Any]] {
            arr = direct
        } else if let wrap = obj as? [String: Any], let inner = wrap["data"] as? [[String: Any]] {
            arr = inner
        } else {
            return []
        }

        return arr.map { d in
            PibDocument(
                kodeTiket: cleanField(d, "kode_tiket", fallback: cleanField(d, "id", fallback: "")),
                noPib: cleanField(d, "no_pib", fallback: cleanField(d, "nopib", fallback: "-")),
                tglPib: cleanField(d, "tgl_pib", fallback: cleanField(d, "tglpib", fallback: "-")),
                jenisDokumen: cleanField(d, "jenis_dokumen", fallback: "PIB"),
                importir: cleanField(d, "importir", fallback: cleanField(d, "nama_importir", fallback: "-")),
                kodeTps: cleanField(d, "kode_tps", fallback: "-"),
                jenisKontainer: cleanField(d, "jenis_kontainer", fallback: "-"),
                ipCeisa: cleanField(d, "ip_ceisa", fallback: "-"),
                namaPfpd: cleanField(d, "nama", fallback: "-"),
                noHpPfpd: cleanField(d, "no_hp", fallback: ""),
                atensi: cleanField(d, "atensi", fallback: ""),
                namaPj: cleanField(d, "nama_pj", fallback: "-"),
                hpPj: cleanField(d, "hp_pj", fallback: ""),
                nomorBap: cleanField(d, "nomor_bap", fallback: ""),
                tglBap: cleanField(d, "tgl_bap", fallback: "-"),
                persentasePeriksa: cleanField(d, "persentase_periksa", fallback: "-"),
                status: cleanField(d, "status", fallback: "Aktif"),
                jumlahItem: cleanField(d, "jumlah_item", fallback: "-"),
                barcon: cleanField(d, "barcon", fallback: "-"),
                pendampingan: cleanField(d, "pendampingan", fallback: "-"),
                bidangPendamping: cleanField(d, "bidang_pendamping", fallback: "-"),
                namaPendamping: cleanField(d, "nama_pendamping", fallback: "-"),
                kendala: cleanField(d, "kendala", fallback: "-"),
                cluster: cleanField(d, "cluster", fallback: "-")
            )
        }
    }

    // MARK: - Auth (Exact Pipe-Delimited Protocol from LoginScreen.kt)

    func login(username: String, password: String) async throws -> UserSession {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let (_, _, raw) = try await postForm(endpoint: "login", fields: [
            ("username", u),
            ("password", SiapCrypto.kodularBase64(p))
        ])

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstPart = trimmed.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if firstPart.caseInsensitiveCompare("Berhasil Login") == .orderedSame {
            guard let sess = UserSession.fromPipeResponse(trimmed, username: u, password: p) else {
                throw SiapApiError.message("Format data akun tidak valid dari server SIAP.")
            }
            return sess
        }

        // Fallback if server returned an error text
        if trimmed.isEmpty {
            throw SiapApiError.message("Username atau Password salah.")
        }
        throw SiapApiError.message(trimmed)
    }

    // MARK: - Homescreen PIB, Detail Kontainer, Browse Data

    func fetchHomescreen(nip: String) async throws -> [PibDocument] {
        let cleanNip = nip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNip.isEmpty else { return [] }

        if !homescreenBypassNips.contains(cleanNip) {
            let (_, data, _) = try await postForm(endpoint: "homescreen", fields: [("nipppf", cleanNip)])
            let list = parsePibArray(data)
            if !list.isEmpty {
                return list
            }
        }

        // Fallback to detailkontainer_nip (matches SIAP NEO getHomescreenPibFromDetail)
        let lorong = try await fetchDetailKontainerNip(nip: cleanNip)
        var seen = Set<String>()
        var out: [PibDocument] = []
        for row in lorong {
            if row.kodeTiket.isEmpty || seen.contains(row.kodeTiket) { continue }
            seen.insert(row.kodeTiket)
            out.append(PibDocument(
                kodeTiket: row.kodeTiket,
                noPib: row.noPib,
                tglPib: row.tglPib,
                jenisDokumen: "PIB",
                importir: "-",
                kodeTps: "-",
                jenisKontainer: row.noContainer.isEmpty ? "LCL" : "FCL",
                ipCeisa: "-",
                namaPfpd: "-",
                noHpPfpd: "",
                atensi: "",
                namaPj: "-",
                hpPj: "",
                nomorBap: "",
                tglBap: "-",
                persentasePeriksa: "-",
                status: row.status,
                jumlahItem: "-",
                barcon: "-",
                pendampingan: "-",
                bidangPendamping: "-",
                namaPendamping: "-",
                kendala: "-",
                cluster: "-"
            ))
        }
        return out
    }

    func fetchDetailKontainerNip(nip: String) async throws -> [InstruksiLorongItem] {
        let (_, data, _) = try await postForm(endpoint: "detailkontainer_nip", fields: [("nipppf", nip)])
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr.map { c in
            InstruksiLorongItem(
                kodeTiket: cleanField(c, "kode_tiket", fallback: ""),
                noContainer: cleanField(c, "no_container", fallback: "-"),
                ukuranContainer: cleanField(c, "ukuran_container", fallback: "-"),
                noPib: cleanField(c, "no_pib", fallback: "-"),
                tglPib: cleanField(c, "tgl_pib", fallback: "-"),
                instruksiLorong: cleanField(c, "instruksi_lorong", fallback: "-"),
                pelaksanaanLorong: cleanField(c, "pelaksanaan_lorong", fallback: "0"),
                alasanLorong: cleanField(c, "alasan_lorong", fallback: "-"),
                teknikPeriksa: cleanField(c, "teknikperiksa", fallback: "-"),
                status: cleanField(c, "status", fallback: "-"),
                image: cleanField(c, "image", fallback: "")
            )
        }
    }

    func browsePibData(nip: String, noPib: String) async throws -> [PibDocument] {
        let (_, data, _) = try await postForm(endpoint: "browse_data", fields: [
            ("nipppf", nip),
            ("nopib", noPib)
        ])
        return parsePibArray(data)
    }

    func fetchDokumen(kodeTiket: String) async throws -> [String: String] {
        let (_, data, _) = try await postForm(endpoint: "get_dokumen", fields: [("kode_tiket", kodeTiket)])
        let jsonObj = try? JSONSerialization.jsonObject(with: data)
        var dict: [String: Any]?
        if let d = jsonObj as? [String: Any] {
            dict = d
        } else if let arr = jsonObj as? [[String: Any]], let first = arr.first {
            dict = first
        }
        guard let dict else { return [:] }
        var out: [String: String] = [:]
        for (k, _) in dict {
            let val = cleanField(dict, k, fallback: "")
            if !val.isEmpty && val != "-" {
                out[k] = val
            }
        }
        return out
    }

    func fetchContainers(kodeTiket: String) async throws -> [ContainerItem] {
        let (_, data, _) = try await postForm(endpoint: "get_container", fields: [("kode_tiket", kodeTiket)])
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr.map { c in
            ContainerItem(
                noContainer: cleanField(c, "no_container", fallback: "CONT"),
                ukuranContainer: cleanField(c, "ukuran_container", fallback: ""),
                instruksiLorong: cleanField(c, "instruksi_lorong", fallback: "-"),
                pelaksanaanLorong: cleanField(c, "pelaksanaan_lorong", fallback: "0"),
                alasanLorong: cleanField(c, "alasan_lorong", fallback: "-"),
                teknikPeriksa: cleanField(c, "teknikperiksa", fallback: "-")
            )
        }
    }

    func fetchImages(kodeTiket: String, nokon: String) async throws -> [OnlineImageItem] {
        let (_, data, _) = try await postForm(endpoint: "get_image", fields: [
            ("nomorkontainer", nokon),
            ("kode_tiket", kodeTiket)
        ])
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr.map { item in
            OnlineImageItem(
                id: cleanField(item, "id", fallback: ""),
                urlImage: cleanField(item, "url_image", fallback: ""),
                imageHttpUrl: cleanField(item, "image", fallback: ""),
                ketPraPemeriksaan: cleanField(item, "ket_pra_pemeriksaan", fallback: "Foto"),
                seriBarang: cleanField(item, "seri_barang", fallback: ""),
                ketSeriBarang: cleanField(item, "ket_seri_barang", fallback: "")
            )
        }
    }

    func insertImage(
        isLcl: Bool,
        kodeTiket: String,
        nokon: String,
        urlImage: String,
        stepLabel: String,
        seriBarang: String,
        ketSeriBarang: String,
        lokasi: String,
        ukuran: String,
        waktuFoto: String,
        uraianBarang: String,
        jumlahJenisKemasan: String,
        pelLorong: String = "0",
        alasanLorong: String = "-",
        teknikPeriksa: String = "-",
        satuanBarang: String = "",
        negaraAsal: String = "",
        spesifikasi: String = ""
    ) async throws -> String {
        if isLcl {
            let (_, _, raw) = try await postForm(endpoint: "insert_image_lcl", fields: [
                ("kode_tiket", kodeTiket),
                ("url_image", urlImage),
                ("ket_pra_pemeriksaan", stepLabel),
                ("seri_barang", seriBarang),
                ("ket_seri_barang", ketSeriBarang),
                ("lokasi", lokasi),
                ("ukuran", ukuran),
                ("waktu_foto", waktuFoto),
                ("status_hapus", "0"),
                ("status_online", "1"),
                ("jumlah_jenis_kemasan", jumlahJenisKemasan),
                ("uraian_barang", uraianBarang),
                ("satuan_barang", satuanBarang),
                ("negara_asal", negaraAsal),
                ("spesifikasi", spesifikasi)
            ])
            return raw
        } else {
            let (_, _, raw) = try await postForm(endpoint: "insert_image", fields: [
                ("kode_tiket", kodeTiket),
                ("nokon", nokon),
                ("url_image", urlImage),
                ("ket_pra_pemeriksaan", stepLabel),
                ("seri_barang", seriBarang),
                ("ket_seri_barang", ketSeriBarang),
                ("lokasi", lokasi),
                ("ukuran", ukuran),
                ("waktu_foto", waktuFoto),
                ("status_hapus", "0"),
                ("status_online", "1"),
                ("pel_lorong", pelLorong),
                ("alasan_lorong", alasanLorong),
                ("teknik_periksa", teknikPeriksa),
                ("jumlah_jenis_kemasan", jumlahJenisKemasan),
                ("uraian_barang", uraianBarang),
                ("satuan_barang", satuanBarang),
                ("negara_asal", negaraAsal),
                ("spesifikasi", spesifikasi)
            ])
            return raw
        }
    }

    func fetchNegaraAsal() async -> [String] {
        guard let (_, data, _) = try? await postForm(endpoint: "get_negara_asal", fields: []),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { dict in
            let v = cleanField(dict, "nama_negara_asal", fallback: "")
            return v.isEmpty ? nil : v
        }
    }

    func cekPelaksanaanLorong(kodeTiket: String, nokon: String) async -> String {
        guard let (_, _, raw) = try? await postForm(endpoint: "cek_pelaksanaan_instruksi_lorong", fields: [
            ("kode_tiket", kodeTiket),
            ("nomorkontainer", nokon)
        ]) else {
            return "0"
        }
        return raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
    }

    func fetchAlasanTidakLorong() async -> [String] {
        guard let (_, data, _) = try? await postForm(endpoint: "get_alasantidaklorong", fields: []),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { dict in
            let v = cleanField(dict, "alasantidaklorong", fallback: "")
            return v.isEmpty ? nil : v
        }
    }

    func fetchTeknikPeriksa() async -> [String] {
        guard let (_, data, _) = try? await postForm(endpoint: "get_teknikperiksa", fields: []),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { dict in
            let v = cleanField(dict, "teknikperiksa", fallback: "")
            return v.isEmpty ? nil : v
        }
    }

    func insertInstruksiLorong(
        kodeTiket: String,
        noPib: String,
        tglPib: String,
        nokon: String,
        instruksiLorong: String,
        lokasiPeriksa: String,
        ukuranKontainer: String,
        statusContainer: String,
        typeDevice: String = "iOS"
    ) async throws -> String {
        let (_, _, raw) = try await postForm(endpoint: "insert_instruksilorong", fields: [
            ("kode_tiket", kodeTiket),
            ("nopib", noPib),
            ("tanggalpib", tglPib),
            ("nomorkontainer", nokon),
            ("instruksilorong", instruksiLorong),
            ("lokasiperiksa", lokasiPeriksa),
            ("ukurankontainer", ukuranKontainer),
            ("status_container", statusContainer),
            ("typedevice", typeDevice)
        ])
        return raw
    }

    func deleteImage(imageId: String) async throws {
        _ = try await postForm(endpoint: "update_foto_hapus", fields: [
            ("status_hapus", "1"),
            ("id", imageId)
        ])
    }

    func insertDokManual(nip: String, noPib: String, tglPib: String) async throws {
        _ = try await postForm(endpoint: "insert_dok_manual", fields: [
            ("nipppf", nip),
            ("nopib", noPib),
            ("tglpib", tglPib)
        ])
    }

    func insertTtdPj(kodeTiket: String, namaPj: String, relUrl: String) async throws {
        _ = try await postForm(endpoint: "insert_ttd_pj", fields: [
            ("kode_tiket", kodeTiket),
            ("nama_pj", namaPj),
            ("url", relUrl)
        ])
    }

    func insertTtdPpf(nip: String) async throws {
        _ = try await postForm(endpoint: "insert_ttd_ppf", fields: [("nip", nip)])
    }

    func updateSelesaiPeriksa(kodeTiket: String) async throws {
        _ = try await postForm(endpoint: "update_status_selesai_periksa", fields: [("kode_tiket", kodeTiket)])
    }

    func updateBatalPeriksa(kodeTiket: String) async throws {
        _ = try await postForm(endpoint: "update_batal_periksa", fields: [("kode_tiket", kodeTiket)])
    }

    // MARK: - Diagnostics

    func pingEndpoint(_ urlStr: String) async -> (Bool, String) {
        guard let url = URL(string: urlStr) else { return (false, "URL tidak valid") }
        let start = Date()
        do {
            let (_, resp) = try await session.data(from: url)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (code > 0 && code < 500, "HTTP \(code) (\(ms) ms)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - SIAP 3.0 Pendok Browse, Lampiran Dokumen & Authenticated PDF Download

    private let desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    func absolutizeSiap3(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        while trimmed.hasPrefix("../") {
            trimmed = String(trimmed.dropFirst(3))
        }
        while trimmed.hasPrefix("./") {
            trimmed = String(trimmed.dropFirst(2))
        }
        let encoded = trimmed.replacingOccurrences(of: " ", with: "%20")
        if encoded.lowercased().hasPrefix("http://") || encoded.lowercased().hasPrefix("https://") {
            return encoded
        }
        if encoded.hasPrefix("/siap3.0") || encoded.hasPrefix("/slim3.0") || encoded.hasPrefix("/siap/") {
            return "https://bcpriok.net" + encoded
        }
        if encoded.hasPrefix("siap3.0/") || encoded.hasPrefix("slim3.0/") || encoded.hasPrefix("siap/") {
            return "https://bcpriok.net/" + encoded
        }
        if encoded.hasPrefix("/") {
            return SiapCrypto.siap3Base + encoded
        }
        return "\(SiapCrypto.siap3Base)/\(encoded)"
    }

    func invalidateSiap3Session() {
        siap3LoggedInUser = nil
        siap3LoggedInAt = .distantPast
    }

    private func isSiap3SessionExpired(response: URLResponse?, body: String) -> Bool {
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { return true }
            if let finalUrl = http.url?.absoluteString.lowercased(),
               finalUrl.contains("/auth/login") || finalUrl.hasSuffix("/login") {
                return true
            }
        }
        let low = body.lowercased()
        if low.contains("auth/login_action") || low.contains("id=\"form-login\"") || low.contains("login - siap") {
            return true
        }
        return false
    }

    private func attemptSingleSiap3Login(identity: String, password: String) async throws -> Bool {
        guard let loginPageUrl = URL(string: "\(SiapCrypto.siap3Base)/auth/login"),
              let loginPostUrl = URL(string: "\(SiapCrypto.siap3Base)/auth/login_action/") else {
            throw SiapApiError.invalidURL
        }
        var getReq = URLRequest(url: loginPageUrl)
        getReq.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        _ = try await siap3Session.data(for: getReq)

        var req = URLRequest(url: loginPostUrl)
        req.httpMethod = "POST"
        req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(loginPageUrl.absoluteString, forHTTPHeaderField: "Referer")
        req.httpBody = formEncode([
            ("identity", identity),
            ("password", password),
            ("remember", "Remember Me")
        ])

        let (data, _) = try await siap3Session.data(for: req)
        let body = String(data: data, encoding: .utf8) ?? ""
        var ok = body.lowercased().contains("\"success\":true") || body.lowercased().contains("redirect")
        if let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let success = dict["success"] as? Bool {
            ok = success
        }
        return ok
    }

    func ensureSiap3Login(username: String, password: String, fallbackEmail: String = "", force: Bool = false) async throws {
        let customUser = (UserDefaults.standard.string(forKey: "siapneo_siap3_user") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let customPass = UserDefaults.standard.string(forKey: "siapneo_siap3_pass") ?? ""
        let effectiveUser = customUser.isEmpty ? username.trimmingCharacters(in: .whitespacesAndNewlines) : customUser
        let effectivePass = customPass.isEmpty ? password : customPass

        if !force && siap3LoggedInUser == effectiveUser && Date().timeIntervalSince(siap3LoggedInAt) < 1200 {
            return
        }
        guard !effectiveUser.isEmpty && !effectivePass.isEmpty else {
            throw SiapApiError.message("Kredensial SIAP 3.0 belum tersedia. Atur di tab Akun.")
        }

        if try await attemptSingleSiap3Login(identity: effectiveUser, password: effectivePass) {
            siap3LoggedInUser = effectiveUser
            siap3LoggedInAt = Date()
            return
        }

        let alt = fallbackEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if customUser.isEmpty && !alt.isEmpty && alt.lowercased() != effectiveUser.lowercased() {
            if try await attemptSingleSiap3Login(identity: alt, password: effectivePass) {
                siap3LoggedInUser = effectiveUser
                siap3LoggedInAt = Date()
                return
            }
        }

        throw SiapApiError.message("Gagal login SIAP 3.0. Cek kredensial SIAP 3.0 di tab Akun.")
    }

    private func extractFirstMatch(pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group else { return nil }
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildDataTablesFields(start: Int, length: Int, search: String, columnCount: Int, orderable: Bool) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("draw", "1"),
            ("start", "\(start)"),
            ("length", "\(length)"),
            ("search[value]", search),
            ("search[regex]", "false")
        ]
        for i in 0..<columnCount {
            fields.append(("columns[\(i)][data]", "\(i)"))
            fields.append(("columns[\(i)][name]", ""))
            fields.append(("columns[\(i)][searchable]", "true"))
            fields.append(("columns[\(i)][orderable]", orderable ? "true" : "false"))
            fields.append(("columns[\(i)][search][value]", ""))
            fields.append(("columns[\(i)][search][regex]", "false"))
        }
        return fields
    }

    /// Exact port of Siap3WebClient.fetchPendokBrowseData
    func browsePendok(username: String, password: String, fallbackEmail: String = "", query: String, start: Int = 0, length: Int = 30) async throws -> [PendokBrowseItem] {
        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/pendok_mk/browse_data") else {
                throw SiapApiError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/pendok_mk", forHTTPHeaderField: "Referer")
            req.httpBody = formEncode(buildDataTablesFields(start: start, length: length, search: query, columnCount: 11, orderable: false))

            let (data, resp) = try await siap3Session.data(for: req)
            let body = String(data: data, encoding: .utf8) ?? ""
            if isSiap3SessionExpired(response: resp, body: body) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                throw SiapApiError.message("Sesi SIAP 3.0 berakhir. Silakan coba lagi.")
            }

            guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return []
            }
            let rawRows = (dict["data"] as? [[Any]]) ?? (dict["aaData"] as? [[Any]]) ?? []
            return rawRows.compactMap { row -> PendokBrowseItem? in
                guard row.count >= 2 else { return nil }
                func rawCol(_ idx: Int) -> String { idx < row.count ? String(describing: row[idx]) : "" }
                func col(_ idx: Int) -> String { stripHtml(rawCol(idx)) }

                let col0 = col(0)
                let col1 = col(1)
                let col2 = col(2)
                let col3 = col(3)
                let col4 = col(4)
                let col5 = col(5)
                let col6 = col(6)
                let col7 = col(7)
                let col8 = col(8)
                let col9 = col(9)
                let lastRaw = rawCol(row.count - 1)

                let actionId = extractFirstMatch(pattern: #"\bclass=["'][^"']*\bhistory\b[^"']*["'][^>]*\bdata(?:-id)?=["']([^"']+)["']"#, in: lastRaw)
                    ?? extractFirstMatch(pattern: #"\bdata(?:-id)?=["']([^"']+)["'][^>]*\bclass=["'][^"']*\bhistory\b"#, in: lastRaw)
                    ?? extractFirstMatch(pattern: #"\bdata(?:-id)?=["']([^"']+)["']"#, in: lastRaw)
                    ?? col0

                let col2LooksLikeDate = extractFirstMatch(pattern: #"(\d{2}[-/.]\d{2}[-/.]\d{4}|\d{4}[-/.]\d{2}[-/.]\d{2})"#, in: col2) != nil
                let noPib: String
                let tglPib: String
                if col2LooksLikeDate {
                    let digits = col1.filter(\.isNumber)
                    noPib = digits.isEmpty ? col1 : digits
                    tglPib = col2
                } else {
                    let parts = col1.components(separatedBy: CharacterSet(charactersIn: " /\n\t")).filter { !$0.isEmpty }
                    let firstDigits = (parts.first ?? "").filter(\.isNumber)
                    noPib = firstDigits.isEmpty ? col1 : firstDigits
                    tglPib = parts.count > 1 ? parts[1] : col2
                }

                let importir = col2LooksLikeDate ? col3 : col2
                let jalur = col2LooksLikeDate ? col6 : col3
                let rawStatus = (!col2LooksLikeDate && col7.isEmpty) ? col5 : col7
                let lowStatus = rawStatus.lowercased()
                let isDitolak = lowStatus.contains("tolak") || lowStatus.contains("reject") || lowStatus.contains("kembali") || lowStatus.contains("batal")
                let statusText = rawStatus.isEmpty ? (isDitolak ? "DITOLAK" : "DIPROSES") : rawStatus

                return PendokBrowseItem(
                    rowId: col0,
                    noPib: noPib,
                    tglPib: tglPib,
                    noAju: col0,
                    namaImportir: importir,
                    npwpImportir: col4,
                    pfpd: col5,
                    jalur: jalur,
                    status: statusText,
                    isDitolak: isDitolak,
                    waktuStatus: "",
                    alasanPenolakan: isDitolak ? rawStatus : "",
                    disdok: col8,
                    coo: col9,
                    actionId: actionId,
                    riwayatTerakhir: rawStatus.isEmpty ? col6 : rawStatus
                )
            }
        }
        return []
    }

    /// Exact port of Siap3WebClient.fetchPendokAttachments (POST /pendok_mk/get_jenis_dokumen)
    func fetchPendokAttachments(username: String, password: String, fallbackEmail: String = "", kodePelayanan: String) async throws -> [PendokDocumentAttachment] {
        let cleanKode = kodePelayanan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKode.isEmpty else { return [] }

        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/pendok_mk/get_jenis_dokumen") else {
                throw SiapApiError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/pendok_mk", forHTTPHeaderField: "Referer")
            req.httpBody = formEncode([("kode_pelayanan", cleanKode)])

            let (data, resp) = try await siap3Session.data(for: req)
            let body = String(data: data, encoding: .utf8) ?? ""
            if isSiap3SessionExpired(response: resp, body: body) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                throw SiapApiError.message("Sesi SIAP 3.0 berakhir.")
            }

            let parsed = try? JSONSerialization.jsonObject(with: data)
            var arr: [[String: Any]] = []
            if let direct = parsed as? [[String: Any]] {
                arr = direct
            } else if let obj = parsed as? [String: Any] {
                arr = (obj["data"] as? [[String: Any]]) ?? (obj["rows"] as? [[String: Any]]) ?? []
            }

            var out: [PendokDocumentAttachment] = []
            for (idx, item) in arr.enumerated() {
                var path = ""
                for key in ["file_path", "link", "url", "file", "dokumen", "path"] {
                    let cand = cleanField(item, key, fallback: "")
                    if !cand.isEmpty && cand != "-" {
                        path = cand
                        break
                    }
                }
                guard !path.isEmpty else { continue }

                var nama = cleanField(item, "nama_dokumen", fallback: "")
                if nama.isEmpty { nama = cleanField(item, "keterangan", fallback: "") }
                let jenis = cleanField(item, "jenis_dokumen", fallback: nama.isEmpty ? "Dokumen" : nama)
                if nama.isEmpty { nama = jenis }
                let tgl = cleanField(item, "tgl_upload", fallback: "")
                let rawId = cleanField(item, "id", fallback: "\(idx)")

                out.append(PendokDocumentAttachment(
                    rawId: rawId,
                    kodePelayanan: cleanKode,
                    jenisDokumen: jenis,
                    namaDokumen: nama,
                    fileUrl: absolutizeSiap3(path),
                    tglUpload: tgl
                ))
            }
            return out
        }
        return []
    }

    /// Searches SIAP 3.0 pendok_mk across multiple PIB query variants (raw, zero-stripped, 6-digit zero-padded, optional importir)
    func searchPendokFlexible(username: String, password: String, fallbackEmail: String = "", noPib: String, importirHint: String = "") async throws -> [PendokBrowseItem] {
        let digits = noPib.filter(\.isNumber)
        let normTarget = String(digits.drop(while: { $0 == "0" }))
        var variants: [String] = []
        if !digits.isEmpty { variants.append(digits) }
        if !normTarget.isEmpty && !variants.contains(normTarget) { variants.append(normTarget) }
        if !normTarget.isEmpty && normTarget.count < 6 {
            let padded = String(repeating: "0", count: 6 - normTarget.count) + normTarget
            if !variants.contains(padded) { variants.append(padded) }
        }
        let cleanImp = importirHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if variants.isEmpty && !cleanImp.isEmpty {
            variants.append(cleanImp)
        }

        for q in variants {
            let items = try await browsePendok(username: username, password: password, fallbackEmail: fallbackEmail, query: q, start: 0, length: 25)
            if !items.isEmpty {
                // Sort exact PIB matches first
                return items.sorted { a, b in
                    let ad = String(a.noPib.filter(\.isNumber).drop(while: { $0 == "0" }))
                    let bd = String(b.noPib.filter(\.isNumber).drop(while: { $0 == "0" }))
                    let am = !normTarget.isEmpty && ad == normTarget
                    let bm = !normTarget.isEmpty && bd == normTarget
                    if am != bm { return am }
                    return false
                }
            }
        }
        // Final fallback: search by importir name and filter by PIB if possible
        if !cleanImp.isEmpty && !variants.contains(cleanImp) {
            let items = try await browsePendok(username: username, password: password, fallbackEmail: fallbackEmail, query: cleanImp, start: 0, length: 25)
            if !items.isEmpty {
                let exact = items.filter {
                    let nd = String($0.noPib.filter(\.isNumber).drop(while: { $0 == "0" }))
                    return !normTarget.isEmpty && nd == normTarget
                }
                return exact.isEmpty ? items : exact
            }
        }
        return []
    }

    /// Searches SIAP 3.0 pendok_mk by PIB number and returns all document attachments (PIB, INV, PL, B/L, COO, etc.)
    func fetchAttachmentsForPib(username: String, password: String, fallbackEmail: String = "", noPib: String, importirHint: String = "") async throws -> [PendokDocumentAttachment] {
        let items = try await searchPendokFlexible(username: username, password: password, fallbackEmail: fallbackEmail, noPib: noPib, importirHint: importirHint)
        guard let first = items.first, !first.actionId.isEmpty else { return [] }
        return try await fetchPendokAttachments(username: username, password: password, fallbackEmail: fallbackEmail, kodePelayanan: first.actionId)
    }

    /// Checks latest update manifest (unlimited CDN) with fallback to GitHub Releases API
    func checkLatestReleaseUpdate() async -> AppUpdateInfo? {
        let ts = Int(Date().timeIntervalSince1970)
        // 1. Primary: direct CDN update-manifest.json (zero API rate-limit, rich changelog)
        if let manifestUrl = URL(string: "https://github.com/rianpermana7io/SiapNEO/releases/download/latest/update-manifest.json?_t=\(ts)") {
            var mReq = URLRequest(url: manifestUrl)
            mReq.setValue("SIAPNeo-iOS-Updater", forHTTPHeaderField: "User-Agent")
            mReq.cachePolicy = .reloadIgnoringLocalCacheData
            mReq.timeoutInterval = 12
            if let (data, resp) = try? await session.data(for: mReq),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let ver = (dict["version"] as? String) ?? ""
                let build = (dict["build"] as? Int) ?? Int((dict["build"] as? String) ?? "0") ?? 0
                let ipaUrl = (dict["ipa_url"] as? String) ?? "https://github.com/rianpermana7io/SiapNEO/releases/download/latest/SIAPNeo-iOS.ipa"
                let sizeBytes = (dict["ipa_size_bytes"] as? Int) ?? 0
                let publishedAt = (dict["published_at"] as? String) ?? ""
                let notes = (dict["changelog"] as? String) ?? (dict["notes"] as? String) ?? ""
                let mandatory = (dict["mandatory"] as? Bool) ?? false
                if !ver.isEmpty || build > 0 {
                    return AppUpdateInfo(
                        remoteVersion: ver,
                        remoteBuild: build,
                        ipaDownloadUrl: ipaUrl,
                        ipaSizeBytes: sizeBytes,
                        publishedAt: publishedAt,
                        notes: notes,
                        mandatory: mandatory
                    )
                }
            }
        }

        // 2. Fallback: GitHub Releases API (same pattern as Android AppUpdater)
        guard let url = URL(string: "https://api.github.com/repos/rianpermana7io/SiapNEO/releases/tags/latest") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("SIAPNeo-iOS-Updater", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 12
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let title = (dict["name"] as? String) ?? ""
        let body = (dict["body"] as? String) ?? ""
        let publishedAt = (dict["published_at"] as? String) ?? ""
        let combined = "\(title) \(body)"
        let remoteVer = extractFirstMatch(pattern: #"v?(\d+\.\d+\.\d+)"#, in: combined) ?? ""
        let remoteBuildStr = extractFirstMatch(pattern: #"(?:BUILD=|\()(\d+)"#, in: combined) ?? "0"
        let remoteBuild = Int(remoteBuildStr) ?? 0
        var ipaUrl = "https://github.com/rianpermana7io/SiapNEO/releases/download/latest/SIAPNeo-iOS.ipa"
        var ipaSize = 0
        if let assets = dict["assets"] as? [[String: Any]],
           let ipaAsset = assets.first(where: { (($0["name"] as? String) ?? "").lowercased().hasSuffix(".ipa") }) {
            if let dl = ipaAsset["browser_download_url"] as? String, !dl.isEmpty {
                ipaUrl = dl
            }
            ipaSize = (ipaAsset["size"] as? Int) ?? 0
        }
        guard !remoteVer.isEmpty || remoteBuild > 0 else { return nil }
        return AppUpdateInfo(
            remoteVersion: remoteVer,
            remoteBuild: remoteBuild,
            ipaDownloadUrl: ipaUrl,
            ipaSizeBytes: ipaSize,
            publishedAt: publishedAt,
            notes: body,
            mandatory: body.uppercased().contains("[MANDATORY]") || body.uppercased().contains("[WAJIB]")
        )
    }

    func isVersionNewer(remoteVersion: String, remoteBuild: Int, localVersion: String, localBuild: Int) -> Bool {
        if remoteBuild > localBuild { return true }
        let rParts = remoteVersion.split(separator: ".").compactMap { Int($0) }
        let lParts = localVersion.split(separator: ".").compactMap { Int($0) }
        let count = max(rParts.count, lParts.count)
        for i in 0..<count {
            let rv = i < rParts.count ? rParts[i] : 0
            let lv = i < lParts.count ? lParts[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    /// Helper to turn dd-MM-yyyy or yyyy-MM-dd (with optional HH:mm:ss) into lexicographically sortable ISO timestamp
    func toSortableTimestamp(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty && s != "-" else { return "" }
        let parts = s.split(separator: " ", maxSplits: 1)
        let datePart = String(parts[0])
        let timePart = parts.count > 1 ? String(parts[1]) : "00:00:00"
        let comps = datePart.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." })
        if comps.count == 3 {
            if comps[0].count == 4 {
                return "\(comps[0])-\(comps[1])-\(comps[2]) \(timePart)"
            } else if comps[2].count == 4 {
                return "\(comps[2])-\(comps[1])-\(comps[0]) \(timePart)"
            }
        }
        return s
    }

    /// Exact port of Siap3WebClient.fetchBrowsePage (POST /siapfb_pemeriksa/browse_data) — returns AssignedIpItem sorted newest-first
    func fetchAssignedIpList(
        username: String,
        password: String,
        fallbackEmail: String = "",
        start: Int = 0,
        length: Int = 25,
        query: String = ""
    ) async throws -> (items: [AssignedIpItem], totalRecords: Int) {
        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/browse_data") else {
                throw SiapApiError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")
            req.httpBody = formEncode(buildDataTablesFields(start: start, length: length, search: query, columnCount: 9, orderable: true))

            let (data, resp) = try await siap3Session.data(for: req)
            let body = String(data: data, encoding: .utf8) ?? ""
            if isSiap3SessionExpired(response: resp, body: body) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                throw SiapApiError.message("Sesi SIAP 3.0 berakhir. Silakan coba lagi.")
            }

            guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return ([], 0)
            }
            let total = (dict["recordsFiltered"] as? Int) ?? (dict["recordsTotal"] as? Int) ?? 0
            let rawRows = (dict["data"] as? [[Any]]) ?? (dict["aaData"] as? [[Any]]) ?? []

            var parsed: [AssignedIpItem] = rawRows.compactMap { row -> AssignedIpItem? in
                guard row.count >= 5 else { return nil }
                func rawCol(_ idx: Int) -> String { idx < row.count ? String(describing: row[idx]) : "" }
                func col(_ idx: Int) -> String { stripHtml(rawCol(idx)) }

                let kodeTiket = col(0)
                let importir = col(1).isEmpty ? "-" : col(1)
                var noPib = col(2)
                if let slashIdx = noPib.firstIndex(of: "/") {
                    noPib = String(noPib[..<slashIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let tglPib = col(3).isEmpty ? "-" : col(3)
                let col4 = col(4)
                let jenisKontainer = col4.uppercased().contains("LCL") ? "LCL" : "FCL"
                let jumlahKontainer = col4.isEmpty ? "1 Cont" : col4
                let tps = col(5).isEmpty ? "-" : col(5)
                let waktuIp = col(6).isEmpty ? "-" : col(6)
                let rawStatusCol = rawCol(7)
                var statusText = stripHtml(rawStatusCol)
                if statusText.isEmpty { statusText = "BELUM PERIKSA" }

                let actionHtml = rawCol(8)
                let hashId = extractFirstMatch(pattern: #"(?:bapp_new_ekspor|cetak_bap|foto_detail|detail)/([A-Za-z0-9+/=_-]+?)(?=["'?#&\s<]|$)"#, in: actionHtml)
                    ?? extractFirstMatch(pattern: #"data(?:-id)?=["']([^"']+)["']"#, in: actionHtml)
                    ?? ""

                let isSudahBap = statusText.lowercased().contains("sudah bap")
                    || statusText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "bap"
                    || actionHtml.lowercased().contains("cetak_bap")

                // Extract all href links from col 8
                var hrefs: [String] = []
                if let hrefRegex = try? NSRegularExpression(pattern: #"href=["']([^"']+)["']"#, options: [.caseInsensitive]) {
                    let nsAct = actionHtml as NSString
                    for m in hrefRegex.matches(in: actionHtml, range: NSRange(location: 0, length: nsAct.length)) {
                        let u = nsAct.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !u.isEmpty && !u.hasPrefix("#") && !u.lowercased().hasPrefix("javascript") {
                            hrefs.append(u)
                        }
                    }
                }

                let cetakHref = hrefs.first(where: { $0.lowercased().contains("cetak") })
                let buatHref = hrefs.first(where: { $0.lowercased().contains("bap") && !$0.lowercased().contains("cetak") })

                let linkCetakBap: String
                if isSudahBap {
                    if let ch = cetakHref {
                        linkCetakBap = absolutizeSiap3(ch)
                    } else if !hashId.isEmpty {
                        linkCetakBap = "https://bcpriok.net/slim3.0/penerimaan_dokumen_merah_kuning/cetak_bap/\(hashId)"
                    } else {
                        linkCetakBap = ""
                    }
                } else {
                    linkCetakBap = ""
                }

                let linkBuatBap: String
                if !isSudahBap {
                    if let bh = buatHref {
                        linkBuatBap = absolutizeSiap3(bh)
                    } else if !hashId.isEmpty {
                        linkBuatBap = "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/bapp_new_ekspor/\(hashId)"
                    } else {
                        linkBuatBap = ""
                    }
                } else {
                    linkBuatBap = ""
                }

                return AssignedIpItem(
                    kodeTiket: kodeTiket,
                    noPib: noPib,
                    tglPib: tglPib,
                    importir: importir,
                    jenisDokumen: "PIB",
                    jenisKontainer: jenisKontainer,
                    jumlahKontainer: jumlahKontainer,
                    tps: tps,
                    waktuIp: waktuIp,
                    status: isSudahBap ? "SUDAH BAP" : statusText,
                    namaPj: "-",
                    hpPj: "-",
                    namaPfpd: "-",
                    hpPfpd: "-",
                    atensi: "-",
                    hashId: hashId,
                    linkCetakBap: linkCetakBap,
                    linkBuatBap: linkBuatBap
                )
            }

            // Sort newest documents first (by waktuIp, fallback tglPib)
            parsed.sort { a, b in
                let ka = toSortableTimestamp(a.waktuIp)
                let kb = toSortableTimestamp(b.waktuIp)
                if ka != kb { return ka > kb }
                let ta = toSortableTimestamp(a.tglPib)
                let tb = toSortableTimestamp(b.tglPib)
                if ta != tb { return ta > tb }
                return a.noPib > b.noPib
            }

            return (parsed, total)
        }
        return ([], 0)
    }

    /// Searches SIAP 3.0 siapfb_pemeriksa/browse_data to find cetak_bap URL for a PIB
    func fetchBapUrlForPib(username: String, password: String, fallbackEmail: String = "", noPib: String) async throws -> String? {
        let digits = noPib.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/browse_data") else {
                throw SiapApiError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")
            req.httpBody = formEncode(buildDataTablesFields(start: 0, length: 25, search: digits, columnCount: 9, orderable: true))

            let (data, resp) = try await siap3Session.data(for: req)
            let body = String(data: data, encoding: .utf8) ?? ""
            if isSiap3SessionExpired(response: resp, body: body) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                return nil
            }
            guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            let rows = (dict["data"] as? [[Any]]) ?? (dict["aaData"] as? [[Any]]) ?? []
            for row in rows {
                let joined = row.map { String(describing: $0) }.joined(separator: " ")
                if let hash = extractFirstMatch(pattern: #"(?:cetak_bap)/([A-Za-z0-9+/=_-]+?)(?=["'?#&\s<]|$)"#, in: joined) {
                    return "https://bcpriok.net/slim3.0/penerimaan_dokumen_merah_kuning/cetak_bap/\(hash)"
                }
            }
            return nil
        }
        return nil
    }

    // MARK: - Redist & Hold (1:1 Port of Android Siap3WebClient)

    private func extractDataTablesRows(from rawJson: String) -> [[String]] {
        let trimmed = rawJson.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let rawList: [Any]
        if let arr = obj as? [Any] {
            rawList = arr
        } else if let dict = obj as? [String: Any] {
            rawList = (dict["data"] as? [Any]) ?? (dict["aaData"] as? [Any]) ?? []
        } else {
            return []
        }
        var out: [[String]] = []
        for entry in rawList {
            if let arr = entry as? [Any] {
                out.append(arr.map { stripHtml(String(describing: $0)) })
            } else if let dict = entry as? [String: Any] {
                var row: [String] = []
                for idx in 0..<10 {
                    if let val = dict[String(idx)] {
                        row.append(stripHtml(String(describing: val)))
                    }
                }
                if !row.isEmpty { out.append(row) }
            }
        }
        return out
    }

    private func parseHtmlSelectOptions(html: String, selectName: String) -> [SiapSelectOption] {
        let selectPattern = "<select[^>]+name=[\"']\(NSRegularExpression.escapedPattern(for: selectName))[\"'][^>]*>(.*?)</select>"
        guard let selRegex = try? NSRegularExpression(pattern: selectPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let optRegex = try? NSRegularExpression(pattern: "<option\\b([^>]*)>(.*?)</option>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let valRegex = try? NSRegularExpression(pattern: "\\bvalue\\s*=\\s*[\"']([^\"']*)[\"']", options: [.caseInsensitive]) else {
            return []
        }
        let nsHtml = html as NSString
        guard let selMatch = selRegex.firstMatch(in: html, range: NSRange(location: 0, length: nsHtml.length)) else {
            return []
        }
        let inner = nsHtml.substring(with: selMatch.range(at: 1))
        let nsInner = inner as NSString
        var out: [SiapSelectOption] = []
        for m in optRegex.matches(in: inner, range: NSRange(location: 0, length: nsInner.length)) {
            let attrs = nsInner.substring(with: m.range(at: 1))
            let label = stripHtml(nsInner.substring(with: m.range(at: 2)))
            var val = label
            let nsAttrs = attrs as NSString
            if let vm = valRegex.firstMatch(in: attrs, range: NSRange(location: 0, length: nsAttrs.length)) {
                val = nsAttrs.substring(with: vm.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if val.isEmpty || label.isEmpty || label.caseInsensitiveCompare("Pilih") == .orderedSame {
                continue
            }
            out.append(SiapSelectOption(value: val, label: label))
        }
        return out
    }

    private func buildMultipartBody(
        boundary: String,
        fields: [(String, String)],
        fileField: (name: String, filename: String, mimeType: String, data: Data)? = nil
    ) -> Data {
        var body = Data()
        for (k, v) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".utf8))
            body.append(Data("\(v)\r\n".utf8))
        }
        if let file = fileField {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n".utf8))
            body.append(Data("Content-Type: \(file.mimeType)\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    func fetchRedistHistory(username: String, password: String, fallbackEmail: String = "") async throws -> [RedistHistoryItem] {
        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/get_redist_ppf") else {
                throw SiapApiError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")

            let (data, resp) = try await siap3Session.data(for: req)
            let body = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isSiap3SessionExpired(response: resp, body: body) || (!body.isEmpty && !body.hasPrefix("{") && !body.hasPrefix("[")) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                throw SiapApiError.message("Sesi SIAP 3.0 berakhir atau respons Redist tidak dikenali.")
            }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SiapApiError.httpError(http.statusCode, "Gagal mengambil daftar Redist")
            }
            let rows = extractDataTablesRows(from: body)
            var items: [RedistHistoryItem] = rows.compactMap { cols in
                guard cols.count >= 9 else { return nil }
                return RedistHistoryItem(
                    kodeTiket: cols[0],
                    importir: cols[1],
                    noPib: cols[2],
                    tglPib: cols[3],
                    tps: cols[4],
                    cluster: cols[5],
                    alasan: cols[6],
                    tanggalPengajuan: cols[7],
                    status: cols[8]
                )
            }
            items.sort { a, b in
                let ta = toSortableTimestamp(a.tanggalPengajuan)
                let tb = toSortableTimestamp(b.tanggalPengajuan)
                if ta != tb { return ta > tb }
                return a.kodeTiket > b.kodeTiket
            }
            return items
        }
        return []
    }

    func fetchHoldHistory(username: String, password: String, fallbackEmail: String = "") async throws -> [HoldHistoryItem] {
        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/get_izin_ppf") else {
                throw SiapApiError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")

            let (data, resp) = try await siap3Session.data(for: req)
            let body = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isSiap3SessionExpired(response: resp, body: body) || (!body.isEmpty && !body.hasPrefix("{") && !body.hasPrefix("[")) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                throw SiapApiError.message("Sesi SIAP 3.0 berakhir atau respons Hold tidak dikenali.")
            }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SiapApiError.httpError(http.statusCode, "Gagal mengambil daftar Hold")
            }
            let rows = extractDataTablesRows(from: body)
            var items: [HoldHistoryItem] = rows.compactMap { cols in
                guard cols.count >= 6 else { return nil }
                return HoldHistoryItem(
                    tanggalPengajuan: cols[0],
                    cluster: cols[1],
                    alasan: cols[2],
                    waktuMulai: cols[3],
                    waktuSelesai: cols[4],
                    status: cols[5]
                )
            }
            items.sort { a, b in
                let ta = toSortableTimestamp(a.tanggalPengajuan)
                let tb = toSortableTimestamp(b.tanggalPengajuan)
                if ta != tb { return ta > tb }
                return toSortableTimestamp(a.waktuMulai) > toSortableTimestamp(b.waktuMulai)
            }
            return items
        }
        return []
    }

    func loadRedistFormSchema(username: String, password: String, fallbackEmail: String = "") async -> RedistHoldFormSchema {
        do {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: false)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/form_permohonan_redist") else {
                return RedistHoldFormSchema(clusters: RedistHoldFormSchema.defaultClusters, alasanOptions: RedistHoldFormSchema.defaultRedistAlasan)
            }
            var req = URLRequest(url: url)
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")
            let (data, resp) = try await siap3Session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty,
               let html = String(data: data, encoding: .utf8) {
                let clusters = parseHtmlSelectOptions(html: html, selectName: "cluster")
                let alasan = parseHtmlSelectOptions(html: html, selectName: "alasan")
                return RedistHoldFormSchema(
                    clusters: clusters.isEmpty ? RedistHoldFormSchema.defaultClusters : clusters,
                    alasanOptions: alasan.isEmpty ? RedistHoldFormSchema.defaultRedistAlasan : alasan
                )
            }
        } catch {}
        return RedistHoldFormSchema(clusters: RedistHoldFormSchema.defaultClusters, alasanOptions: RedistHoldFormSchema.defaultRedistAlasan)
    }

    func loadHoldFormSchema(username: String, password: String, fallbackEmail: String = "") async -> RedistHoldFormSchema {
        do {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: false)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/form_permohonan_hold") else {
                return RedistHoldFormSchema(clusters: RedistHoldFormSchema.defaultClusters, alasanOptions: RedistHoldFormSchema.defaultHoldAlasan)
            }
            var req = URLRequest(url: url)
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")
            let (data, resp) = try await siap3Session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty,
               let html = String(data: data, encoding: .utf8) {
                let clusters = parseHtmlSelectOptions(html: html, selectName: "cluster")
                let alasan = parseHtmlSelectOptions(html: html, selectName: "alasan")
                return RedistHoldFormSchema(
                    clusters: clusters.isEmpty ? RedistHoldFormSchema.defaultClusters : clusters,
                    alasanOptions: alasan.isEmpty ? RedistHoldFormSchema.defaultHoldAlasan : alasan
                )
            }
        } catch {}
        return RedistHoldFormSchema(clusters: RedistHoldFormSchema.defaultClusters, alasanOptions: RedistHoldFormSchema.defaultHoldAlasan)
    }

    func submitRedist(
        username: String,
        password: String,
        fallbackEmail: String = "",
        kodeTiket: String,
        cluster: String,
        alasan: String,
        keterangan: String,
        imageData: Data,
        filename: String = "lampiran_redist.jpg"
    ) async throws -> String {
        guard !imageData.isEmpty else {
            throw SiapApiError.message("Lampiran foto permohonan Redist wajib dipilih.")
        }
        guard imageData.count <= 10 * 1024 * 1024 else {
            throw SiapApiError.message("Ukuran file tidak boleh lebih dari 10 MB.")
        }
        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/simpan_redist") else {
                throw SiapApiError.invalidURL
            }
            let boundary = "Boundary-\(UUID().uuidString)"
            let bodyData = buildMultipartBody(
                boundary: boundary,
                fields: [
                    ("kode_tiket", kodeTiket.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("cluster", cluster.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("alasan", alasan.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("keterangan", keterangan.trimmingCharacters(in: .whitespacesAndNewlines))
                ],
                fileField: ("FileUpload", filename, "image/jpeg", imageData)
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 90
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")
            req.setValue("https://bcpriok.net", forHTTPHeaderField: "Origin")
            req.httpBody = bodyData

            let (data, resp) = try await siap3Session.data(for: req)
            let body = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isSiap3SessionExpired(response: resp, body: body) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                throw SiapApiError.message("Sesi SIAP 3.0 berakhir, silakan coba kirim ulang.")
            }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SiapApiError.httpError(http.statusCode, "Gagal mengirim permohonan Redist")
            }
            if body.range(of: "SUCCESS", options: .caseInsensitive) != nil {
                return "Data Berhasil Disimpan"
            }
            let clean = stripHtml(body)
            throw SiapApiError.message(clean.isEmpty ? "Permohonan Redist gagal disimpan." : clean)
        }
        throw SiapApiError.message("Gagal mengirim permohonan Redist.")
    }

    func submitHold(
        username: String,
        password: String,
        fallbackEmail: String = "",
        cluster: String,
        alasan: String,
        keterangan: String,
        tanggal: String,
        wkMulai: String,
        wkSelesai: String
    ) async throws -> String {
        for attempt in 0..<2 {
            try await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            guard let url = URL(string: "\(SiapCrypto.siap3Base)/siapfb_pemeriksa/simpan_hold") else {
                throw SiapApiError.invalidURL
            }
            let boundary = "Boundary-\(UUID().uuidString)"
            let bodyData = buildMultipartBody(
                boundary: boundary,
                fields: [
                    ("cluster", cluster.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("alasan", alasan.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("keterangan", keterangan.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("tanggal", tanggal.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("wk_mulai", wkMulai.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ("wk_selesai", wkSelesai.trimmingCharacters(in: .whitespacesAndNewlines))
                ]
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 45
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("\(SiapCrypto.siap3Base)/home", forHTTPHeaderField: "Referer")
            req.setValue("https://bcpriok.net", forHTTPHeaderField: "Origin")
            req.httpBody = bodyData

            let (data, resp) = try await siap3Session.data(for: req)
            let body = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isSiap3SessionExpired(response: resp, body: body) {
                invalidateSiap3Session()
                if attempt == 0 { continue }
                throw SiapApiError.message("Sesi SIAP 3.0 berakhir, silakan coba kirim ulang.")
            }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SiapApiError.httpError(http.statusCode, "Gagal mengirim permohonan Hold")
            }
            if body.range(of: "SUCCESS", options: .caseInsensitive) != nil {
                return "Data Berhasil Disimpan"
            }
            let clean = stripHtml(body)
            throw SiapApiError.message(clean.isEmpty ? "Permohonan Hold gagal disimpan." : clean)
        }
        throw SiapApiError.message("Gagal mengirim permohonan Hold.")
    }

    struct DownloadedDocument {
        let localURL: URL
        let isPDF: Bool
        let isImage: Bool
    }

    /// Exact port of Siap3WebClient.downloadAttachmentFile — downloads PDF/Image using authenticated permissive-TLS session
    func downloadDocumentFile(urlStr: String, username: String, password: String, fallbackEmail: String = "") async throws -> DownloadedDocument {
        let absUrlStr = absolutizeSiap3(urlStr)
        guard let url = URL(string: absUrlStr) else {
            throw SiapApiError.invalidURL
        }
        let needsSiap3Auth = absUrlStr.lowercased().contains("bcpriok.net/siap3.0") || absUrlStr.lowercased().contains("bcpriok.net/slim3.0")

        for attempt in 0..<2 {
            if needsSiap3Auth || attempt > 0 {
                try? await ensureSiap3Login(username: username, password: password, fallbackEmail: fallbackEmail, force: attempt > 0)
            }
            var req = URLRequest(url: url)
            req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("\(SiapCrypto.siap3Base)/pendok_mk", forHTTPHeaderField: "Referer")

            let (data, resp) = try await siap3Session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if (http.statusCode == 401 || http.statusCode == 403) && attempt == 0 {
                    invalidateSiap3Session()
                    continue
                }
                throw SiapApiError.httpError(http.statusCode, "Gagal mengunduh dokumen")
            }
            guard data.count >= 30 else {
                throw SiapApiError.message("File dokumen kosong atau tidak ditemukan di server.")
            }

            let headStr = String(data: data.prefix(512), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let contentType = ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let looksHtml = contentType.contains("text/html") || headStr.hasPrefix("<!doctype html") || headStr.hasPrefix("<html") || headStr.contains("id=\"form-login\"")
            if looksHtml {
                if attempt == 0 {
                    invalidateSiap3Session()
                    continue
                }
                throw SiapApiError.message("Server mengembalikan halaman login HTML (cek kredensial SIAP 3.0 di tab Akun).")
            }

            let isPdf = data.prefix(5) == Data("%PDF-".utf8) || contentType.contains("pdf") || absUrlStr.lowercased().contains(".pdf")
            let isPng = data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])
            let isJpg = data.prefix(2) == Data([0xFF, 0xD8])
            let isImage = isPng || isJpg || contentType.contains("image/")

            let ext = isPdf ? "pdf" : (isPng ? "png" : (isJpg ? "jpg" : "pdf"))
            let fileName = "siap_doc_\(Int(Date().timeIntervalSince1970))_\(UInt(bitPattern: absUrlStr.hashValue)).\(ext)"
            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: localURL, options: .atomic)
            return DownloadedDocument(localURL: localURL, isPDF: isPdf, isImage: isImage)
        }
        throw SiapApiError.message("Gagal mengunduh dokumen.")
    }

    // MARK: - TPS Monitoring

    func fetchTps(source: TpsSource, myPibs: Set<String>, myContainers: Set<String>) async throws -> [TpsMonitorItem] {
        let baseUrl: String
        switch source {
        case .graha: baseUrl = "http://103.130.242.88/tpft/MON_SIAP_PERIKSA/"
        case .npct:  baseUrl = "https://bos.multiterminal.co.id/tpk_ipc/cgis/application.php/display/list_antrian"
        case .tpsl:  baseUrl = "https://bcpriok.net/siap3.0/antrian_pkb"
        }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "\(baseUrl)?_t=\(ts)") else { throw SiapApiError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        let targetSession = (source == .tpsl) ? siap3Session : session
        let (data, _) = try await targetSession.data(for: req)
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return parseHtmlTableRows(html: html, source: source.rawValue, myPibs: myPibs, myContainers: myContainers)
    }

    private func stripHtml(_ raw: String) -> String {
        let noTags = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = noTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return decoded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseHtmlTableRows(html: String, source: String, myPibs: Set<String>, myContainers: Set<String>) -> [TpsMonitorItem] {
        guard let trRegex = try? NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let tdRegex = try? NSRegularExpression(pattern: "<td[^>]*>(.*?)</td>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let thRegex = try? NSRegularExpression(pattern: "<th[^>]*>(.*?)</th>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let contRegex = try? NSRegularExpression(pattern: "\\b([A-Z]{4}\\d{7})\\b"),
              let exactPibCellRegex = try? NSRegularExpression(pattern: "^0*\\d{5,6}$"),
              let dateTimeRegex = try? NSRegularExpression(pattern: "\\b\\d{2,4}[-/.]\\d{2}[-/.]\\d{2,4}\\b|\\b\\d{2}:\\d{2}(?::\\d{2})?\\b"),
              let pibInTextRegex = try? NSRegularExpression(pattern: "(?<![\\d:-])(\\d{5,6})(?![\\d:-])") else {
            return []
        }

        let nsHtml = html as NSString
        let trMatches = trRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
        var out: [TpsMonitorItem] = []

        // Track header column indices per table section (matches Android findHeaderIndex)
        var pibColIdx: Int?
        var importirColIdx: Int?
        var statusColIdx: Int?

        for m in trMatches {
            if out.count >= 600 { break }
            let rowHtml = nsHtml.substring(with: m.range(at: 1))
            let nsRow = rowHtml as NSString
            if rowHtml.lowercased().contains("datatables_empty") { continue }

            // Check if header row
            let thMatches = thRegex.matches(in: rowHtml, range: NSRange(location: 0, length: nsRow.length))
            if thMatches.count >= 3 {
                let headers = thMatches.map { stripHtml(nsRow.substring(with: $0.range(at: 1))).uppercased() }
                pibColIdx = headers.firstIndex(where: { $0.contains("NO_DOKUMEN") || $0.contains("NO_PIB") || $0.contains("NO PIB") || $0.contains("NO. PIB") || $0 == "PIB" || $0.contains("DOKUMEN") })
                importirColIdx = headers.firstIndex(where: { $0.contains("IMPORTIR") || $0.contains("CUSTOMER") || $0.contains("CONSIGNEE") })
                statusColIdx = headers.firstIndex(where: { $0.contains("STATUS") || $0.contains("KET") })
                continue
            }

            let tdMatches = tdRegex.matches(in: rowHtml, range: NSRange(location: 0, length: nsRow.length))
            if tdMatches.count < 3 { continue }
            let rawCells = tdMatches.map { stripHtml(nsRow.substring(with: $0.range(at: 1))) }
            let cells = rawCells.filter { !$0.isEmpty }
            if cells.count < 2 { continue }
            let joined = cells.joined(separator: " • ")
            let upper = joined.uppercased() as NSString

            var cont = ""
            if let cm = contRegex.firstMatch(in: upper as String, range: NSRange(location: 0, length: upper.length)) {
                cont = upper.substring(with: cm.range(at: 1))
            }

            // 1. Header-guided PIB column first
            var pib = ""
            if let idx = pibColIdx, idx < rawCells.count {
                let cellVal = rawCells[idx]
                let scrubbedCell = dateTimeRegex.stringByReplacingMatches(in: cellVal, range: NSRange(location: 0, length: (cellVal as NSString).length), withTemplate: " ")
                if let pm = pibInTextRegex.firstMatch(in: scrubbedCell, range: NSRange(location: 0, length: (scrubbedCell as NSString).length)) {
                    pib = (scrubbedCell as NSString).substring(with: pm.range(at: 1))
                }
            }
            // 2. Exact 5-6 digit PIB cell
            if pib.isEmpty {
                for cell in cells {
                    let cTrim = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                    if exactPibCellRegex.firstMatch(in: cTrim, range: NSRange(location: 0, length: (cTrim as NSString).length)) != nil {
                        pib = cTrim
                        break
                    }
                }
            }
            // 3. Date/time & container scrubbed fallback
            if pib.isEmpty {
                var scrubbed = cont.isEmpty ? joined : joined.replacingOccurrences(of: cont, with: " ")
                scrubbed = dateTimeRegex.stringByReplacingMatches(in: scrubbed, range: NSRange(location: 0, length: (scrubbed as NSString).length), withTemplate: " ")
                if let pm = pibInTextRegex.firstMatch(in: scrubbed, range: NSRange(location: 0, length: (scrubbed as NSString).length)) {
                    pib = (scrubbed as NSString).substring(with: pm.range(at: 1))
                }
            }

            let normPib = String(pib.drop(while: { $0 == "0" }))
            let isMine = (!normPib.isEmpty && myPibs.contains(normPib))
                || (!cont.isEmpty && myContainers.contains(cont.uppercased()))

            var importir = ""
            if let idx = importirColIdx, idx < rawCells.count, !rawCells[idx].isEmpty, rawCells[idx] != "-" {
                importir = rawCells[idx]
            } else {
                importir = cells.first(where: {
                    let u = $0.uppercased()
                    return u.hasPrefix("PT") || u.hasPrefix("CV") || u.hasPrefix("UD") || u.hasPrefix("PD") || u.hasPrefix("FA") || u.hasPrefix("YAYASAN")
                }) ?? ""
            }
            let status: String
            if let idx = statusColIdx, idx < rawCells.count, !rawCells[idx].isEmpty {
                status = rawCells[idx]
            } else {
                status = cells.last ?? source
            }

            out.append(TpsMonitorItem(
                source: source,
                container: cont.isEmpty ? (cells.count > 1 ? cells[1] : cells[0]) : cont,
                pib: pib,
                importir: importir,
                status: status,
                summary: cells.prefix(8).joined(separator: " • "),
                isMyTask: isMine
            ))
        }
        return out
    }
}
