import Foundation

struct XtreamAccount {
    let base: String
    let username: String
    let password: String
    let liveExtension: String
}

// Reconhece URLs de servidor Xtream Codes (get.php ou player_api.php com usuário e senha).
func xtreamAccount(_ url: String) -> XtreamAccount? {
    guard let c = URLComponents(string: url.trimmingCharacters(in: .whitespaces)),
          c.path.hasSuffix("get.php") || c.path.hasSuffix("player_api.php"),
          let scheme = c.scheme, let host = c.host else { return nil }
    let items = c.queryItems ?? []
    func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
    guard let user = q("username"), let pass = q("password") else { return nil }
    let port = c.port.map { ":\($0)" } ?? ""
    return XtreamAccount(base: "\(scheme)://\(host)\(port)", username: user, password: pass,
                         liveExtension: q("output") == "ts" ? "ts" : "m3u8")
}

private func encode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
}

// Os painéis misturam número e texto no mesmo campo; tudo vira String.
private func str(_ value: Any?) -> String? {
    switch value {
    case let s as String: return s
    case let n as NSNumber: return n.stringValue
    default: return nil
    }
}

private func nonBlank(_ value: Any?) -> String? {
    guard let s = str(value)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    return s
}

// "5.667" -> "5.7"; "8" continua "8".
private func formatRating(_ value: Any?) -> String? {
    guard let n = str(value).flatMap(Double.init), n > 0 else { return nil }
    return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(format: "%.1f", n)
}

private func decodeBase64(_ value: String) -> String {
    guard !value.isEmpty, value.count % 4 == 0,
          value.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil,
          let data = Data(base64Encoded: value), let text = String(data: data, encoding: .utf8) else { return value }
    return text
}

/// Cliente da API do Xtream Codes (player_api.php). As respostas grandes ficam em cache em disco.
final class Xtream: @unchecked Sendable {
    private let account: XtreamAccount
    private let userAgent: String
    private let dir: URL
    private let user: String
    private let pass: String
    private let api: String

    init(account: XtreamAccount, userAgent: String, dir: URL) {
        self.account = account
        self.userAgent = userAgent
        self.dir = dir
        user = encode(account.username)
        pass = encode(account.password)
        api = "\(account.base)/player_api.php?username=\(user)&password=\(pass)"
    }

    func checkAccount() async throws {
        let data = try await Http.data(api, userAgent: userAgent)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["user_info"] as? [String: Any] else { throw AppError("o servidor não respondeu como Xtream") }
        if str(info["auth"]) != "1" { throw AppError("usuário ou senha recusados") }
        if let status = nonBlank(info["status"]), status != "Active" { throw AppError("conta \(status)") }
    }

    func live(force: Bool) async throws -> [Channel] {
        let categories = Dictionary(try await categoryList("get_live_categories", force: force).map { ($0.id, $0.name) },
                                    uniquingKeysWith: { a, _ in a })
        return try await array("get_live_streams", force: force).compactMap { o in
            guard let id = str(o["stream_id"]) else { return nil }
            return Channel(
                name: str(o["name"])?.trimmingCharacters(in: .whitespaces) ?? "",
                url: "\(account.base)/live/\(user)/\(pass)/\(id).\(account.liveExtension)",
                group: str(o["category_id"]).flatMap { categories[$0] } ?? noGroup,
                logo: nonBlank(o["stream_icon"]),
                tvgId: nonBlank(o["epg_channel_id"]),
                tvgName: nil,
                streamId: id
            )
        }
    }

    func movies(force: Bool) async throws -> ([VodCategory], [VodItem]) {
        let categories = try await categoryList("get_vod_categories", force: force)
        let items: [VodItem] = try await array("get_vod_streams", force: force).compactMap { o in
            guard let id = str(o["stream_id"]) else { return nil }
            return VodItem(
                id: id,
                name: str(o["name"])?.trimmingCharacters(in: .whitespaces) ?? "",
                poster: nonBlank(o["stream_icon"]),
                categoryId: str(o["category_id"]) ?? "",
                rating: formatRating(o["rating"]),
                url: "\(account.base)/movie/\(user)/\(pass)/\(id).\(nonBlank(o["container_extension"]) ?? "mp4")"
            )
        }
        return (categories, items)
    }

    func series(force: Bool) async throws -> ([VodCategory], [VodItem]) {
        let categories = try await categoryList("get_series_categories", force: force)
        let items: [VodItem] = try await array("get_series", force: force).compactMap { o in
            guard let id = str(o["series_id"]) else { return nil }
            return VodItem(
                id: id,
                name: str(o["name"])?.trimmingCharacters(in: .whitespaces) ?? "",
                poster: nonBlank(o["cover"]),
                categoryId: str(o["category_id"]) ?? "",
                rating: formatRating(o["rating"]),
                year: nonBlank(o["releaseDate"]).map { String($0.prefix(4)) },
                plot: nonBlank(o["plot"]),
                genre: nonBlank(o["genre"])
            )
        }
        return (categories, items)
    }

    func seriesInfo(_ seriesId: String) async throws -> SeriesInfo {
        let data = try await Http.data("\(api)&action=get_series_info&series_id=\(seriesId)", userAgent: userAgent)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError("resposta inválida do servidor")
        }
        var episodes: [Int: [Episode]] = [:]
        func add(_ list: [Any]) {
            for (i, raw) in list.enumerated() {
                guard let e = raw as? [String: Any], let id = nonBlank(e["id"]) else { continue }
                let info = e["info"] as? [String: Any]
                let season = str(e["season"]).flatMap { Int($0) } ?? 0
                let ext = nonBlank(e["container_extension"]) ?? "mp4"
                episodes[season, default: []].append(Episode(
                    id: id,
                    season: season,
                    number: str(e["episode_num"]).flatMap { Int($0) } ?? (i + 1),
                    title: nonBlank(e["title"]) ?? "Episódio \(i + 1)",
                    url: "\(account.base)/series/\(user)/\(pass)/\(id).\(ext)",
                    plot: nonBlank(info?["plot"]),
                    duration: nonBlank(info?["duration"])
                ))
            }
        }
        // "episodes" costuma ser { "1": [...], "2": [...] }, mas alguns servidores mandam uma lista de listas.
        if let dict = root["episodes"] as? [String: Any] {
            dict.values.compactMap { $0 as? [Any] }.forEach(add)
        } else if let list = root["episodes"] as? [Any] {
            list.compactMap { $0 as? [Any] }.forEach(add)
        }
        let sorted = episodes.mapValues { $0.sorted { $0.number < $1.number } }
        return SeriesInfo(seasons: sorted.keys.sorted(), episodes: sorted)
    }

    // EPG curto de um canal. Alguns painéis devolvem o JSON inteiro dentro de uma string base64.
    func shortEpg(_ streamId: String) async throws -> [Programme] {
        let data = try await Http.data("\(api)&action=get_short_epg&stream_id=\(streamId)&limit=30", userAgent: userAgent)
        var json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        if let s = json as? String, let inner = decodeBase64(s).data(using: .utf8) {
            json = try JSONSerialization.jsonObject(with: inner)
        }
        guard let root = json as? [String: Any], let listings = root["epg_listings"] as? [[String: Any]] else { return [] }
        return listings.compactMap { l -> Programme? in
            guard let start = str(l["start_timestamp"]).flatMap({ Int64($0) }),
                  let stop = str(l["stop_timestamp"]).flatMap({ Int64($0) }) else { return nil }
            let title = decodeBase64(str(l["title"]) ?? "")
            let desc = decodeBase64(str(l["description"]) ?? "")
            return Programme(start: start * 1000, stop: stop * 1000,
                             title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "Sem título" : title,
                             description: desc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : desc)
        }.sorted { $0.start < $1.start }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func cached(_ action: String, force: Bool) async throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(action).json")
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if force || size == 0 {
            try await Http.download("\(api)&action=\(action)", userAgent: userAgent, to: file)
        }
        return file
    }

    // Sem conteúdo, alguns servidores mandam {} em vez de [] — só o array interessa.
    private func array(_ action: String, force: Bool) async throws -> [[String: Any]] {
        let file = try await cached(action, force: force)
        let data = try Data(contentsOf: file)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func categoryList(_ action: String, force: Bool) async throws -> [VodCategory] {
        try await array(action, force: force).compactMap { o in
            guard let id = str(o["category_id"]) else { return nil }
            return VodCategory(id: id, name: str(o["category_name"])?.trimmingCharacters(in: .whitespaces) ?? "")
        }
    }
}
