import Foundation
import SwiftUI
import CryptoKit

// MARK: - Notification for Late NPCT Importer Enrichment

extension Notification.Name {
    static let siapNpctImportersUpdated = Notification.Name("siapNpctImportersUpdated")
}

// MARK: - RowDataKit Utilities (1:1 Port of Android RowDataKitKt + SiapModelsKt.cleanServerField + ContainerNumber)

enum TpsRowKit {
    static func cleanServerField(_ raw: String, fallback: String = "") -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.caseInsensitiveCompare("null") == .orderedSame || t.caseInsensitiveCompare("n/a") == .orderedSame {
            return fallback
        }
        return t
    }

    static func normalizeContainer(_ raw: String) -> String {
        let up = raw.uppercased()
        var out = ""
        out.reserveCapacity(up.count)
        for ch in up where ch.isASCII && (ch.isLetter || ch.isNumber) {
            out.append(ch)
        }
        return out
    }

    /// Exact port of RowDataKitKt.shortStatusLabel
    static func shortStatusLabel(_ status: String) -> String {
        let upper = status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper == "SIAP PERIKSA" || upper == "SIAP" {
            return "SIAP"
        }
        if upper == "SEDANG PERIKSA" || upper == "PROSES" || upper == "SEDANG PROSES" {
            return "PROSES"
        }
        if upper.hasPrefix("PPK") {
            return "PPK"
        }
        if upper == "BELUM PEMERIKSAAN"
            || upper == "BELUM PERIKSA"
            || upper == "IP"
            || upper.hasPrefix("BELUM PEMERIKSAAN")
            || upper == "IP - BELUM PEMERIKSAAN" {
            return "IP"
        }
        return status.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Exact port of RowDataKitKt.containerSizeLabel
    static func containerSizeLabel(_ size: String) -> String {
        var upper = size.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.hasSuffix("FT") {
            upper = String(upper.dropLast(2))
        }
        if upper.hasSuffix("'") {
            upper = String(upper.dropLast(1))
        }
        let cleaned = upper.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "-" {
            return ""
        }
        let digits = String(cleaned.prefix(while: { $0.isNumber }))
        if !digits.isEmpty {
            let rest = String(cleaned.dropFirst(digits.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(digits)'\(rest)"
        }
        return cleaned
    }

    private static let isoDateRegex = try? NSRegularExpression(pattern: "^(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})")
    private static let dmyDateRegex = try? NSRegularExpression(pattern: "^(\\d{1,2})[-/.](\\d{1,2})[-/.](\\d{4})")

    /// Exact port of RowDataKitKt.formatTpsDate
    static func formatTpsDate(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("(") { s.removeFirst() }
        if s.hasSuffix(")") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "-" || s.caseInsensitiveCompare("N/A") == .orderedSame || s.caseInsensitiveCompare("null") == .orderedSame {
            return ""
        }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let m = isoDateRegex?.firstMatch(in: s, range: range) {
            let y = ns.substring(with: m.range(at: 1))
            let mo = pad2(ns.substring(with: m.range(at: 2)))
            let d = pad2(ns.substring(with: m.range(at: 3)))
            return "\(d)/\(mo)/\(y)"
        }
        if let m = dmyDateRegex?.firstMatch(in: s, range: range) {
            let d = pad2(ns.substring(with: m.range(at: 1)))
            let mo = pad2(ns.substring(with: m.range(at: 2)))
            let y = ns.substring(with: m.range(at: 3))
            return "\(d)/\(mo)/\(y)"
        }
        return s
    }

    private static func pad2(_ s: String) -> String {
        s.count < 2 ? "0\(s)" : s
    }

    /// Exact port of RowDataKitKt.locationAccentColor with Java String.hashCode() UTF-16 parity
    static func locationAccentColor(_ lokasi: String, isDark: Bool) -> Color {
        let lightPalette: [UInt32] = [0x075985, 0x166534, 0x9D174D, 0x1E40AF, 0x92400E, 0x5B21B6]
        let darkPalette: [UInt32] = [0x7DD3FC, 0x86EFAC, 0xF9A8D4, 0x93C5FD, 0xFCD34D, 0xC4B5FD]

        let upper = lokasi.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.isEmpty || upper == "-" {
            return Color(hex: isDark ? 0xE2E8F0 : 0x334155)
        }
        var h: Int32 = 0
        for unit in upper.utf16 {
            h = h &* 31 &+ Int32(unit)
        }
        let n = lightPalette.count
        let idx = ((Int(h) % n) + n) % n
        return Color(hex: isDark ? darkPalette[idx] : lightPalette[idx])
    }
}

// MARK: - Sealed NPCT BOS Credential Vault (1:1 Port of Android NpctBosVault.java)

private enum NpctBosVault {
    private static let sealedPassHex = "17b1a783e5f41f74cb82cde920439b51bbd4a3f4baa1bf6588663a7f71ac4d895504"
    private static let sealedUserHex = "96f8f4980eda6a55b41d1c1cab29682a964ec700293859bb84eaf4b6d4c1bc"
    private static let saltPkg = "b5cb972ab7e44cbb6cabf48bf17fbc82a2508cc57982818e|com.kemenkeu.bcpriok.siapneo"

    private static let derivedKey: [UInt8] = sha256([Array(saltPkg.utf8)])

    static func user() -> String { open(sealedUserHex) }
    static func pass() -> String { open(sealedPassHex) }

    private static func sha256(_ chunks: [[UInt8]]) -> [UInt8] {
        var hasher = SHA256()
        for c in chunks {
            hasher.update(data: c)
        }
        return Array(hasher.finalize())
    }

    private static func hexToBytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }

    private static func open(_ hex: String) -> String {
        guard let raw = hexToBytes(hex), raw.count >= 25 else { return "" }
        let nonce = Array(raw[0..<16])
        let cipher = Array(raw[16..<(raw.count - 8)])
        let mac = Array(raw[(raw.count - 8)..<raw.count])

        let expectedMac = Array(sha256([derivedKey, nonce, cipher]).prefix(8))
        guard expectedMac == mac else { return "" }

        var plain = [UInt8](repeating: 0, count: cipher.count)
        var offset = 0
        var counter: UInt32 = 0
        while offset < cipher.count {
            let ctrBytes: [UInt8] = [
                UInt8((counter >> 24) & 0xFF),
                UInt8((counter >> 16) & 0xFF),
                UInt8((counter >> 8) & 0xFF),
                UInt8(counter & 0xFF)
            ]
            let ks = sha256([derivedKey, nonce, ctrBytes])
            for k in ks where offset < cipher.count {
                plain[offset] = cipher[offset] ^ k
                offset += 1
            }
            counter &+= 1
        }
        return String(bytes: plain, encoding: .utf8) ?? ""
    }
}

// MARK: - Persistent TPS Monitor Cache (1:1 Port of Android TpsMonitorCache.java)

struct CachedTpsData: Codable {
    let timestampMillis: Int64
    let snapshot: TpsMonitorSnapshot
}

final class TpsMonitorCache {
    static let shared = TpsMonitorCache()
    static let soreHour = 15

    private let lock = NSLock()
    private var memory: CachedTpsData?
    private let diskQueue = DispatchQueue(label: "com.kemenkeu.bcpriok.siapneo.tpscache", qos: .utility)

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tps_monitor_cache.json")
    }

    /// Exact port of Android TpsMonitorCache.Companion.isExpired (midnight + 15:00 WIB rollover)
    static func isExpired(timestampMillis: Int64, nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        if timestampMillis <= 0 { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current
        let cachedDate = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
        let nowDate = Date(timeIntervalSince1970: TimeInterval(nowMillis) / 1000.0)
        let c1 = cal.dateComponents([.year, .month, .day, .hour], from: cachedDate)
        let c2 = cal.dateComponents([.year, .month, .day, .hour], from: nowDate)
        if c1.year == c2.year && c1.month == c2.month && c1.day == c2.day {
            return (c1.hour ?? 0) < soreHour && (c2.hour ?? 0) >= soreHour
        }
        return true
    }

    func load() -> CachedTpsData? {
        lock.lock()
        if let mem = memory {
            lock.unlock()
            return mem
        }
        lock.unlock()

        let url = cacheFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CachedTpsData.self, from: data) else {
            return nil
        }

        lock.lock()
        memory = decoded
        lock.unlock()
        return decoded
    }

    func saveInBackground(_ snapshot: TpsMonitorSnapshot, timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        var cleanSnap = snapshot
        cleanSnap.isLoading = false
        let entry = CachedTpsData(timestampMillis: timestampMillis, snapshot: cleanSnap)

        lock.lock()
        memory = entry
        lock.unlock()

        let url = cacheFileURL
        diskQueue.async {
            if let data = try? JSONEncoder().encode(entry) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func clear() {
        lock.lock()
        memory = nil
        lock.unlock()

        let url = cacheFileURL
        diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Comment-Aware & Nested-Table-Aware HTML Scanner (Matches Jsoup Selectors)

struct TpsHtmlElement {
    let openTag: String
    let innerHTML: String
    let outerHTML: String

    func attr(_ name: String) -> String {
        TpsHtmlScanner.attribute(name, inOpenTag: openTag)
    }

    var text: String {
        TpsHtmlScanner.cleanHtmlText(innerHTML)
    }
}

enum TpsHtmlScanner {
    /// Extracts all `<tag ...>...</tag>` elements in document pre-order, skipping HTML comments (`<!--...-->`),
    /// properly balancing nested tags (e.g., nested `<table>`) and tolerating unclosed `tr`/`td`/`th` elements.
    static func extractElements(tag: String, in html: String) -> [TpsHtmlElement] {
        let lowerTag = tag.lowercased()
        let isAutoCloseRowOrCell = (lowerTag == "tr" || lowerTag == "td" || lowerTag == "th")
        let bytes = Array(html.utf8)
        let n = bytes.count
        let tagBytes = Array(lowerTag.utf8)

        struct OpenEntry {
            let startIdx: Int
            let innerStartIdx: Int
            let openTagEndIdx: Int
            let tableDepth: Int
        }

        var stack: [OpenEntry] = []
        var completed: [(startIdx: Int, el: TpsHtmlElement)] = []
        var tableDepth = 0
        var i = 0

        @inline(__always)
        func asciiLower(_ b: UInt8) -> UInt8 {
            (b >= 65 && b <= 90) ? (b + 32) : b
        }

        @inline(__always)
        func isTagBoundary(_ b: UInt8) -> Bool {
            b == 62 || b == 47 || b == 32 || b == 9 || b == 10 || b == 13 // '>', '/', whitespace
        }

        func matchesWord(_ pos: Int, _ word: [UInt8]) -> Bool {
            if pos + word.count > n { return false }
            for k in 0..<word.count {
                if asciiLower(bytes[pos + k]) != word[k] { return false }
            }
            let after = pos + word.count
            return after >= n || isTagBoundary(bytes[after])
        }

        func sliceString(_ s: Int, _ e: Int) -> String {
            guard s >= 0, e >= s, e <= n else { return "" }
            return String(decoding: bytes[s..<e], as: UTF8.self)
        }

        func findTagEnd(_ from: Int) -> Int {
            var j = from
            var quote: UInt8 = 0
            while j < n {
                let c = bytes[j]
                if quote != 0 {
                    if c == quote { quote = 0 }
                } else {
                    if c == 34 || c == 39 { // '"' or '\''
                        quote = c
                    } else if c == 62 { // '>'
                        return j
                    }
                }
                j += 1
            }
            return n - 1
        }

        let tableWord = Array("table".utf8)
        let trWord = Array("tr".utf8)

        while i < n {
            if bytes[i] == 60 { // '<'
                // Skip HTML comments <!-- ... -->
                if i + 3 < n && bytes[i + 1] == 33 && bytes[i + 2] == 45 && bytes[i + 3] == 45 {
                    var j = i + 4
                    while j + 2 < n {
                        if bytes[j] == 45 && bytes[j + 1] == 45 && bytes[j + 2] == 62 {
                            j += 3
                            break
                        }
                        j += 1
                    }
                    i = min(j, n)
                    continue
                }

                let isClose = (i + 1 < n && bytes[i + 1] == 47) // '/'
                let nameStart = isClose ? (i + 2) : (i + 1)

                // Track nested table depth for tr/td/th scoping
                if lowerTag != "table" && matchesWord(nameStart, tableWord) {
                    let endGt = findTagEnd(nameStart)
                    if isClose {
                        // Close any unclosed tr/td/th belonging to this table before popping depth
                        if isAutoCloseRowOrCell {
                            while let top = stack.last, top.tableDepth == tableDepth {
                                stack.removeLast()
                                let openT = sliceString(top.startIdx, top.openTagEndIdx)
                                let inner = sliceString(top.innerStartIdx, i)
                                let outer = sliceString(top.startIdx, i)
                                completed.append((top.startIdx, TpsHtmlElement(openTag: openT, innerHTML: inner, outerHTML: outer)))
                            }
                        }
                        tableDepth = max(0, tableDepth - 1)
                    } else {
                        tableDepth += 1
                    }
                    i = endGt + 1
                    continue
                }

                // If extracting td/th and we hit </tr> or <tr>, auto-close unclosed cells at current table depth
                if (lowerTag == "td" || lowerTag == "th") && matchesWord(nameStart, trWord) {
                    while let top = stack.last, top.tableDepth == tableDepth {
                        stack.removeLast()
                        let openT = sliceString(top.startIdx, top.openTagEndIdx)
                        let inner = sliceString(top.innerStartIdx, i)
                        let outer = sliceString(top.startIdx, i)
                        completed.append((top.startIdx, TpsHtmlElement(openTag: openT, innerHTML: inner, outerHTML: outer)))
                    }
                }

                if matchesWord(nameStart, tagBytes) {
                    let endGt = findTagEnd(nameStart)
                    let nextPos = min(endGt + 1, n)
                    if isClose {
                        if let matchIdx = stack.lastIndex(where: { lowerTag == "table" || $0.tableDepth == tableDepth }) {
                            let entry = stack.remove(at: matchIdx)
                            let openT = sliceString(entry.startIdx, entry.openTagEndIdx)
                            let inner = sliceString(entry.innerStartIdx, i)
                            let outer = sliceString(entry.startIdx, nextPos)
                            completed.append((entry.startIdx, TpsHtmlElement(openTag: openT, innerHTML: inner, outerHTML: outer)))
                        }
                    } else {
                        if isAutoCloseRowOrCell, let top = stack.last, top.tableDepth == tableDepth {
                            stack.removeLast()
                            let openT = sliceString(top.startIdx, top.openTagEndIdx)
                            let inner = sliceString(top.innerStartIdx, i)
                            let outer = sliceString(top.startIdx, i)
                            completed.append((top.startIdx, TpsHtmlElement(openTag: openT, innerHTML: inner, outerHTML: outer)))
                        }
                        let isSelfClosing = (endGt > nameStart && bytes[endGt - 1] == 47)
                        if isSelfClosing {
                            let openT = sliceString(i, nextPos)
                            completed.append((i, TpsHtmlElement(openTag: openT, innerHTML: "", outerHTML: openT)))
                        } else {
                            stack.append(OpenEntry(startIdx: i, innerStartIdx: nextPos, openTagEndIdx: nextPos, tableDepth: tableDepth))
                        }
                    }
                    i = nextPos
                    continue
                }
            }
            i += 1
        }

        // Flush any unclosed tr/td/th at EOF
        if isAutoCloseRowOrCell {
            while let top = stack.popLast() {
                let openT = sliceString(top.startIdx, top.openTagEndIdx)
                let inner = sliceString(top.innerStartIdx, n)
                let outer = sliceString(top.startIdx, n)
                completed.append((top.startIdx, TpsHtmlElement(openTag: openT, innerHTML: inner, outerHTML: outer)))
            }
        }

        // Sort by document start position (matches Jsoup document pre-order)
        completed.sort { $0.startIdx < $1.startIdx }
        return completed.map(\.el)
    }

    static func attribute(_ name: String, inOpenTag openTag: String) -> String {
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = openTag as NSString
        guard let m = rx.firstMatch(in: openTag, range: NSRange(location: 0, length: ns.length)) else { return "" }
        for g in 1...3 {
            let r = m.range(at: g)
            if r.location != NSNotFound {
                return decodeEntities(ns.substring(with: r)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    static func stripComments(_ html: String) -> String {
        html.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
    }

    static func cleanHtmlText(_ raw: String) -> String {
        let noComments = stripComments(raw)
        let noTags = noComments.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = decodeEntities(noTags)
        return decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
        if s.contains("&#"), let rx = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);") {
            let ns = s as NSString
            let matches = rx.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                let token = ns.substring(with: m.range(at: 1))
                let code: UInt32?
                if token.lowercased().hasPrefix("x") {
                    code = UInt32(token.dropFirst(), radix: 16)
                } else {
                    code = UInt32(token, radix: 10)
                }
                if let c = code, let scalar = UnicodeScalar(c) {
                    s = (s as NSString).replacingCharacters(in: m.range, with: String(scalar))
                }
            }
        }
        return s
    }
}

// MARK: - TPS Monitor Repository (1:1 Port of Android TpsMonitorRepository.java)

final class TpsMonitorRepository {
    static let shared = TpsMonitorRepository()

    static let grahaDefaultUrl = "http://103.130.242.88/tpft/MON_SIAP_PERIKSA/"
    static let npctBosBase = "https://bos.multiterminal.co.id/tpk_ipc/cgis"
    static let npctDefaultUrl = "https://bos.multiterminal.co.id/tpk_ipc/cgis/application.php/display/list_antrian"
    static let npctFallbackUrl = "https://bos.multiterminal.co.id/tpk_ipc/cgis/application.php/monitoring"
    static let tpslPkbUrl = "https://bcpriok.net/siap3.0/antrian_pkb"

    private static let stealthHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7"
    ]

    private let session: URLSession
    private let stateLock = NSLock()
    private var pkbMetadataCache: [String: (tglPib: String, importir: String)] = [:]
    private var pkbFetchedAt: TimeInterval = 0
    private var importerCache: [String: String] = [:]
    private var importerCacheAt: TimeInterval = 0
    private var importerInFlight: Task<[String: String], Never>?

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 25
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        self.session = URLSession(configuration: cfg, delegate: PermissiveTLSDelegate(), delegateQueue: nil)
    }

    // MARK: - Shared Normalization & Metadata Helpers

    static func formatWibClock(_ date: Date = Date()) -> String {
        SiapCrypto.wibFormatter("HH:mm").string(from: date)
    }

    static func normalizePibKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-" || trimmed.caseInsensitiveCompare("N/A") == .orderedSame {
            return ""
        }
        let beforeSlash = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
        let beforeSpace = beforeSlash.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1).first.map(String.init) ?? beforeSlash
        let token = beforeSpace.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = token.filter(\.isNumber)
        if !digits.isEmpty {
            let stripped = String(digits.drop(while: { $0 == "0" }))
            return stripped.isEmpty ? "0" : stripped
        }
        return String(token.drop(while: { $0 == "0" })).uppercased()
    }

    static func matchesMyTask(
        noPib: String,
        noContainer: String = "",
        normalizedMyPibs: Set<String>,
        normalizedMyContainers: Set<String> = []
    ) -> Bool {
        let pk = normalizePibKey(noPib)
        if !pk.isEmpty && normalizedMyPibs.contains(pk) {
            return true
        }
        if normalizedMyContainers.isEmpty { return false }
        let ck = TpsRowKit.normalizeContainer(noContainer)
        return !ck.isEmpty && normalizedMyContainers.contains(ck)
    }

    static func recomputeMyTasks(
        snapshot: TpsMonitorSnapshot,
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) -> TpsMonitorSnapshot {
        let normPibs = Set(activeMyPibs.map(normalizePibKey).filter { !$0.isEmpty })
        let normConts = Set(activeMyContainers.map(TpsRowKit.normalizeContainer).filter { !$0.isEmpty })

        let graha = snapshot.grahaRows.map { row -> GrahaMonitorItem in
            let mine = matchesMyTask(noPib: row.noPib, noContainer: row.noContainer, normalizedMyPibs: normPibs, normalizedMyContainers: normConts)
            return row.isMyTask == mine ? row : row.with(isMyTask: mine)
        }
        let npct = snapshot.npctRows.map { row -> NpctMonitorItem in
            let mine = matchesMyTask(noPib: row.noPib, noContainer: row.noContainer, normalizedMyPibs: normPibs, normalizedMyContainers: normConts)
            return row.isMyTask == mine ? row : row.with(isMyTask: mine)
        }
        let tpsl = snapshot.tpslRows.map { row -> TpslMonitorItem in
            let mine = matchesMyTask(noPib: row.noPib, noContainer: "", normalizedMyPibs: normPibs, normalizedMyContainers: normConts)
            return row.isMyTask == mine ? row : row.with(isMyTask: mine)
        }

        var copy = snapshot
        copy.grahaRows = graha
        copy.npctRows = npct
        copy.tpslRows = tpsl
        return copy
    }

    func recordPkbMetadata(noPib: String, tglPib: String, importir: String) {
        let key = Self.normalizePibKey(noPib)
        guard !key.isEmpty else { return }
        var cleanTgl = tglPib.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTgl == "-" || cleanTgl.caseInsensitiveCompare("null") == .orderedSame { cleanTgl = "" }
        var cleanImp = importir.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanImp == "-" || cleanImp.caseInsensitiveCompare("null") == .orderedSame { cleanImp = "" }
        guard !cleanTgl.isEmpty || !cleanImp.isEmpty else { return }

        stateLock.lock()
        let prev = pkbMetadataCache[key]
        let mergedTgl = cleanTgl.isEmpty ? (prev?.tglPib ?? "") : cleanTgl
        let mergedImp = cleanImp.isEmpty ? (prev?.importir ?? "") : cleanImp
        pkbMetadataCache[key] = (mergedTgl, mergedImp)
        stateLock.unlock()
    }

    func getKnownPkbMetadata() -> [String: (tglPib: String, importir: String)] {
        stateLock.lock()
        let copy = pkbMetadataCache
        stateLock.unlock()
        return copy
    }

    private func currentImporterCache() -> (map: [String: String], fetchedAt: TimeInterval) {
        stateLock.lock()
        let result = (importerCache, importerCacheAt)
        stateLock.unlock()
        return result
    }

    // MARK: - Full Parallel Snapshot Fetch

    func fetchFullSnapshot(
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) async -> TpsMonitorSnapshot {
        let clock = Self.formatWibClock()
        let bosUser = NpctBosVault.user()
        let bosPass = NpctBosVault.pass()

        async let grahaRes = fetchGrahaMonitoringResult(activeMyPibs: activeMyPibs, activeMyContainers: activeMyContainers)
        async let npctRes = fetchNpctMonitoringResult(activeMyPibs: activeMyPibs, activeMyContainers: activeMyContainers, bosUser: bosUser, bosPass: bosPass)
        async let tpslRes = fetchTpslMonitoringResult(activeMyPibs: activeMyPibs, activeMyContainers: activeMyContainers)

        let g = await grahaRes
        let n = await npctRes
        let t = await tpslRes

        var grahaRows: [GrahaMonitorItem] = []
        var npctRows: [NpctMonitorItem] = []
        var tpslRows: [TpslMonitorItem] = []
        var failed: [String] = []
        var firstError: Error?

        switch g {
        case .success(let list): grahaRows = list
        case .failure(let err): failed.append("Graha"); if firstError == nil { firstError = err }
        }
        switch n {
        case .success(let list): npctRows = list
        case .failure(let err): failed.append("NPCT"); if firstError == nil { firstError = err }
        }
        switch t {
        case .success(let list): tpslRows = list
        case .failure(let err): failed.append("TPSL"); if firstError == nil { firstError = err }
        }

        let allFailed = failed.count == 3
        let errMsg = allFailed ? (firstError?.localizedDescription ?? "Gagal memuat monitoring TPS") : nil

        return TpsMonitorSnapshot(
            grahaRows: grahaRows,
            npctRows: npctRows,
            tpslRows: tpslRows,
            lastUpdated: clock,
            isLoading: false,
            errorMessage: errMsg,
            failedSources: failed
        )
    }

    // MARK: - HTTP Helpers

    private func makeStealthRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        for (k, v) in Self.stealthHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return req
    }

    private func fetchHtmlString(urlString: String, using targetSession: URLSession? = nil) async throws -> String {
        guard let url = URL(string: urlString) else { throw SiapApiError.invalidURL }
        let req = makeStealthRequest(url: url)
        let s = targetSession ?? session
        let (data, resp) = try await s.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SiapApiError.message("HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - 1. Graha Fetch & Parser

    func fetchGrahaMonitoringResult(
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) async -> Result<[GrahaMonitorItem], Error> {
        do {
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            let html = try await fetchHtmlString(urlString: "\(Self.grahaDefaultUrl)?_t=\(ts)")
            if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SiapApiError.message("Respons Graha kosong")
            }
            let tables = TpsHtmlScanner.extractElements(tag: "table", in: html)
            if tables.isEmpty {
                throw SiapApiError.message("Struktur tabel Graha tidak ditemukan")
            }
            let parsed = parseGrahaHtml(html, tables: tables, activeMyPibs: activeMyPibs, activeMyContainers: activeMyContainers)
            if tables.count < 4 && parsed.isEmpty {
                throw SiapApiError.message("Halaman monitoring Graha tidak lengkap")
            }
            return .success(parsed)
        } catch {
            return .failure(error)
        }
    }

    func parseGrahaHtml(
        _ html: String,
        tables preExtractedTables: [TpsHtmlElement]? = nil,
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) -> [GrahaMonitorItem] {
        let normPibs = Set(activeMyPibs.map(Self.normalizePibKey).filter { !$0.isEmpty })
        let normConts = Set(activeMyContainers.map(TpsRowKit.normalizeContainer).filter { !$0.isEmpty })

        let tables = preExtractedTables ?? TpsHtmlScanner.extractElements(tag: "table", in: html)
        let targetHtml: String
        if tables.count >= 4 {
            targetHtml = tables[3].innerHTML
        } else if let largest = tables.max(by: { $0.text.count < $1.text.count }) {
            targetHtml = largest.innerHTML
        } else {
            targetHtml = html
        }

        let commentRx1 = try? NSRegularExpression(pattern: "<!--\\s*<td[^>]*>.*?<strong>([^<]+?)</strong>.*?</td>\\s*-->", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let commentRx2 = try? NSRegularExpression(pattern: "<!--.*?<strong>([^<]+?)</strong>.*?-->", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let commentRx3 = try? NSRegularExpression(pattern: "<!--(.*?)-->", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let styleTagRx = try? NSRegularExpression(pattern: "<(?:td|span|font)\\b[^>]*>", options: [.caseInsensitive])

        var results: [GrahaMonitorItem] = []
        var seenKeys = Set<String>()

        let rows = TpsHtmlScanner.extractElements(tag: "tr", in: targetHtml)
        for row in rows {
            let tdElements = TpsHtmlScanner.extractElements(tag: "td", in: row.innerHTML)
            guard tdElements.count >= 8 else { continue }
            let cells = tdElements.map(\.text)

            // Combine style/bgcolor/class/color attributes from <tr> and visible <td>/<span>/<font>
            var colorBag = "\(row.attr("style")) \(row.attr("bgcolor")) \(row.attr("class")) "
            let visibleInner = TpsHtmlScanner.stripComments(row.innerHTML)
            if let rx = styleTagRx {
                let nsVis = visibleInner as NSString
                for m in rx.matches(in: visibleInner, range: NSRange(location: 0, length: nsVis.length)) {
                    let openTag = nsVis.substring(with: m.range)
                    colorBag += "\(TpsHtmlScanner.attribute("style", inOpenTag: openTag)) "
                    colorBag += "\(TpsHtmlScanner.attribute("bgcolor", inOpenTag: openTag)) "
                    colorBag += "\(TpsHtmlScanner.attribute("class", inOpenTag: openTag)) "
                    colorBag += "\(TpsHtmlScanner.attribute("color", inOpenTag: openTag)) "
                }
            }
            let upperColor = colorBag.uppercased()

            let status: String
            if upperColor.contains("#1E90FF") || upperColor.contains("DODGERBLUE") || upperColor.contains("BLUE") {
                status = "SEDANG PERIKSA"
            } else if upperColor.contains("#98FB98") || upperColor.contains("PALEGREEN") || upperColor.contains("GREEN") {
                status = "SIAP PERIKSA"
            } else if upperColor.contains("#FF4500") || upperColor.contains("ORANGERED") || upperColor.contains("RED") {
                status = "PPK BELUM SIAP"
            } else {
                continue
            }

            let col4 = cells.count > 4 ? cells[4] : ""
            let col5 = cells.count > 5 ? cells[5] : ""
            let col4HasDate = col4.contains("/") || col4.contains("-")
            let col5HasDate = col5.contains("/") || col5.contains("-")
            let hasVisibleImportir = col5HasDate && !col4HasDate

            let col2 = cells.count > 2 ? cells[2] : ""
            var importir = hasVisibleImportir ? (cells.count > 3 ? cells[3] : "") : ""
            let rawPib = hasVisibleImportir
                ? (cells.count > 4 ? cells[4] : "")
                : (cells.count > 3 ? cells[3] : "")
            let rawTgl = hasVisibleImportir
                ? (cells.count > 5 ? cells[5] : "")
                : (cells.count > 4 ? cells[4] : "")
            let rawContainer = hasVisibleImportir
                ? (cells.count > 6 ? cells[6] : "")
                : (cells.count > 5 ? cells[5] : "")
            let rawSize = hasVisibleImportir
                ? (cells.count > 8 ? cells[8] : "")
                : (cells.count > 7 ? cells[7] : "")
            let rawLokasi = hasVisibleImportir
                ? (cells.count > 9 ? cells[9] : "GRAHA")
                : (cells.count > 8 ? cells[8] : "GRAHA")

            if rawPib.isEmpty && rawContainer.isEmpty { continue }

            // Extract hidden importir from HTML comment if cell is empty or "-"
            if importir.isEmpty || importir == "-" {
                importir = "-"
                let outer = row.outerHTML
                let nsOuter = outer as NSString
                let fullRange = NSRange(location: 0, length: nsOuter.length)
                let match = commentRx1?.firstMatch(in: outer, range: fullRange)
                    ?? commentRx2?.firstMatch(in: outer, range: fullRange)
                    ?? commentRx3?.firstMatch(in: outer, range: fullRange)
                if let m = match, m.numberOfRanges > 1 {
                    let candidateRaw = nsOuter.substring(with: m.range(at: 1))
                    if !candidateRaw.lowercased().contains("<input") {
                        let cleaned = TpsHtmlScanner.cleanHtmlText(candidateRaw)
                        if !cleaned.isEmpty {
                            importir = cleaned
                        }
                    }
                }
            }

            let dedupKey = "\(rawContainer)_\(rawPib)_\(status)".uppercased()
            guard !seenKeys.contains(dedupKey) else { continue }
            seenKeys.insert(dedupKey)

            let finalContainer = rawContainer.isEmpty ? "N/A" : rawContainer
            let finalSize = rawSize.isEmpty ? "-" : rawSize
            let finalLokasi = rawLokasi.isEmpty ? "GRAHA" : rawLokasi
            let finalPib = rawPib.isEmpty ? "N/A" : rawPib
            let finalTgl: String
            if !rawTgl.isEmpty && rawTgl != "-" {
                finalTgl = rawTgl
            } else {
                finalTgl = col2.isEmpty ? "-" : col2
            }

            let isMine = Self.matchesMyTask(
                noPib: finalPib,
                noContainer: finalContainer,
                normalizedMyPibs: normPibs,
                normalizedMyContainers: normConts
            )

            results.append(GrahaMonitorItem(
                noContainer: finalContainer,
                size: finalSize,
                lokasi: finalLokasi,
                noPib: finalPib,
                tglPib: finalTgl,
                importir: importir,
                status: status,
                isMyTask: isMine
            ))
        }

        return results
    }

    // MARK: - 2. NPCT1 Fetch, BOS Handheld Importer Enrichment & Parser

    func fetchNpctMonitoringResult(
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>,
        bosUser: String,
        bosPass: String
    ) async -> Result<[NpctMonitorItem], Error> {
        let now = Date().timeIntervalSince1970
        let cached = currentImporterCache()
        let isCacheFresh = !cached.map.isEmpty && (now - cached.fetchedAt) < 600

        // Fire background PKB metadata warmup silently
        Task.detached(priority: .utility) { [weak self] in
            await self?.fetchPkbAntrianMetadataSilently()
        }

        // Fire BOS importer enrichment concurrently if cache is stale
        var importerTask: Task<[String: String], Never>?
        if !isCacheFresh && !bosUser.isEmpty && !bosPass.isEmpty {
            importerTask = startOrJoinImporterTask(user: bosUser, pass: bosPass)
        }

        // Fetch NPCT primary/fallback table
        let listResult = await fetchNpctListResult(activeMyPibs: activeMyPibs, activeMyContainers: activeMyContainers)
        guard case .success(let rawItems) = listResult else {
            return listResult
        }

        // Wait up to 2.0 seconds inline for BOS importer lookup (matching Android C.K(2000L, ...))
        var importersMap = currentImporterCache().map
        if !isCacheFresh, let task = importerTask {
            if let inlineResult = await waitWithTimeout(seconds: 2.0, task: task) {
                if !inlineResult.isEmpty {
                    importersMap = inlineResult
                }
            }
        }

        let pkbMeta = getKnownPkbMetadata()
        let enriched = enrichNpctRows(rawItems, importersMap: importersMap, pkbMeta: pkbMeta)
        return .success(enriched)
    }

    func enrichNpctRows(
        _ rows: [NpctMonitorItem],
        importersMap: [String: String],
        pkbMeta: [String: (tglPib: String, importir: String)]
    ) -> [NpctMonitorItem] {
        rows.map { row in
            let pibKey = Self.normalizePibKey(row.noPib)
            let pkb = pibKey.isEmpty ? nil : pkbMeta[pibKey]

            let cleanCont = row.noContainer
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .uppercased()
            let strippedPib = String(row.noPib.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "0" }))
            let bosImp = importersMap["C:\(cleanCont)"]
                ?? (strippedPib.isEmpty ? nil : importersMap["P:\(strippedPib)"])
                ?? ""

            let finalTgl: String
            if !row.tglPib.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && row.tglPib != "-" {
                finalTgl = row.tglPib
            } else if let t = pkb?.tglPib, !t.isEmpty && t != "-" {
                finalTgl = t
            } else {
                finalTgl = ""
            }

            let finalImp: String
            if !row.importir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && row.importir != "-" {
                finalImp = row.importir
            } else if let imp = pkb?.importir, !imp.isEmpty && imp != "-" {
                finalImp = imp
            } else if !bosImp.isEmpty {
                finalImp = bosImp
            } else {
                finalImp = ""
            }

            if finalTgl == row.tglPib && finalImp == row.importir {
                return row
            }
            return row.with(tglPib: finalTgl, importir: finalImp)
        }
    }

    private func waitWithTimeout<T>(seconds: TimeInterval, task: Task<T, Never>) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await task.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func startOrJoinImporterTask(user: String, pass: String) -> Task<[String: String], Never> {
        stateLock.lock()
        if let existing = importerInFlight {
            stateLock.unlock()
            return existing
        }
        let task = Task.detached(priority: .utility) { [weak self] () -> [String: String] in
            guard let self else { return [:] }
            let map = await self.fetchNpctImportersFromBos(user: user, pass: pass)
            self.stateLock.lock()
            if !map.isEmpty {
                self.importerCache = map
                self.importerCacheAt = Date().timeIntervalSince1970
            }
            self.importerInFlight = nil
            let fallback = self.importerCache
            self.stateLock.unlock()

            if !map.isEmpty {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .siapNpctImportersUpdated, object: map)
                }
            }
            return map.isEmpty ? fallback : map
        }
        importerInFlight = task
        stateLock.unlock()
        return task
    }

    private func fetchNpctImportersFromBos(user: String, pass: String) async -> [String: String] {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 25
        cfg.httpCookieStorage = HTTPCookieStorage()
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        let bosSession = URLSession(configuration: cfg, delegate: PermissiveTLSDelegate(), delegateQueue: nil)
        defer { bosSession.finishTasksAndInvalidate() }

        var result: [String: String] = [:]
        do {
            // 1. Seed session cookie
            _ = try await fetchHtmlString(urlString: "\(Self.npctBosBase)/handheld.php", using: bosSession)

            // 2. Sign in to BOS handheld
            let signInBody = "username=\(formEncode(user))&password=\(formEncode(pass))"
            _ = try await postBosForm(
                urlString: "\(Self.npctBosBase)/handheld.php/home/signin",
                body: signInBody,
                isAjax: false,
                using: bosSession
            )

            // 3. Fetch first page of pergerakan
            let page1 = try await fetchHtmlString(
                urlString: "\(Self.npctBosBase)/application.php/display/pergerakan",
                using: bosSession
            )
            parseNpctImporters(html: page1, into: &result)

            // 4. Paginate up to 5 pages
            var totalRecords = 0
            if let rx = try? NSRegularExpression(pattern: "SHOWING\\s+\\d+\\s*-\\s*\\d+\\s+OF\\s+(\\d+)\\s+RECORDS", options: [.caseInsensitive]) {
                let ns = page1 as NSString
                if let m = rx.firstMatch(in: page1, range: NSRange(location: 0, length: ns.length)),
                   let parsed = Int(ns.substring(with: m.range(at: 1))) {
                    totalRecords = parsed
                }
            }
            let totalPages = min(max((totalRecords + 49) / 50, 1), 5)
            if totalPages >= 2 {
                for page in 2...totalPages {
                    do {
                        let ajaxBody = "ajax=1&page=\(page)&orderby=STATUS2,WK_RESPON&sortby=&form%5B0%5D%5B%5D=&form%5B1%5D%5B%5D=&form%5B1%5D%5B%5D=&form%5B2%5D%5B%5D="
                        let htmlPage = try await postBosForm(
                            urlString: "\(Self.npctBosBase)/application.php/display/pergerakan",
                            body: ajaxBody,
                            isAjax: true,
                            using: bosSession
                        )
                        parseNpctImporters(html: htmlPage, into: &result)
                    } catch {
                        break
                    }
                }
            }
        } catch {
            // Silent failure matches Android fetchNpctImporters
        }
        return result
    }

    private func postBosForm(urlString: String, body: String, isAjax: Bool, using targetSession: URLSession) async throws -> String {
        guard let url = URL(string: urlString) else { throw SiapApiError.invalidURL }
        var req = makeStealthRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if isAjax {
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await targetSession.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SiapApiError.message("HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    func parseNpctImporters(html: String, into map: inout [String: String]) {
        let rows = TpsHtmlScanner.extractElements(tag: "tr", in: html)
        for row in rows {
            let tds = TpsHtmlScanner.extractElements(tag: "td", in: row.innerHTML)
            guard tds.count >= 17 else { continue }
            let cells = tds.map(\.text)
            let contKey = cells[2]
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .uppercased()
            let pibKey = String(cells[7].trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "0" }))
            let imp = cells[10]
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !imp.isEmpty && imp != "-" else { continue }
            if contKey.count >= 7 {
                map["C:\(contKey)"] = imp
            }
            if !pibKey.isEmpty {
                map["P:\(pibKey)"] = imp
            }
        }
    }

    private func fetchNpctListResult(
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) async -> Result<[NpctMonitorItem], Error> {
        var validEmptyFallback: [NpctMonitorItem]?
        var lastError: Error?

        for baseUrl in [Self.npctDefaultUrl, Self.npctFallbackUrl] {
            do {
                let ts = Int64(Date().timeIntervalSince1970 * 1000)
                let html = try await fetchHtmlString(urlString: "\(baseUrl)?_t=\(ts)")
                if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw SiapApiError.message("Respons NPCT kosong")
                }
                let hasTableScroll = html.range(of: "table_scroll", options: .caseInsensitive) != nil
                let hasTh = !TpsHtmlScanner.extractElements(tag: "th", in: html).isEmpty
                let hasValidStructure = hasTableScroll || hasTh

                let parsed = parseNpctHtml(html, activeMyPibs: activeMyPibs, activeMyContainers: activeMyContainers)
                if !parsed.isEmpty {
                    return .success(parsed)
                }
                if hasValidStructure && validEmptyFallback == nil {
                    validEmptyFallback = parsed
                }
            } catch {
                lastError = error
            }
        }

        if let fallback = validEmptyFallback {
            return .success(fallback)
        }
        return .failure(lastError ?? SiapApiError.message("Gagal memuat antrian NPCT1"))
    }

    private func findHeaderIndex(_ headers: [String], keywords: [String], defaultIndex: Int) -> Int {
        guard !headers.isEmpty else { return defaultIndex }
        for kw in keywords {
            if let idx = headers.firstIndex(where: { $0.contains(kw) }) {
                return idx
            }
        }
        return defaultIndex
    }

    private func formatNpctDate(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "-" || s.caseInsensitiveCompare("N/A") == .orderedSame {
            return ""
        }
        return TpsRowKit.formatTpsDate(s)
    }

    func parseNpctHtml(
        _ html: String,
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) -> [NpctMonitorItem] {
        let normPibs = Set(activeMyPibs.map(Self.normalizePibKey).filter { !$0.isEmpty })
        let normConts = Set(activeMyContainers.map(TpsRowKit.normalizeContainer).filter { !$0.isEmpty })

        let tables = TpsHtmlScanner.extractElements(tag: "table", in: html)
        let scrollTable = tables.first(where: { $0.attr("id").caseInsensitiveCompare("table_scroll") == .orderedSame })

        // Locate header row (>= 5 <th> cells)
        func findHeaderCells(in scopeHtml: String) -> [TpsHtmlElement]? {
            let theadList = TpsHtmlScanner.extractElements(tag: "thead", in: scopeHtml)
            for thd in theadList {
                for tr in TpsHtmlScanner.extractElements(tag: "tr", in: thd.innerHTML) {
                    let ths = TpsHtmlScanner.extractElements(tag: "th", in: tr.innerHTML)
                    if ths.count >= 5 { return ths }
                }
            }
            for tr in TpsHtmlScanner.extractElements(tag: "tr", in: scopeHtml) {
                let ths = TpsHtmlScanner.extractElements(tag: "th", in: tr.innerHTML)
                if ths.count >= 5 { return ths }
            }
            return nil
        }

        let headerElements: [TpsHtmlElement]
        if let st = scrollTable, let found = findHeaderCells(in: st.innerHTML) {
            headerElements = found
        } else if let found = findHeaderCells(in: html) {
            headerElements = found
        } else if let st = scrollTable {
            headerElements = TpsHtmlScanner.extractElements(tag: "th", in: st.innerHTML)
        } else {
            headerElements = TpsHtmlScanner.extractElements(tag: "th", in: html)
        }

        let headers = headerElements.map {
            $0.text.uppercased().replacingOccurrences(of: "[\\s-]+", with: "_", options: .regularExpression)
        }
        let hasCustomer = headers.contains { $0.contains("CUSTOMER") || $0.contains("IMPORTIR") }

        let containerIdx = findHeaderIndex(headers, keywords: ["NO_KONTAINER", "CONTAINER"], defaultIndex: 2)
        let sizeIdx = findHeaderIndex(headers, keywords: ["UKURAN", "SIZE"], defaultIndex: 3)
        let tglIdx = findHeaderIndex(headers, keywords: ["TANGGAL_DOKUMEN", "TGL_DOK", "TGL_PIB", "TANGGAL"], defaultIndex: 5)
        let pibIdx = findHeaderIndex(headers, keywords: ["NO_DOKUMEN", "NO_PIB"], defaultIndex: 7)
        let lokasiIdx = findHeaderIndex(headers, keywords: ["LOKASI"], defaultIndex: 8)
        let ketIdx = findHeaderIndex(headers, keywords: ["KETERANGAN"], defaultIndex: 9)
        let impIdx = hasCustomer ? findHeaderIndex(headers, keywords: ["CUSTOMER", "IMPORTIR"], defaultIndex: 10) : -1
        let statusIdx = findHeaderIndex(headers, keywords: ["STATUS"], defaultIndex: 11)
        let noteIdx = findHeaderIndex(headers, keywords: ["NOTE"], defaultIndex: hasCustomer ? 12 : 10)
        let siapIdx = findHeaderIndex(headers, keywords: ["SIAP_PERIKSA"], defaultIndex: 14)
        let responIdx = findHeaderIndex(headers, keywords: ["RESPON"], defaultIndex: hasCustomer ? 15 : 12)

        // Locate data rows
        let rows: [TpsHtmlElement]
        if let st = scrollTable {
            let tbodies = TpsHtmlScanner.extractElements(tag: "tbody", in: st.innerHTML)
            let tbodyRows = tbodies.flatMap { TpsHtmlScanner.extractElements(tag: "tr", in: $0.innerHTML) }
            rows = tbodyRows.isEmpty ? TpsHtmlScanner.extractElements(tag: "tr", in: st.innerHTML) : tbodyRows
        } else {
            rows = TpsHtmlScanner.extractElements(tag: "tr", in: html)
        }

        var results: [NpctMonitorItem] = []
        var seenContainers = Set<String>()

        func cell(_ arr: [String], _ idx: Int, default def: String = "") -> String {
            (idx >= 0 && idx < arr.count) ? arr[idx] : def
        }

        for row in rows {
            if !TpsHtmlScanner.extractElements(tag: "th", in: row.innerHTML).isEmpty { continue }
            if !TpsHtmlScanner.extractElements(tag: "select", in: row.innerHTML).isEmpty { continue }

            let tds = TpsHtmlScanner.extractElements(tag: "td", in: row.innerHTML)
            guard tds.count >= 11 else { continue }
            let cells = tds.map(\.text)

            let noContainer = cell(cells, containerIdx).uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard noContainer.count >= 5, !seenContainers.contains(noContainer) else { continue }
            seenContainers.insert(noContainer)

            let size = cell(cells, sizeIdx, default: "-")
            let tglPib = formatNpctDate(cell(cells, tglIdx))
            let noPib = cell(cells, pibIdx, default: "N/A")
            let lokasi = cell(cells, lokasiIdx, default: "N/A")
            let keterangan = cell(cells, ketIdx, default: "-")

            let rawImp = impIdx >= 0 ? cell(cells, impIdx) : ""
            let importir = (rawImp.isEmpty || rawImp == "-") ? "" : rawImp

            let rawSiap = siapIdx >= 0 ? cell(cells, siapIdx) : ""
            let waktuSiap = (rawSiap.isEmpty || rawSiap == "-") ? "" : rawSiap

            // Status detection (4 candidates + fallback CSS class posisi1..4)
            let candidatesRaw = [
                cell(cells, statusIdx).uppercased(),
                cell(cells, responIdx).uppercased(),
                cell(cells, 12).uppercased(),
                cell(cells, 11).uppercased()
            ]
            var seenCand = Set<String>()
            var resolvedStatus: String?
            for cand in candidatesRaw where !cand.isEmpty && seenCand.insert(cand).inserted {
                if cand.contains("SIAP") && !cand.contains("BELUM") {
                    resolvedStatus = "SIAP PERIKSA"
                    break
                } else if cand.contains("SEDANG") || cand.contains("PROSES") {
                    resolvedStatus = "SEDANG PERIKSA"
                    break
                } else if cand.contains("BELUM PPK") {
                    resolvedStatus = "BELUM PPK"
                    break
                } else if cand == "PPK" || (cand.contains("PPK") && !cand.contains("LONGROOM") && !cand.contains("MINI") && !cand.contains("YARD") && !cand.contains("RESPON")) {
                    resolvedStatus = "PPK"
                    break
                }
            }

            if resolvedStatus == nil {
                let rowClass = row.attr("class").lowercased()
                let tokens = Set(rowClass.split(whereSeparator: \.isWhitespace).map(String.init))
                if rowClass == "posisi1" || tokens.contains("posisi1") {
                    resolvedStatus = "SIAP PERIKSA"
                } else if rowClass == "posisi2" || tokens.contains("posisi2") {
                    resolvedStatus = "PPK"
                } else if rowClass == "posisi3" || tokens.contains("posisi3") {
                    resolvedStatus = "BELUM PPK"
                } else if rowClass == "posisi4" || tokens.contains("posisi4") {
                    resolvedStatus = "SEDANG PERIKSA"
                }
            }

            guard let status = resolvedStatus else { continue }

            // Note resolution
            let rawNote = noteIdx >= 0 ? cell(cells, noteIdx, default: "-") : "-"
            let note: String
            if !rawNote.isEmpty && rawNote.caseInsensitiveCompare(status) != .orderedSame {
                note = rawNote
            } else {
                let col10 = cell(cells, 10)
                if !col10.isEmpty && col10.caseInsensitiveCompare(status) != .orderedSame {
                    note = col10
                } else {
                    note = "-"
                }
            }

            // Respon resolution
            let respon: String
            if let exactRespIdx = headers.firstIndex(of: "RESPON") {
                respon = cell(cells, exactRespIdx)
            } else if cells.count >= 14 {
                let fallbackCandidates = [cell(cells, 13), cell(cells, 15), cell(cells, 12)]
                respon = fallbackCandidates.first(where: { !$0.isEmpty && $0.caseInsensitiveCompare(status) != .orderedSame }) ?? ""
            } else {
                respon = cell(cells, 12)
            }

            let isMine = Self.matchesMyTask(
                noPib: noPib,
                noContainer: noContainer,
                normalizedMyPibs: normPibs,
                normalizedMyContainers: normConts
            )

            results.append(NpctMonitorItem(
                noContainer: noContainer,
                size: size.isEmpty ? "-" : size,
                lokasi: lokasi.isEmpty ? "N/A" : lokasi,
                noPib: noPib.isEmpty ? "N/A" : noPib,
                tglPib: tglPib,
                waktuGateIn: "",
                status: status,
                keterangan: keterangan.isEmpty ? "-" : keterangan,
                note: note,
                respon: respon,
                isMyTask: isMine,
                importir: importir,
                waktuSiapPeriksa: waktuSiap
            ))
        }

        return results
    }

    // MARK: - 3. TPSL & PKB Metadata Fetch & Parser

    func fetchPkbAntrianMetadataSilently() async {
        let now = Date().timeIntervalSince1970
        stateLock.lock()
        let skip = !pkbMetadataCache.isEmpty && (now - pkbFetchedAt) < 120
        stateLock.unlock()
        if skip { return }

        let ts = Int64(now * 1000)
        if let html = try? await fetchHtmlString(urlString: "\(Self.tpslPkbUrl)?_t=\(ts)"),
           !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extractAllPkbMetadata(from: html)
            stateLock.lock()
            pkbFetchedAt = Date().timeIntervalSince1970
            stateLock.unlock()
        }
    }

    func extractAllPkbMetadata(from html: String) {
        let tables = TpsHtmlScanner.extractElements(tag: "table", in: html)
        for table in tables where !table.attr("id").isEmpty {
            let rows = TpsHtmlScanner.extractElements(tag: "tr", in: table.innerHTML)
            for row in rows {
                if row.outerHTML.lowercased().contains("datatables_empty") { continue }
                if !TpsHtmlScanner.extractElements(tag: "th", in: row.innerHTML).isEmpty { continue }
                let tds = TpsHtmlScanner.extractElements(tag: "td", in: row.innerHTML)
                guard tds.count >= 6 else { continue }
                let cells = tds.map(\.text)
                recordPkbMetadata(noPib: cells[4], tglPib: cells[5], importir: cells[3])
            }
        }
    }

    func fetchTpslMonitoringResult(
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) async -> Result<[TpslMonitorItem], Error> {
        do {
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            let html = try await fetchHtmlString(urlString: "\(Self.tpslPkbUrl)?_t=\(ts)")
            if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SiapApiError.message("Respons TPSL kosong")
            }
            let tables = TpsHtmlScanner.extractElements(tag: "table", in: html).filter { !$0.attr("id").isEmpty }
            if tables.isEmpty {
                throw SiapApiError.message("Tabel antrian TPSL tidak ditemukan")
            }
            let parsed = parseTpslHtml(html, tablesWithId: tables, activeMyPibs: activeMyPibs, activeMyContainers: activeMyContainers)
            stateLock.lock()
            pkbFetchedAt = Date().timeIntervalSince1970
            stateLock.unlock()
            return .success(parsed)
        } catch {
            return .failure(error)
        }
    }

    func parseTpslHtml(
        _ html: String,
        tablesWithId preExtracted: [TpsHtmlElement]? = nil,
        activeMyPibs: Set<String>,
        activeMyContainers: Set<String>
    ) -> [TpslMonitorItem] {
        extractAllPkbMetadata(from: html)

        let normPibs = Set(activeMyPibs.map(Self.normalizePibKey).filter { !$0.isEmpty })
        let normConts = Set(activeMyContainers.map(TpsRowKit.normalizeContainer).filter { !$0.isEmpty })

        let tables = preExtracted ?? TpsHtmlScanner.extractElements(tag: "table", in: html).filter { !$0.attr("id").isEmpty }
        var results: [TpslMonitorItem] = []
        var seenKeys = Set<String>()

        for table in tables {
            let tableId = table.attr("id").lowercased()
            if tableId.contains("gsra") || tableId.contains("nct1") {
                continue
            }

            let cluster: String
            if tableId.contains("zona") {
                cluster = "TPSL"
            } else if tableId.contains("lcl") {
                cluster = "LCL"
            } else if tableId.contains("ji") {
                cluster = "JOINT_INSPECTION"
            } else if tableId.contains("mita") {
                cluster = "MITA"
            } else {
                cluster = "TPSL"
            }

            let rows = TpsHtmlScanner.extractElements(tag: "tr", in: table.innerHTML)
            for row in rows {
                if row.outerHTML.lowercased().contains("datatables_empty") { continue }
                if !TpsHtmlScanner.extractElements(tag: "th", in: row.innerHTML).isEmpty { continue }

                let tds = TpsHtmlScanner.extractElements(tag: "td", in: row.innerHTML)
                guard tds.count >= 8 else { continue }
                let cells = tds.map(\.text)

                let pengajuan = cells[0].isEmpty ? "-" : cells[0]
                let antrian = cells[1].isEmpty ? "-" : cells[1]
                let kodeTiket = cells[2].isEmpty ? "-" : cells[2]
                let importir = cells[3].isEmpty ? "-" : cells[3]
                let noPib = cells[4].isEmpty ? "-" : cells[4]
                let tglPib = cells[5].isEmpty ? "-" : cells[5]
                let lokasi = cells[6].isEmpty ? "-" : cells[6]
                let keputusan = cells[7].isEmpty ? "-" : cells[7]

                let dedupKey = "\(cluster)_\(kodeTiket)_\(noPib)_\(antrian)".uppercased()
                guard !seenKeys.contains(dedupKey) else { continue }
                seenKeys.insert(dedupKey)

                let isMine = Self.matchesMyTask(
                    noPib: noPib,
                    noContainer: "",
                    normalizedMyPibs: normPibs,
                    normalizedMyContainers: normConts
                )

                results.append(TpslMonitorItem(
                    pengajuan: pengajuan,
                    antrian: antrian,
                    kodeTiket: kodeTiket,
                    importir: importir,
                    noPib: noPib,
                    tglPib: tglPib,
                    lokasi: lokasi,
                    keputusan: keputusan,
                    cluster: cluster,
                    isMyTask: isMine
                ))
            }
        }

        return results
    }
}

// MARK: - Filter & Sort Engines (1:1 Port of Android filterAndSortGraha / Npct / Tpsl)

enum TpsFilterAndSort {
    static func matchesStatus(_ rawStatus: String, filter: TpsFilterStatus) -> Bool {
        let up = rawStatus.uppercased()
        switch filter {
        case .all:
            return true
        case .siap:
            return up.contains("SIAP") && !up.contains("BELUM")
        case .sedang:
            return up.contains("SEDANG") || up.contains("PROSES")
        case .ppk:
            return up.contains("PPK")
        }
    }

    private static func statusSortRank(_ rawStatus: String) -> Int {
        let up = rawStatus.uppercased()
        if up.contains("SIAP") && !up.contains("BELUM") { return 0 }
        if up.contains("SEDANG") || up.contains("PROSES") { return 1 }
        if up.contains("PPK") || up.contains("BELUM") { return 2 }
        return 3
    }

    static func filterAndSortGraha(
        rows: [GrahaMonitorItem],
        filter: TpsFilterStatus,
        query: String,
        sort: GrahaSortOption
    ) -> [GrahaMonitorItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = rows.filter { item in
            guard matchesStatus(item.status, filter: filter) else { return false }
            if q.isEmpty { return true }
            return item.noContainer.lowercased().contains(q)
                || item.noPib.lowercased().contains(q)
                || item.importir.lowercased().contains(q)
                || item.lokasi.lowercased().contains(q)
        }

        return filtered.sorted { a, b in
            if a.isMyTask != b.isMyTask { return a.isMyTask && !b.isMyTask }
            switch sort {
            case .default:
                let ra = statusSortRank(a.status)
                let rb = statusSortRank(b.status)
                if ra != rb { return ra < rb }
                return false
            case .lokasiAsc:
                let la = TpsRowKit.cleanServerField(a.lokasi, fallback: "")
                let lb = TpsRowKit.cleanServerField(b.lokasi, fallback: "")
                let aBlank = la.isEmpty || la == "-"
                let bBlank = lb.isEmpty || lb == "-"
                if aBlank != bBlank { return !aBlank && bBlank }
                let cmp = la.localizedCaseInsensitiveCompare(lb)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return a.noContainer.localizedCaseInsensitiveCompare(b.noContainer) == .orderedAscending
            case .containerAsc:
                return a.noContainer.localizedCaseInsensitiveCompare(b.noContainer) == .orderedAscending
            case .pibAsc:
                return a.noPib.localizedCaseInsensitiveCompare(b.noPib) == .orderedAscending
            }
        }
    }

    static func filterAndSortNpct(
        rows: [NpctMonitorItem],
        filter: TpsFilterStatus,
        query: String,
        sort: NpctSortOption
    ) -> [NpctMonitorItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = rows.filter { item in
            guard matchesStatus(item.status, filter: filter) else { return false }
            if q.isEmpty { return true }
            return item.noContainer.lowercased().contains(q)
                || item.noPib.lowercased().contains(q)
                || item.importir.lowercased().contains(q)
                || item.lokasi.lowercased().contains(q)
                || item.keterangan.lowercased().contains(q)
        }

        return filtered.sorted { a, b in
            if a.isMyTask != b.isMyTask { return a.isMyTask && !b.isMyTask }
            switch sort {
            case .siapPeriksaDesc:
                let sa = a.waktuSiapPeriksa.trimmingCharacters(in: .whitespacesAndNewlines)
                let sb = b.waktuSiapPeriksa.trimmingCharacters(in: .whitespacesAndNewlines)
                if sa.isEmpty != sb.isEmpty { return !sa.isEmpty && sb.isEmpty }
                if sa != sb { return sa > sb }
                return false
            case .siapPeriksaAsc:
                let sa = a.waktuSiapPeriksa.trimmingCharacters(in: .whitespacesAndNewlines)
                let sb = b.waktuSiapPeriksa.trimmingCharacters(in: .whitespacesAndNewlines)
                if sa.isEmpty != sb.isEmpty { return !sa.isEmpty && sb.isEmpty }
                if sa != sb { return sa < sb }
                return false
            case .containerAsc:
                return a.noContainer.localizedCaseInsensitiveCompare(b.noContainer) == .orderedAscending
            case .pibAsc:
                return a.noPib.localizedCaseInsensitiveCompare(b.noPib) == .orderedAscending
            }
        }
    }

    static func filterAndSortTpsl(
        rows: [TpslMonitorItem],
        clusterFilter: String,
        query: String,
        sort: TpslSortOption
    ) -> [TpslMonitorItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cf = clusterFilter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let filtered = rows.filter { item in
            if cf != "SEMUA" && !cf.isEmpty {
                if item.cluster.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != cf {
                    return false
                }
            }
            if q.isEmpty { return true }
            return item.noPib.lowercased().contains(q)
                || item.importir.lowercased().contains(q)
                || item.lokasi.lowercased().contains(q)
                || item.antrian.lowercased().contains(q)
        }

        return filtered.sorted { a, b in
            if a.isMyTask != b.isMyTask { return a.isMyTask && !b.isMyTask }
            switch sort {
            case .default:
                return false
            case .tpsAsc:
                let la = TpsRowKit.cleanServerField(a.lokasi, fallback: "")
                let lb = TpsRowKit.cleanServerField(b.lokasi, fallback: "")
                let aBlank = la.isEmpty || la == "-"
                let bBlank = lb.isEmpty || lb == "-"
                if aBlank != bBlank { return !aBlank && bBlank }
                let cmp = la.localizedCaseInsensitiveCompare(lb)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                let na = Int(a.antrian.filter(\.isNumber)) ?? Int.max
                let nb = Int(b.antrian.filter(\.isNumber)) ?? Int.max
                if na != nb { return na < nb }
                return false
            }
        }
    }

    /// Exact port of Android cluster ordering in TpsMonitoringHubScreen (SEMUA + preferred TPSL/JI/MITA + remaining sorted)
    static func tpslClusters(for rows: [TpslMonitorItem]) -> [String] {
        var uniqueSet = Set<String>()
        var uniqueOrdered: [String] = []
        for r in rows {
            let c = r.cluster.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !c.isEmpty && uniqueSet.insert(c).inserted {
                uniqueOrdered.append(c)
            }
        }
        let preferred = ["TPSL", "JI", "MITA"]
        let presentPreferred = preferred.filter { p in
            uniqueOrdered.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame })
        }
        let others = uniqueOrdered.filter { c in
            !preferred.contains(where: { $0.caseInsensitiveCompare(c) == .orderedSame })
        }.sorted()
        let combined = presentPreferred + others
        return ["SEMUA"] + (combined.isEmpty ? preferred : combined)
    }
}
