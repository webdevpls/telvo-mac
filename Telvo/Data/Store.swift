import Foundation

private let epgMaxAge: TimeInterval = 12 * 60 * 60

/// Guarda listas, favoritos e recentes no UserDefaults e os arquivos baixados em
/// ~/Library/Application Support/Telvo.
final class Store: @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    let dir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("Telvo/playlists", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func playlists() -> [Playlist] {
        guard let data = defaults.data(forKey: "playlists") else { return [] }
        return (try? decoder.decode([Playlist].self, from: data)) ?? []
    }

    func savePlaylists(_ list: [Playlist]) {
        defaults.set(try? encoder.encode(list), forKey: "playlists")
    }

    // Favoritos são globais, valem para todas as listas.
    var favorites: Set<String> {
        get { Set(defaults.stringArray(forKey: "favorites") ?? []) }
        set { defaults.set(Array(newValue), forKey: "favorites") }
    }

    var lastPlaylistId: String? {
        get { defaults.string(forKey: "last_playlist") }
        set { defaults.set(newValue, forKey: "last_playlist") }
    }

    func lastChannel(_ playlistId: String) -> String? { defaults.string(forKey: "last_channel_\(playlistId)") }
    func setLastChannel(_ playlistId: String, url: String) { defaults.set(url, forKey: "last_channel_\(playlistId)") }

    // Recentes ficam por lista (as URLs dos filmes carregam o usuário/senha daquela conta).
    func recents(_ playlistId: String) -> [WatchProgress] {
        guard let data = defaults.data(forKey: "recent_\(playlistId)") else { return [] }
        return (try? decoder.decode([WatchProgress].self, from: data)) ?? []
    }

    func saveRecents(_ playlistId: String, _ list: [WatchProgress]) {
        defaults.set(try? encoder.encode(list), forKey: "recent_\(playlistId)")
    }

    func xtream(_ p: Playlist) -> Xtream? {
        xtreamAccount(p.url).map {
            Xtream(account: $0, userAgent: p.userAgent ?? defaultUserAgent, dir: dir.appendingPathComponent("\(p.id)-xtream"))
        }
    }

    func loadCached(_ p: Playlist) -> M3U? {
        guard let data = try? Data(contentsOf: m3uFile(p)) else { return nil }
        return parseM3U(String(decoding: gunzipIfNeeded(data), as: UTF8.self))
    }

    func download(_ p: Playlist, onProgress: @escaping (Int64) -> Void) async throws -> M3U {
        let tmp = dir.appendingPathComponent("\(p.id).m3u.download")
        try await Http.download(p.url, userAgent: p.userAgent ?? defaultUserAgent, to: tmp, onProgress: onProgress)
        let data = try Data(contentsOf: tmp)
        let m3u = parseM3U(String(decoding: gunzipIfNeeded(data), as: UTF8.self))
        guard !m3u.channels.isEmpty else {
            try? FileManager.default.removeItem(at: tmp)
            throw AppError("a lista não tem nenhum canal")
        }
        try? FileManager.default.removeItem(at: m3uFile(p))
        try FileManager.default.moveItem(at: tmp, to: m3uFile(p))
        return m3u
    }

    func loadEpg(_ p: Playlist, url: String, channels: [Channel], force: Bool) async throws -> Epg {
        let file = dir.appendingPathComponent("\(p.id).epg")
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? .distantPast
        let stale = Date().timeIntervalSince(modified) > epgMaxAge || defaults.string(forKey: "epg_url_\(p.id)") != url
        if force || stale {
            try await Http.download(url, userAgent: p.userAgent ?? defaultUserAgent, to: file)
            defaults.set(url, forKey: "epg_url_\(p.id)")
        }
        let data = gunzipIfNeeded(try Data(contentsOf: file))
        return XmltvParser(channels: channels).parse(data)
    }

    func delete(_ p: Playlist) {
        let fm = FileManager.default
        try? fm.removeItem(at: m3uFile(p))
        try? fm.removeItem(at: dir.appendingPathComponent("\(p.id).epg"))
        try? fm.removeItem(at: dir.appendingPathComponent("\(p.id)-xtream"))
        ["last_channel_", "epg_url_", "recent_"].forEach { defaults.removeObject(forKey: "\($0)\(p.id)") }
    }

    private func m3uFile(_ p: Playlist) -> URL { dir.appendingPathComponent("\(p.id).m3u") }
}
