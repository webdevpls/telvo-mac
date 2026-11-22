import Foundation

// Muitos servidores IPTV só respondem para players conhecidos.
let defaultUserAgent = "VLC/3.0.21 LibVLC/3.0.21"

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func describe(_ error: Error) -> String {
    if let app = error as? AppError { return app.message }
    if let url = error as? URLError {
        switch url.code {
        case .notConnectedToInternet: return "sem internet"
        case .timedOut: return "o servidor demorou demais para responder"
        case .cannotFindHost, .dnsLookupFailed: return "servidor não encontrado"
        case .cannotConnectToHost: return "não consegui conectar ao servidor"
        case .networkConnectionLost: return "o servidor fechou a conexão sem responder"
        default: return url.localizedDescription
        }
    }
    return error.localizedDescription
}

enum Http {
    // Servidores IPTV fecham keep-alive sem avisar: sessão sem cache e sem reaproveitar conexões.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static func request(_ url: String, userAgent: String) throws -> URLRequest {
        guard let u = URL(string: url.trimmingCharacters(in: .whitespaces)) else { throw AppError("URL inválida") }
        var req = URLRequest(url: u)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.timeoutInterval = 15
        return req
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AppError("o servidor respondeu HTTP \(http.statusCode)")
        }
    }

    // O servidor às vezes derruba a conexão antes de responder (painel sobrecarregado):
    // nada foi lido ainda, então dá para tentar de novo com segurança.
    private static func withRetry<T>(_ block: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await block()
            } catch let e as URLError where [.networkConnectionLost, .timedOut, .cannotConnectToHost].contains(e.code) {
                attempt += 1
                if attempt >= 3 { throw e }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }
    }

    static func data(_ url: String, userAgent: String) async throws -> Data {
        let req = try request(url, userAgent: userAgent)
        return try await withRetry {
            let (data, response) = try await session.data(for: req)
            try check(response)
            return data
        }
    }

    // Baixa para um arquivo, avisando o progresso a cada ~1 MB.
    static func download(_ url: String, userAgent: String, to target: URL, onProgress: @escaping (Int64) -> Void = { _ in }) async throws {
        let req = try request(url, userAgent: userAgent)
        try await withRetry {
            let (bytes, response) = try await session.bytes(for: req)
            try check(response)
            let tmp = target.appendingPathExtension("tmp")
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tmp)
            defer { try? handle.close() }
            var buffer = Data()
            buffer.reserveCapacity(256 * 1024)
            var total: Int64 = 0
            var reported: Int64 = 0
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 256 * 1024 {
                    try handle.write(contentsOf: buffer)
                    total += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if total - reported >= 1_000_000 {
                        reported = total
                        onProgress(total)
                    }
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            try handle.close()
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: tmp, to: target)
        }
    }
}

// Guias EPG costumam vir em .xml.gz; detecta pelo cabeçalho, não pela extensão.
func gunzipIfNeeded(_ data: Data) -> Data {
    guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return data }
    let bytes = [UInt8](data)
    let flags = bytes[3]
    var offset = 10
    if flags & 0x04 != 0 { // FEXTRA
        let len = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        offset += 2 + len
    }
    if flags & 0x08 != 0 { while offset < bytes.count && bytes[offset] != 0 { offset += 1 }; offset += 1 } // FNAME
    if flags & 0x10 != 0 { while offset < bytes.count && bytes[offset] != 0 { offset += 1 }; offset += 1 } // FCOMMENT
    if flags & 0x02 != 0 { offset += 2 } // FHCRC
    guard offset < bytes.count - 8 else { return data }
    let deflated = Data(bytes[offset..<(bytes.count - 8)])
    // .zlib no NSData é deflate cru (sem cabeçalho), exatamente o miolo do gzip.
    return (try? (deflated as NSData).decompressed(using: .zlib) as Data) ?? data
}
