import Foundation

enum Kind: String, Codable { case live, movie, series }

struct Channel: Hashable, Identifiable {
    var name: String
    var url: String
    var group: String
    var logo: String?
    var tvgId: String?
    var tvgName: String?
    var kind: Kind = .live
    // Só em listas Xtream: usado para buscar o EPG do canal na API.
    var streamId: String? = nil

    var id: String { url }
}

struct VodCategory: Hashable, Identifiable {
    let id: String
    let name: String
}

// Filme, série ou episódio solto de uma lista M3U. Sem url = série Xtream (episódios vêm da API).
struct VodItem: Hashable, Identifiable {
    let id: String
    let name: String
    let poster: String?
    let categoryId: String
    var rating: String? = nil
    var url: String? = nil
    var year: String? = nil
    var plot: String? = nil
    var genre: String? = nil
}

struct Episode: Hashable, Identifiable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let url: String
    let plot: String?
    let duration: String?
}

struct SeriesInfo {
    let seasons: [Int]
    let episodes: [Int: [Episode]]
}

struct Playable: Codable, Hashable {
    let title: String
    let subtitle: String?
    let url: String
    var poster: String? = nil
}

// O que está tocando no player de filmes/séries; a fila permite ir ao próximo episódio.
// startMs vale só para o primeiro item aberto (continuar de onde parou).
struct VodPlayback: Equatable {
    let queue: [Playable]
    var index: Int
    var startMs: Int64 = 0
    var current: Playable { queue[index] }
}

// Ponto em que o usuário parou um filme ou episódio (aba Recentes).
struct WatchProgress: Codable, Hashable, Identifiable {
    let item: Playable
    let position: Int64
    let duration: Int64
    let updatedAt: Int64
    var id: String { item.url }
}

// Pergunta "continuar ou começar do início" antes de abrir o player.
struct ResumePrompt: Equatable {
    let queue: [Playable]
    let index: Int
    let progress: WatchProgress
}

struct Playlist: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var url: String
    var epgUrl: String?
    var userAgent: String?
    var autoUpdate: Bool
    var addedAt: Int64
    var updatedAt: Int64
    var channelCount: Int
}

struct Programme: Hashable {
    let start: Int64
    let stop: Int64
    let title: String
    let description: String?

    func progress(at now: Int64) -> Double {
        let span = max(stop - start, 1)
        return min(max(Double(now - start) / Double(span), 0), 1)
    }
}

func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

// Usado na busca e para casar canais da lista com os do EPG.
func normalize(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

// "Filmes | Lançamentos 2025" -> "Lançamentos 2025"
func shortCategory(_ name: String) -> String {
    guard let bar = name.firstIndex(of: "|") else { return name }
    return name[name.index(after: bar)...].trimmingCharacters(in: .whitespaces)
}

func formatDuration(_ ms: Int64) -> String {
    guard ms > 0 else { return "0:00" }
    let total = ms / 1000
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

private let hourFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

func formatTime(_ ms: Int64) -> String {
    hourFormatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
}
