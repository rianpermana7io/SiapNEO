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
        jumlahJenisKemasan: String
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
                ("satuan_barang", ""),
                ("negara_asal", ""),
                ("spesifikasi", "")
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
                ("pel_lorong", "0"),
                ("alasan_lorong", "-"),
                ("teknik_periksa", "-"),
                ("jumlah_jenis_kemasan", jumlahJenisKemasan),
                ("uraian_barang", uraianBarang),
                ("satuan_barang", ""),
                ("negara_asal", ""),
                ("spesifikasi", "")
            ])
            return raw
        }
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
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let encoded = trimmed.replacingOccurrences(of: " ", with: "%20")
        if encoded.lowercased().hasPrefix("http://") || encoded.lowercased().hasPrefix("https://") {
            return encoded
        }
        if encoded.hasPrefix("/siap3.0") || encoded.hasPrefix("/slim3.0") || encoded.hasPrefix("/siap/") {
            return "https://bcpriok.net" + encoded
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
                var path = cleanField(item, "file_path", fallback: "")
                if path.isEmpty { path = cleanField(item, "link", fallback: "") }
                if path.isEmpty { path = cleanField(item, "url", fallback: "") }
                guard !path.isEmpty else { continue }

                var nama = cleanField(item, "nama_dokumen", fallback: "")
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

    /// Searches SIAP 3.0 pendok_mk by PIB number and returns all document attachments (PIB, INV, PL, B/L, COO, etc.)
    func fetchAttachmentsForPib(username: String, password: String, fallbackEmail: String = "", noPib: String) async throws -> [PendokDocumentAttachment] {
        let digits = noPib.filter(\.isNumber)
        guard !digits.isEmpty else { return [] }
        let items = try await browsePendok(username: username, password: password, fallbackEmail: fallbackEmail, query: digits, start: 0, length: 25)
        let normTarget = String(digits.drop(while: { $0 == "0" }))
        let matched = items.first(where: {
            let d = $0.noPib.filter(\.isNumber)
            let nd = String(d.drop(while: { $0 == "0" }))
            return d == digits || (!normTarget.isEmpty && nd == normTarget)
        }) ?? items.first
        guard let kode = matched?.actionId, !kode.isEmpty else { return [] }
        return try await fetchPendokAttachments(username: username, password: password, fallbackEmail: fallbackEmail, kodePelayanan: kode)
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
              let contRegex = try? NSRegularExpression(pattern: "\\b([A-Z]{4}\\d{7})\\b"),
              let exactPibCellRegex = try? NSRegularExpression(pattern: "^0*\\d{5,6}$"),
              let pibInTextRegex = try? NSRegularExpression(pattern: "(?<![\\d:-])(\\d{6})(?![\\d:-])") else {
            return []
        }

        let nsHtml = html as NSString
        let trMatches = trRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
        var out: [TpsMonitorItem] = []

        for m in trMatches {
            if out.count >= 600 { break }
            let rowHtml = nsHtml.substring(with: m.range(at: 1))
            if rowHtml.lowercased().contains("datatables_empty") || rowHtml.lowercased().contains("<th") { continue }
            let nsRow = rowHtml as NSString
            let tdMatches = tdRegex.matches(in: rowHtml, range: NSRange(location: 0, length: nsRow.length))
            if tdMatches.count < 3 { continue }
            let cells = tdMatches.map { stripHtml(nsRow.substring(with: $0.range(at: 1))) }.filter { !$0.isEmpty }
            if cells.count < 2 { continue }
            let joined = cells.joined(separator: " • ")
            let upper = joined.uppercased() as NSString

            var cont = ""
            if let cm = contRegex.firstMatch(in: upper as String, range: NSRange(location: 0, length: upper.length)) {
                cont = upper.substring(with: cm.range(at: 1))
            }

            // Prefer exact 5-6 digit PIB cell (skipping container & date/time cells), fallback to regex
            var pib = ""
            for cell in cells {
                let cTrim = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                if exactPibCellRegex.firstMatch(in: cTrim, range: NSRange(location: 0, length: (cTrim as NSString).length)) != nil {
                    pib = cTrim
                    break
                }
            }
            if pib.isEmpty {
                let scrubbed = cont.isEmpty ? joined : joined.replacingOccurrences(of: cont, with: "")
                if let pm = pibInTextRegex.firstMatch(in: scrubbed, range: NSRange(location: 0, length: (scrubbed as NSString).length)) {
                    pib = (scrubbed as NSString).substring(with: pm.range(at: 1))
                }
            }

            let normPib = String(pib.drop(while: { $0 == "0" }))
            let isMine = (!normPib.isEmpty && myPibs.contains(normPib))
                || (!cont.isEmpty && myContainers.contains(cont.uppercased()))

            let importir = cells.first(where: {
                let u = $0.uppercased()
                return u.hasPrefix("PT") || u.hasPrefix("CV") || u.hasPrefix("UD") || u.hasPrefix("PD") || u.hasPrefix("FA") || u.hasPrefix("YAYASAN")
            }) ?? ""
            let status = cells.last ?? source

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
