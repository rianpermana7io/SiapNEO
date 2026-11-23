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
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, _) in dict {
            out[k] = cleanField(dict, k, fallback: "")
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

    // MARK: - SIAP 3.0 Pendok Browse

    private func ensureSiap3Login(username: String, password: String) async throws {
        if siap3LoggedInUser == username && Date().timeIntervalSince(siap3LoggedInAt) < 1200 {
            return
        }
        guard let loginPageUrl = URL(string: "\(SiapCrypto.siap3Base)/auth/login"),
              let loginPostUrl = URL(string: "\(SiapCrypto.siap3Base)/auth/login_action/") else {
            throw SiapApiError.invalidURL
        }
        _ = try await siap3Session.data(from: loginPageUrl)

        var req = URLRequest(url: loginPostUrl)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(loginPageUrl.absoluteString, forHTTPHeaderField: "Referer")
        req.httpBody = formEncode([
            ("identity", username),
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
        if !ok {
            throw SiapApiError.message("Gagal login ke SIAP 3.0. Periksa username/password.")
        }
        siap3LoggedInUser = username
        siap3LoggedInAt = Date()
    }

    func browsePendok(username: String, password: String, query: String) async throws -> [PendokItem] {
        try await ensureSiap3Login(username: username, password: password)
        guard let url = URL(string: "\(SiapCrypto.siap3Base)/pendok_mk/browse_data") else {
            throw SiapApiError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("\(SiapCrypto.siap3Base)/pendok_mk", forHTTPHeaderField: "Referer")
        req.httpBody = formEncode([
            ("draw", "1"),
            ("start", "0"),
            ("length", "30"),
            ("search[value]", query),
            ("search[regex]", "false")
        ])

        let (data, _) = try await siap3Session.data(for: req)
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = dict["data"] as? [[Any]] else {
            return []
        }

        return rows.map { row in
            let cleaned = row.map { stripHtml(String(describing: $0)) }.filter { !$0.isEmpty }
            let title = cleaned.count > 1 ? cleaned[1] : (cleaned.first ?? "Dokumen")
            let status = cleaned.last ?? ""
            let sub = cleaned.dropFirst(2).prefix(4).joined(separator: " • ")
            return PendokItem(title: title, subtitle: sub, status: status)
        }
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

        let (data, _) = try await session.data(from: url)
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
              let pibRegex = try? NSRegularExpression(pattern: "\\b(\\d{6})\\b") else {
            return []
        }

        let nsHtml = html as NSString
        let trMatches = trRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
        var out: [TpsMonitorItem] = []

        for m in trMatches {
            if out.count >= 200 { break }
            let rowHtml = nsHtml.substring(with: m.range(at: 1))
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
            var pib = ""
            if let pm = pibRegex.firstMatch(in: joined, range: NSRange(location: 0, length: (joined as NSString).length)) {
                pib = (joined as NSString).substring(with: pm.range(at: 1))
            }
            let normPib = String(pib.drop(while: { $0 == "0" }))
            let isMine = (!normPib.isEmpty && myPibs.contains(normPib))
                || (!cont.isEmpty && myContainers.contains(cont.uppercased()))

            let importir = cells.first(where: { $0.uppercased().hasPrefix("PT") || $0.uppercased().hasPrefix("CV") }) ?? ""
            let status = cells.last ?? source

            out.append(TpsMonitorItem(
                source: source,
                container: cont.isEmpty ? (cells.count > 1 ? cells[1] : cells[0]) : cont,
                pib: pib,
                importir: importir,
                status: status,
                summary: cells.prefix(6).joined(separator: " • "),
                isMyTask: isMine
            ))
        }
        return out
    }
}
