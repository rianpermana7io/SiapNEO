import Foundation
import Darwin

/// Pure-Swift passive binary FTP client (zero external dependencies)
/// Matches SiapFtpClient.kt in SIAP NEO Android v1.19.0
final class SiapFtpClient {
    static let shared = SiapFtpClient()

    private let host = "ftp.bcpriok.net"
    private let port: UInt16 = 21
    private let user = "siapfb@bcpriok.net"
    private let pass = "4k{9}kp2`t#~&Zcg"

    enum FtpError: LocalizedError {
        case connectFailed(String)
        case replyError(String)
        case pasvParseFailed(String)

        var errorDescription: String? {
            switch self {
            case .connectFailed(let m): return "FTP gagal terhubung: \(m)"
            case .replyError(let m): return "FTP ditolak: \(m)"
            case .pasvParseFailed(let m): return "FTP PASV tidak valid: \(m)"
            }
        }
    }

    func upload(remoteDir: String, remoteFilename: String, data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let msg = try self.uploadSync(remoteDir: remoteDir, remoteFilename: remoteFilename, data: data)
                    cont.resume(returning: msg)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func connectSocket(host: String, port: UInt16, timeoutSec: Int = 20) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &res)
        guard status == 0, let first = res else {
            throw FtpError.connectFailed("DNS lookup gagal untuk \(host)")
        }
        defer { freeaddrinfo(res) }

        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let current = ptr {
            let fd = Darwin.socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if fd >= 0 {
                var tv = timeval(tv_sec: timeoutSec, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                if Darwin.connect(fd, current.pointee.ai_addr, current.pointee.ai_addrlen) == 0 {
                    return fd
                }
                Darwin.close(fd)
            }
            ptr = current.pointee.ai_next
        }
        throw FtpError.connectFailed("Tidak dapat membuka socket ke \(host):\(port)")
    }

    private func sendAll(_ fd: Int32, bytes: Data) throws {
        try bytes.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var total = 0
            while total < bytes.count {
                let n = Darwin.send(fd, base.advanced(by: total), bytes.count - total, 0)
                if n <= 0 {
                    throw FtpError.connectFailed("Gagal mengirim data ke socket FTP")
                }
                total += n
            }
        }
    }

    private func readLine(_ fd: Int32) throws -> String {
        var buf = Data()
        var ch: UInt8 = 0
        while true {
            let n = Darwin.recv(fd, &ch, 1, 0)
            if n <= 0 { break }
            buf.append(ch)
            if ch == 10 { break } // '\n'
        }
        return String(data: buf, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func readReply(_ fd: Int32) throws -> (Int, String) {
        let first = try readLine(fd)
        guard first.count >= 3, let code = Int(first.prefix(3)) else {
            throw FtpError.replyError(first.isEmpty ? "Koneksi terputus" : first)
        }
        var lines = [first]
        // Multi-line FTP reply: "220-..." continues until "220 ..."
        if first.count >= 4 && first[first.index(first.startIndex, offsetBy: 3)] == "-" {
            let endPrefix = "\(first.prefix(3)) "
            while true {
                let next = try readLine(fd)
                if next.isEmpty { break }
                lines.append(next)
                if next.hasPrefix(endPrefix) { break }
            }
        }
        return (code, lines.joined(separator: "\n"))
    }

    private func command(_ fd: Int32, _ cmd: String) throws -> (Int, String) {
        try sendAll(fd, bytes: Data("\(cmd)\r\n".utf8))
        return try readReply(fd)
    }

    private func parsePasv(_ reply: String) throws -> (String, UInt16) {
        guard let openIdx = reply.firstIndex(of: "("),
              let closeIdx = reply.firstIndex(of: ")"),
              openIdx < closeIdx else {
            throw FtpError.pasvParseFailed(reply)
        }
        let inner = reply[reply.index(after: openIdx)..<closeIdx]
        let parts = inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 6 else {
            throw FtpError.pasvParseFailed(reply)
        }
        let ip = "\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])"
        let port = UInt16((parts[4] * 256) + parts[5])
        return (ip, port)
    }

    private func uploadSync(remoteDir: String, remoteFilename: String, data: Data) throws -> String {
        let ctrl = try connectSocket(host: host, port: port, timeoutSec: 20)
        defer { Darwin.close(ctrl) }

        let (greetCode, greetMsg) = try readReply(ctrl)
        guard greetCode == 220 else { throw FtpError.replyError(greetMsg) }

        let (uCode, uMsg) = try command(ctrl, "USER \(user)")
        if uCode == 331 {
            let (pCode, pMsg) = try command(ctrl, "PASS \(pass)")
            guard pCode == 230 else { throw FtpError.replyError(pMsg) }
        } else if uCode != 230 {
            throw FtpError.replyError(uMsg)
        }

        _ = try command(ctrl, "TYPE I")

        let cleanDir = remoteDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !cleanDir.isEmpty {
            for part in cleanDir.split(separator: "/").map(String.init) where !part.isEmpty {
                let (cwdCode, _) = try command(ctrl, "CWD \(part)")
                if cwdCode != 250 {
                    _ = try command(ctrl, "MKD \(part)")
                    let (cwd2, cwd2Msg) = try command(ctrl, "CWD \(part)")
                    if cwd2 != 250 {
                        throw FtpError.replyError("CWD \(part) gagal: \(cwd2Msg)")
                    }
                }
            }
        }

        let (pasvCode, pasvMsg) = try command(ctrl, "PASV")
        guard pasvCode == 227 else { throw FtpError.pasvParseFailed(pasvMsg) }
        let (dataIp, dataPort) = try parsePasv(pasvMsg)

        let dataFd = try connectSocket(host: dataIp, port: dataPort, timeoutSec: 35)
        let (storCode, storMsg) = try command(ctrl, "STOR \(remoteFilename)")
        guard storCode == 150 || storCode == 125 else {
            Darwin.close(dataFd)
            throw FtpError.replyError(storMsg)
        }

        do {
            try sendAll(dataFd, bytes: data)
        } catch {
            Darwin.close(dataFd)
            throw error
        }
        Darwin.close(dataFd)

        let (doneCode, doneMsg) = try readReply(ctrl)
        _ = try? command(ctrl, "QUIT")
        guard doneCode == 226 || doneCode == 250 else {
            throw FtpError.replyError(doneMsg)
        }
        return doneMsg
    }
}
