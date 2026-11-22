import SwiftUI

// MARK: - Grade de filmes / séries

struct VodBrowser: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let items = vm.vodItems()
        let categories = vm.vodCategories(for: vm.section)
        let counts = vm.vodCounts()
        let noun = vm.section == .movies ? "filmes" : "séries"
        let total = vm.section == .movies ? vm.movies.count : vm.seriesList.count

        VStack(spacing: 0) {
        TopBar(title: vm.section.rawValue, subtitle: vm.current?.name) {
            SearchField(placeholder: "Buscar \(noun)", text: $vm.vodQuery).frame(width: 260)
        }
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "\(categories.count) categorias")
                ScrollView {
                    LazyVStack(spacing: 2) {
                        CategoryRow(name: "Todas", count: total, selected: vm.vodCategory == nil) { vm.vodCategory = nil }
                        ForEach(categories) { c in
                            CategoryRow(name: shortCategory(c.name), count: counts[c.id] ?? 0, selected: vm.vodCategory == c.id) {
                                vm.vodCategory = c.id
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .frame(width: 300)
            .background(C.rail)

            VStack(alignment: .leading, spacing: 4) {
                let title = vm.vodCategory.flatMap { id in categories.first { $0.id == id }.map { shortCategory($0.name) } }
                    ?? (vm.section == .movies ? "Todos os filmes" : "Todas as séries")
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                Text(items.count == 1 ? "1 título" : "\(items.count) títulos").font(.tSubtitle).foregroundStyle(C.body)
                if vm.vodLoading && items.isEmpty {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Carregando \(noun)…") }
                        .font(.tSubtitle).foregroundStyle(C.body).padding(.top, 24)
                    Spacer()
                } else if items.isEmpty {
                    Text("Nada encontrado.").font(.tSubtitle).foregroundStyle(C.body).padding(.top, 24)
                    Spacer()
                } else {
                    PosterGrid(items: items)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        }
        .background(C.shell)
    }
}

private struct CategoryRow: View {
    let name: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        RowButton(selected: selected, radius: 8, action: action) {
            HStack {
                Text(name).font(.tRow).lineLimit(1)
                Spacer()
                Text("\(count)").font(.system(size: 12)).foregroundStyle(C.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
        }
    }
}

private struct PosterGrid: View {
    @Environment(AppModel.self) private var vm
    let items: [VodItem]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 20)], spacing: 24) {
                ForEach(items) { item in
                    PosterCard(item: item) { vm.openVod(item) }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        }
        // Trocar de categoria volta ao topo.
        .id(vm.vodCategory ?? "all")
    }
}

private struct PosterCard: View {
    let item: VodItem
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                PosterView(title: item.name, poster: item.poster, rating: item.rating, hover: hover)
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hover ? C.heading : C.body)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Detalhe da série

struct SeriesDetail: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        if let series = vm.openSeries {
            let info = vm.seriesInfo
            let episodes = info?.episodes[vm.season] ?? []
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 16) {
                    Pill(action: vm.closeSeries) { Image(systemName: "chevron.left"); Text("Voltar") }
                    PosterView(title: series.name, poster: series.poster).frame(width: 240)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(series.name).font(.system(size: 28, weight: .semibold)).foregroundStyle(C.heading).lineLimit(2)
                    let meta = [series.year, series.genre, series.rating.map { "★ \($0)" }].compactMap { $0 }.joined(separator: "  ·  ")
                    if !meta.isEmpty { Text(meta).font(.system(size: 14)).foregroundStyle(C.body) }
                    if let plot = series.plot {
                        Text(plot).font(.system(size: 14)).foregroundStyle(C.body).lineSpacing(4).lineLimit(4).padding(.top, 6)
                    }
                    if let info {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(info.seasons, id: \.self) { s in
                                    Pill(s == 0 ? "Extras" : "Temporada \(s)", active: s == vm.season) { vm.season = s }
                                }
                            }
                        }
                        .padding(.top, 14)
                        SectionLabel(text: "\(episodes.count) episódios").padding(.top, 8)
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(episodes.enumerated()), id: \.element.id) { i, e in
                                    EpisodeRow(episode: e) { vm.playEpisode(episodes, i) }
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    } else {
                        HStack(spacing: 8) {
                            if vm.vodLoading { ProgressView().controlSize(.small) }
                            Text(vm.vodLoading ? "Carregando episódios…" : vm.error ?? "Sem episódios.")
                        }
                        .font(.tSubtitle).foregroundStyle(C.body).padding(.top, 18)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .top) {
                RemoteImage(url: series.poster, fill: true)
                    .frame(height: 420).clipped().opacity(0.12).blur(radius: 30)
            }
            .background(C.shell)
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        RowButton(action: action) {
            HStack(alignment: .top, spacing: 0) {
                Text("\(episode.number)").font(.tTitle).foregroundStyle(C.selection).frame(width: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title.components(separatedBy: " - ").last ?? episode.title)
                        .font(.tChannel).foregroundStyle(C.heading).lineLimit(1)
                    if let d = episode.duration { Text(d).font(.tMeta).foregroundStyle(C.body) }
                    if let plot = episode.plot {
                        Text(plot).font(.system(size: 12)).foregroundStyle(C.body).lineLimit(hover ? 4 : 1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").foregroundStyle(hover ? C.selection : .clear).padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onHover { hover = $0 }
    }
}

// MARK: - Player de filmes e episódios

struct VodPlayerView: View {
    @Environment(AppModel.self) private var vm
    let playback: VodPlayback
    @State private var player = VideoPlayer(userAgent: defaultUserAgent)
    @State private var loaded: Playable?
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing: Double?

    var body: some View {
        let item = playback.current
        ZStack(alignment: .bottom) {
            VideoSurface(player: player)
                .onTapGesture(count: 2) { NSApp.keyWindow?.toggleFullScreen(nil) }
                .onTapGesture { player.togglePause(); poke() }
            if showControls || !player.isPlaying || player.error != nil {
                controls(item)
                    .transition(.opacity)
            }
            VStack {
                HStack {
                    Pill(action: vm.closePlayer) { Image(systemName: "chevron.left"); Text("Voltar") }
                    Spacer()
                }
                Spacer()
            }
            .padding(20)
            .opacity(showControls || !player.isPlaying ? 1 : 0)
        }
        .background(Color.black)
        .onContinuousHover { phase in if case .active = phase { poke() } }
        .animation(.easeOut(duration: 0.2), value: showControls)
        .task(id: item.url) {
            // Trocou de episódio: guarda o anterior antes de carregar o próximo.
            save(loaded)
            let start = loaded == nil ? playback.startMs : 0
            player.play(item.url, startMs: start)
            loaded = item
            poke()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if player.isPlaying { save(item) }
            }
        }
        .onAppear { vm.keyHandler = handle }
        .onDisappear {
            vm.keyHandler = nil
            save(loaded)
            player.release()
        }
    }

    private func controls(_ item: Playable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = item.subtitle { Text(s).font(.system(size: 14)).foregroundStyle(C.body) }
            Text(item.title).font(.system(size: 24, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
            HStack(spacing: 14) {
                PlayPauseButton(player: player, size: 20, onAction: poke)
                Text(formatDuration(scrubbing.map { Int64($0) } ?? player.positionMs))
                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(C.heading)
                Slider(
                    value: Binding(
                        get: { scrubbing ?? Double(player.positionMs) },
                        set: { scrubbing = $0 }
                    ),
                    in: 0...Double(max(player.durationMs, 1)),
                    onEditingChanged: { editing in
                        if !editing, let target = scrubbing {
                            player.seek(to: Int64(target))
                            scrubbing = nil
                        }
                        poke()
                    }
                )
                .tint(C.selection)
                .disabled(player.durationMs <= 0)
                Text(formatDuration(player.durationMs)).font(.system(size: 13).monospacedDigit()).foregroundStyle(C.heading)
                VolumeControl(player: player, width: 110, onAction: poke)
                if playback.queue.count > 1 {
                    Button { vm.nextVod(-1) } label: { Image(systemName: "backward.end.fill") }
                        .buttonStyle(.plain).foregroundStyle(playback.index > 0 ? C.heading : C.muted)
                        .disabled(playback.index == 0)
                    Button { vm.nextVod(1) } label: { Image(systemName: "forward.end.fill") }
                        .buttonStyle(.plain).foregroundStyle(playback.index < playback.queue.count - 1 ? C.heading : C.muted)
                        .disabled(playback.index >= playback.queue.count - 1)
                }
            }
            Group {
                if let e = player.error {
                    HStack { Text("\(e)").foregroundStyle(C.live); Pill("Tentar de novo") { player.retry() } }
                } else if player.buffering {
                    HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Carregando…").foregroundStyle(C.body) }
                } else {
                    Text(hint).foregroundStyle(C.body)
                }
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 48)
        .padding(.top, 60)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
    }

    private var hint: String {
        var s = "Espaço pausa · ← → 10 s · ↑ ↓ volume · M mudo · clique duplo: tela cheia · Esc volta"
        if playback.queue.count > 1 { s += " · N/P episódio \(playback.index + 1) de \(playback.queue.count)" }
        return s
    }

    private func handle(_ key: AppKey) -> Bool {
        switch key {
        case .space, .enter:
            if player.error != nil { player.retry() } else { player.togglePause() }
        case .left: player.seek(by: -10_000)
        case .right: player.seek(by: 10_000)
        case .next: vm.nextVod(1)
        case .previous: vm.nextVod(-1)
        case .fullscreen: NSApp.keyWindow?.toggleFullScreen(nil)
        case .up, .volumeUp: player.changeVolume(by: 5)
        case .down, .volumeDown: player.changeVolume(by: -5)
        case .mute: player.toggleMute()
        default: return false
        }
        poke()
        return true
    }

    private func save(_ target: Playable?) {
        guard let target, player.durationMs > 0 else { return }
        vm.saveProgress(target, position: player.positionMs, duration: player.durationMs)
    }

    private func poke() {
        showControls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && player.isPlaying && scrubbing == nil { showControls = false }
        }
    }
}

// MARK: - Continuar ou começar do início

struct ResumeView: View {
    @Environment(AppModel.self) private var vm
    let prompt: ResumePrompt

    var body: some View {
        let progress = prompt.progress
        let item = prompt.queue[prompt.index]
        ZStack {
            C.shell
            RemoteImage(url: item.poster, fill: true).opacity(0.18).blur(radius: 20).clipped()
            HStack(spacing: 40) {
                PosterView(title: item.title, poster: item.poster).frame(width: 220)
                VStack(alignment: .leading, spacing: 8) {
                    if let s = item.subtitle { Text(s).font(.system(size: 15)).foregroundStyle(C.body) }
                    Text(item.title).font(.system(size: 28, weight: .semibold)).foregroundStyle(C.heading).lineLimit(2)
                    Text("Você parou em \(formatDuration(progress.position)) de \(formatDuration(progress.duration))")
                        .font(.system(size: 15)).foregroundStyle(C.body)
                    ProgressLine(value: Double(progress.position) / Double(max(progress.duration, 1))).frame(width: 420)
                    HStack(spacing: 12) {
                        Pill(active: true, action: { vm.resume(fromStart: false) }) {
                            Image(systemName: "play.fill")
                            Text("Continuar de \(formatDuration(progress.position))")
                        }
                        .keyboardShortcut(.defaultAction)
                        Pill(action: { vm.resume(fromStart: true) }) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Começar do início")
                        }
                        Pill("Cancelar", action: vm.cancelResume)
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
