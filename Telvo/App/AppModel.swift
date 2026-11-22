import Foundation
import Observation

enum Section: String, CaseIterable, Identifiable {
    case live = "TV"
    case series = "Séries"
    case movies = "Filmes"
    var id: Self { self }
}

/// Filtro único da lista de canais: substitui as abas Todos/Grupos/Favoritos.
enum LiveFilter: Hashable {
    case all, favorites
    case group(String)
}

enum Screen: Equatable {
    case hub              // Início: TV, Séries, Filmes, Configurações
    case section          // dentro de TV, Séries ou Filmes
    case settings         // listas
    case form(editing: Playlist?)
}

/// Teclas que o app trata em qualquer tela (monitor global em TelvoApp).
enum AppKey {
    case up, down, left, right, space, enter, escape, fullscreen, next, previous, volumeUp, volumeDown, mute
}

struct PlaylistForm {
    var name = ""
    var url = ""
    var epgUrl = ""
    var userAgent = ""
    var autoUpdate = false
}

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let store = Store()
    @ObservationIgnored private var xtream: Xtream?
    @ObservationIgnored private var byGroup: [String: [Channel]] = [:]
    @ObservationIgnored private var m3uEpgUrl: String?
    @ObservationIgnored private var playingList: [Channel] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var epgTask: Task<Void, Never>?
    @ObservationIgnored private var shortEpgTask: Task<Void, Never>?
    @ObservationIgnored private var vodTask: Task<Void, Never>?
    @ObservationIgnored private var moviesLoaded = false
    @ObservationIgnored private var seriesLoaded = false
    @ObservationIgnored private var clock: Timer?
    /// A tela do player ativo registra aqui o que fazer com cada tecla.
    @ObservationIgnored var keyHandler: ((AppKey) -> Bool)?

    var playlists: [Playlist] = []
    private(set) var screen: Screen = .hub
    private(set) var current: Playlist?
    private(set) var channels: [Channel] = []
    private(set) var groups: [String] = []
    private(set) var favorites: Set<String> = []
    private(set) var epg = Epg.empty
    private(set) var shortEpg: [String: [Programme]] = [:]
    private(set) var epgLoading = false
    private(set) var loading = false
    private(set) var progress: String?
    var error: String?
    private(set) var notice: String?

    // Ao vivo
    private(set) var section: Section = .live
    var filter: LiveFilter = .all
    var query = ""
    private(set) var playing: Channel?
    private(set) var playingNumber = 0
    var fullscreen = false
    var showEpg = true
    private(set) var now = nowMs()

    // Filmes e séries
    private(set) var movieCategories: [VodCategory] = []
    private(set) var movies: [VodItem] = []
    private(set) var seriesCategories: [VodCategory] = []
    private(set) var seriesList: [VodItem] = []
    private(set) var vodLoading = false
    var vodCategory: String?
    var vodQuery = ""
    private(set) var openSeries: VodItem?
    private(set) var seriesInfo: SeriesInfo?
    var season = 1
    private(set) var vodPlayback: VodPlayback?
    private(set) var recents: [WatchProgress] = []
    private(set) var resumePrompt: ResumePrompt?

    var epgUrl: String? { current?.epgUrl ?? m3uEpgUrl }
    var hasEpg: Bool { epgUrl != nil || xtream != nil }
    var hasVod: Bool { xtream != nil || !movies.isEmpty || !seriesList.isEmpty }

    init() {
        playlists = store.playlists()
        favorites = store.favorites
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = nowMs() }
        }
        if let id = store.lastPlaylistId, let p = playlists.first(where: { $0.id == id }) { open(p) } else { screen = .settings }
    }

    // MARK: - Ao vivo

    func visibleChannels() -> [Channel] {
        let q = normalize(query)
        // Buscando, procura em todos os canais.
        let base: [Channel]
        if !q.isEmpty { base = channels } else {
            switch filter {
            case .all: base = channels
            case .favorites: base = channels.filter { favorites.contains($0.url) }
            case .group(let g): base = byGroup[g] ?? []
            }
        }
        return q.isEmpty ? base : base.filter { normalize($0.name).contains(q) }
    }

    func groupSize(_ name: String) -> Int { byGroup[name]?.count ?? 0 }
    var favoritesCount: Int { channels.filter { favorites.contains($0.url) }.count }

    var filterTitle: String {
        switch filter {
        case .all: return "Todos os canais"
        case .favorites: return "Favoritos"
        case .group(let g): return g
        }
    }

    func programmes(_ channel: Channel) -> [Programme] {
        let list = epg.programmes(channel)
        return list.isEmpty ? shortEpg[channel.url] ?? [] : list
    }

    func nowFor(_ channel: Channel) -> Programme? { programmes(channel).first { now >= $0.start && now < $0.stop } }
    func nextFor(_ channel: Channel) -> Programme? { programmes(channel).first { $0.start >= now } }

    // Clique num canal novo toca na prévia; no que já está tocando abre a tela cheia.
    func select(_ list: [Channel], _ index: Int) {
        if list[index].url == playing?.url { fullscreen = true } else { setPlaying(list, index) }
    }

    func zap(_ delta: Int) {
        guard let index = playingList.firstIndex(where: { $0.url == playing?.url }) else { return }
        setPlaying(playingList, index + delta)
    }

    func toggleFavorite(_ channel: Channel) {
        if favorites.contains(channel.url) { favorites.remove(channel.url) } else { favorites.insert(channel.url) }
        store.favorites = favorites
    }

    // MARK: - Seções, filmes e séries

    func openSection(_ s: Section) {
        screen = .section
        guard section != s else { return }
        section = s
        vodCategory = nil
        vodQuery = ""
        openSeries = nil
        guard let xt = xtream else { return }
        if s == .movies && !moviesLoaded {
            loadVod(.movies) { [weak self] in
                let (cats, items) = try await xt.movies(force: false)
                self?.movieCategories = cats
                self?.movies = items
                self?.moviesLoaded = true
            }
        } else if s == .series && !seriesLoaded {
            loadVod(.series) { [weak self] in
                let (cats, items) = try await xt.series(force: false)
                self?.seriesCategories = cats
                self?.seriesList = items
                self?.seriesLoaded = true
            }
        }
    }

    func vodCategories(for s: Section) -> [VodCategory] { s == .movies ? movieCategories : seriesCategories }

    func vodItems() -> [VodItem] {
        let q = normalize(vodQuery)
        let base = section == .movies ? movies : seriesList
        let inCategory = vodCategory.map { id in base.filter { $0.categoryId == id } } ?? base
        return q.isEmpty ? inCategory : inCategory.filter { normalize($0.name).contains(q) }
    }

    func vodCounts() -> [String: Int] {
        Dictionary(grouping: section == .movies ? movies : seriesList, by: \.categoryId).mapValues(\.count)
    }

    func openVod(_ item: VodItem) {
        if let url = item.url {
            startPlayback([Playable(title: item.name, subtitle: item.year ?? item.genre, url: url, poster: item.poster)], 0)
            return
        }
        guard let xt = xtream else { return }
        openSeries = item
        seriesInfo = nil
        vodTask?.cancel()
        vodTask = Task {
            vodLoading = true
            defer { vodLoading = false }
            do {
                let info = try await xt.seriesInfo(item.id)
                guard !Task.isCancelled else { return }
                seriesInfo = info
                season = info.seasons.first { $0 > 0 } ?? info.seasons.first ?? 1
            } catch {
                if !Task.isCancelled { self.error = "Não consegui abrir a série: \(describe(error))" }
            }
        }
    }

    func closeSeries() { openSeries = nil }

    func playEpisode(_ episodes: [Episode], _ index: Int) {
        let queue = episodes.map { e in
            let title = e.title.components(separatedBy: " - ").last ?? e.title
            return Playable(title: "T\(e.season) E\(e.number) · \(title)", subtitle: openSeries?.name, url: e.url, poster: openSeries?.poster)
        }
        startPlayback(queue, index)
    }

    // MARK: - Recentes / continuar assistindo

    func openRecent(_ progress: WatchProgress) { startPlayback([progress.item], 0) }

    func removeRecent(_ progress: WatchProgress) { updateRecents(recents.filter { $0.item.url != progress.item.url }) }

    func resume(fromStart: Bool) {
        guard let prompt = resumePrompt else { return }
        resumePrompt = nil
        vodPlayback = VodPlayback(queue: prompt.queue, index: prompt.index, startMs: fromStart ? 0 : prompt.progress.position)
    }

    func cancelResume() { resumePrompt = nil }

    // Chamado pelo player a cada 15 s e ao sair. Abaixo de 15 s não vale guardar;
    // depois de 95% o filme conta como assistido e sai dos recentes.
    func saveProgress(_ item: Playable, position: Int64, duration: Int64) {
        guard duration > 0, position >= 15_000 else { return }
        let rest = recents.filter { $0.item.url != item.url }
        updateRecents(Double(position) >= Double(duration) * 0.95
            ? rest
            : [WatchProgress(item: item, position: position, duration: duration, updatedAt: nowMs())] + rest)
    }

    private func startPlayback(_ queue: [Playable], _ index: Int) {
        if let saved = recents.first(where: { $0.item.url == queue[index].url }) {
            resumePrompt = ResumePrompt(queue: queue, index: index, progress: saved)
        } else {
            vodPlayback = VodPlayback(queue: queue, index: index)
        }
    }

    private func updateRecents(_ list: [WatchProgress]) {
        guard let id = current?.id else { return }
        recents = Array(list.prefix(50))
        store.saveRecents(id, recents)
    }

    func nextVod(_ delta: Int) {
        guard var p = vodPlayback else { return }
        let i = p.index + delta
        guard p.queue.indices.contains(i) else { return }
        p.index = i
        p.startMs = 0
        vodPlayback = p
    }

    func closePlayer() { vodPlayback = nil }

    // MARK: - Listas

    func newPlaylist() { clearMessages(); screen = .form(editing: nil) }
    func edit(_ p: Playlist) { clearMessages(); screen = .form(editing: p) }
    func openSettings() { clearMessages(); screen = .settings }

    /// Volta para o Início (hub). Sem lista aberta, o Início é a tela de listas.
    func goHome() {
        fullscreen = false
        vodPlayback = nil
        resumePrompt = nil
        screen = current == nil ? .settings : .hub
    }

    func save(_ editing: Playlist?, _ form: PlaylistForm) {
        let url = form.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            error = "Informe a URL da lista"
            return
        }
        var p = editing ?? Playlist(id: UUID().uuidString, name: "", url: url, epgUrl: nil, userAgent: nil,
                                    autoUpdate: false, addedAt: nowMs(), updatedAt: 0, channelCount: 0)
        let name = form.name.trimmingCharacters(in: .whitespaces)
        p.name = name.isEmpty ? nameFromUrl(url) : name
        p.url = url
        p.epgUrl = form.epgUrl.trimmingCharacters(in: .whitespaces).nilIfEmpty
        p.userAgent = form.userAgent.trimmingCharacters(in: .whitespaces).nilIfEmpty
        p.autoUpdate = form.autoUpdate
        let target = p
        loadTask?.cancel()
        loadTask = Task {
            loading = true
            clearMessages()
            defer { loading = false; progress = nil }
            do {
                var saved = target
                let download = editing == nil || editing?.url != target.url || editing?.userAgent != target.userAgent
                if download {
                    if let xt = store.xtream(target) {
                        progress = "Conferindo a conta…"
                        try await xt.checkAccount()
                        xt.clearCache()
                    }
                    let count = try await loadLive(target, force: true, apply: false)
                    saved.channelCount = count
                    saved.updatedAt = nowMs()
                }
                upsert(saved)
                if editing == nil {
                    current = nil
                    open(saved)
                } else {
                    // Força recarregar na próxima vez que abrir.
                    if current?.id == saved.id { current = nil }
                    screen = .settings
                }
            } catch {
                if !Task.isCancelled { self.error = "Não consegui carregar a lista: \(describe(error))" }
            }
        }
    }

    func refresh(_ p: Playlist, quiet: Bool = false) {
        Task {
            if !quiet { loading = true; clearMessages() }
            defer { if !quiet { loading = false; progress = nil } }
            do {
                let isCurrent = current?.id == p.id
                store.xtream(p)?.clearCache()
                let count = try await loadLive(p, force: true, apply: isCurrent)
                var updated = p
                updated.channelCount = count
                updated.updatedAt = nowMs()
                upsert(updated)
                if isCurrent {
                    current = updated
                    loadEpg(updated, force: !quiet)
                    // Recarrega a seção de VOD aberta com os dados novos.
                    let open = section, where_ = screen
                    if open != .live {
                        section = .live
                        openSection(open)
                        screen = where_
                    }
                }
                if !quiet { notice = "\"\(p.name)\" atualizada: \(count) canais ao vivo" }
            } catch {
                if !quiet { self.error = "Não consegui atualizar: \(describe(error))" }
            }
        }
    }

    func delete(_ p: Playlist) {
        store.delete(p)
        playlists.removeAll { $0.id == p.id }
        store.savePlaylists(playlists)
        if store.lastPlaylistId == p.id { store.lastPlaylistId = nil }
        if current?.id == p.id {
            current = nil
            channels = []
            playing = nil
        }
    }

    func open(_ p: Playlist) {
        if current?.id == p.id && !channels.isEmpty {
            enterHub()
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            loading = true
            clearMessages()
            defer { loading = false; progress = nil }
            do {
                let count = try await loadLive(p, force: false, apply: true)
                var latest = p
                latest.channelCount = count
                if latest != p { upsert(latest) }
                current = latest
                store.lastPlaylistId = latest.id
                recents = store.recents(latest.id)
                section = .live
                let last = store.lastChannel(latest.id)
                if let index = channels.firstIndex(where: { $0.url == last }) { setPlaying(channels, index) } else { playing = nil }
                enterHub()
                loadEpg(latest, force: false)
                if latest.autoUpdate && latest.updatedAt > 0 { refresh(latest, quiet: true) }
            } catch {
                if !Task.isCancelled {
                    self.error = "Não consegui abrir a lista: \(describe(error))"
                    screen = .settings
                }
            }
        }
    }

    /// Esc: volta um nível, como o botão Voltar do controle no Android.
    func back() {
        if resumePrompt != nil { resumePrompt = nil }
        else if vodPlayback != nil { vodPlayback = nil }
        else if fullscreen { fullscreen = false }
        else if case .form = screen { screen = playlists.isEmpty ? .settings : .settings }
        else if screen == .settings { if current != nil { screen = .hub } }
        else if screen == .section {
            if openSeries != nil { openSeries = nil }
            else if section == .live && !query.isEmpty { query = "" }
            else if section != .live && !vodQuery.isEmpty { vodQuery = "" }
            else if section != .live && vodCategory != nil { vodCategory = nil }
            else { screen = .hub }
        }
    }

    // MARK: - Internos

    // Carrega os canais ao vivo: pela API se for Xtream, senão pelo M3U (cache ou download).
    private func loadLive(_ p: Playlist, force: Bool, apply: Bool) async throws -> Int {
        if let xt = store.xtream(p) {
            progress = "Baixando canais…"
            let live = try await xt.live(force: force)
            if apply {
                xtream = xt
                m3uEpgUrl = nil
                resetVod()
                applyLive(live)
            }
            return live.count
        }
        let store = self.store
        var m3u = force ? nil : store.loadCached(p)
        if m3u == nil {
            m3u = try await store.download(p) { bytes in
                Task { @MainActor [weak self] in self?.progress = "Baixando lista… \(bytes / 1_000_000) MB" }
            }
        }
        guard let m3u else { throw AppError("lista vazia") }
        if apply {
            xtream = nil
            m3uEpgUrl = m3u.epgUrl
            resetVod()
            applyM3U(m3u)
        }
        return m3u.channels.filter { $0.kind == .live }.count
    }

    private func applyLive(_ list: [Channel]) {
        channels = list
        byGroup = Dictionary(grouping: list, by: \.group)
        var seen = Set<String>()
        groups = list.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
        if !playingList.isEmpty { playingList = channels }
    }

    // Numa lista M3U comum, filmes e episódios soltos viram itens de VOD agrupados pelo group-title.
    private func applyM3U(_ m3u: M3U) {
        applyLive(m3u.channels.filter { $0.kind == .live })
        func vod(_ kind: Kind) -> ([VodCategory], [VodItem]) {
            let items = m3u.channels.filter { $0.kind == kind }.map {
                VodItem(id: $0.url, name: $0.name, poster: $0.logo, categoryId: $0.group, url: $0.url)
            }
            var seen = Set<String>()
            let cats = items.compactMap { seen.insert($0.categoryId).inserted ? VodCategory(id: $0.categoryId, name: $0.categoryId) : nil }
            return (cats, items)
        }
        (movieCategories, movies) = vod(.movie)
        (seriesCategories, seriesList) = vod(.series)
        moviesLoaded = true
        seriesLoaded = true
    }

    private func resetVod() {
        movieCategories = []; movies = []
        seriesCategories = []; seriesList = []
        moviesLoaded = false; seriesLoaded = false
        openSeries = nil; seriesInfo = nil
        shortEpg = [:]
    }

    private func loadVod(_ s: Section, _ block: @escaping @MainActor () async throws -> Void) {
        vodTask?.cancel()
        vodTask = Task {
            vodLoading = true
            progress = s == .movies ? "Baixando filmes…" : "Baixando séries…"
            defer { vodLoading = false; progress = nil }
            do {
                try await block()
            } catch {
                if !Task.isCancelled { self.error = "Não consegui carregar \(s.rawValue.lowercased()): \(describe(error))" }
            }
        }
    }

    private func enterHub() {
        query = ""
        fullscreen = false
        screen = .hub
    }

    private func setPlaying(_ list: [Channel], _ index: Int) {
        guard !list.isEmpty else { return }
        let i = ((index % list.count) + list.count) % list.count
        let channel = list[i]
        playingList = list
        playing = channel
        playingNumber = i + 1
        if let id = current?.id { store.setLastChannel(id, url: channel.url) }
        loadShortEpg(channel)
    }

    // Servidores Xtream sem xmltv.php: busca o guia do canal na hora em que ele toca.
    private func loadShortEpg(_ channel: Channel) {
        guard let xt = xtream, let id = channel.streamId else { return }
        if !epg.isEmpty && !epg.programmes(channel).isEmpty { return }
        if let known = shortEpg[channel.url], known.contains(where: { $0.stop > now }) { return }
        shortEpgTask?.cancel()
        shortEpgTask = Task {
            if let list = try? await xt.shortEpg(id), !Task.isCancelled { shortEpg[channel.url] = list }
        }
    }

    private func loadEpg(_ p: Playlist, force: Bool) {
        epgTask?.cancel()
        guard let url = p.epgUrl ?? m3uEpgUrl else {
            epg = .empty
            return
        }
        let store = self.store
        let channels = self.channels
        epgTask = Task {
            epgLoading = true
            defer { epgLoading = false }
            do {
                epg = try await Task.detached { try await store.loadEpg(p, url: url, channels: channels, force: force) }.value
            } catch {
                if !Task.isCancelled { self.error = "Não consegui carregar o guia: \(describe(error))" }
            }
        }
    }

    private func upsert(_ p: Playlist) {
        if let i = playlists.firstIndex(where: { $0.id == p.id }) { playlists[i] = p } else { playlists.append(p) }
        store.savePlaylists(playlists)
    }

    private func clearMessages() {
        error = nil
        notice = nil
    }

    private func nameFromUrl(_ url: String) -> String {
        let u = URL(string: url)
        let segment = u?.deletingPathExtension().lastPathComponent
        if let segment, !segment.isEmpty, segment != "/", segment != "get", segment != "player_api" { return segment }
        return u?.host ?? "Lista"
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
