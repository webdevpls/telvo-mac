import SwiftUI

// O player ao vivo só existe nesta tela: ao sair ele é liberado,
// o que importa em contas com 1 conexão simultânea.
struct LiveView: View {
    @Environment(AppModel.self) private var vm
    @State private var player: VideoPlayer?

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            if !vm.fullscreen {
                TopBar(title: "TV", subtitle: vm.current?.name) {
                    SearchField(placeholder: "Buscar canal", text: $vm.query).frame(width: 260)
                }
            }
            HStack(spacing: 0) {
                if !vm.fullscreen {
                    ChannelColumn().frame(width: 330)
                }
                if let player {
                    PlayerArea(player: player)
                } else {
                    Color.black
                }
            }
        }
        .background(C.shell)
        .task(id: vm.current?.id) {
            player?.release()
            player = VideoPlayer(userAgent: vm.current?.userAgent ?? defaultUserAgent)
            if let c = vm.playing { player?.play(c.url) }
        }
        .onChange(of: vm.playing?.url) { _, url in
            if let url { player?.play(url) }
        }
        .onDisappear {
            player?.release()
            player = nil
        }
    }
}

// MARK: - Coluna de canais

private struct ChannelColumn: View {
    @Environment(AppModel.self) private var vm
    @State private var picking = false

    var body: some View {
        let list = vm.visibleChannels()
        let searching = !vm.query.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            // Um único seletor no lugar das abas Todos/Grupos/Favoritos.
            Button { picking.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon(vm.filter)).foregroundStyle(C.selection).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(searching ? "Resultados da busca" : vm.filterTitle)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                        Text("\(list.count) canais").font(.tMeta).foregroundStyle(C.body)
                    }
                    Spacer()
                    Image(systemName: picking ? "chevron.up" : "chevron.down").foregroundStyle(C.body).font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 12).fill(C.widget))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(picking ? C.selectionBorder : C.separator))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(searching)

            if picking && !searching {
                FilterList { picking = false }
            } else {
                ChannelList(list: list)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .background(C.rail)
        .onChange(of: vm.query) { _, q in if !q.isEmpty { picking = false } }
    }

    private func icon(_ f: LiveFilter) -> String {
        switch f {
        case .all: return "square.grid.2x2"
        case .favorites: return "star.fill"
        case .group: return "folder"
        }
    }
}

private struct FilterList: View {
    @Environment(AppModel.self) private var vm
    let done: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                row("Todos os canais", count: vm.channels.count, icon: "square.grid.2x2", filter: .all)
                row("Favoritos", count: vm.favoritesCount, icon: "star.fill", filter: .favorites)
                Divider().overlay(C.separator).padding(.vertical, 6)
                ForEach(vm.groups, id: \.self) { g in
                    row(g, count: vm.groupSize(g), icon: nil, filter: .group(g))
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func row(_ title: String, count: Int, icon: String?, filter: LiveFilter) -> some View {
        RowButton(selected: vm.filter == filter, radius: 8, action: {
            vm.filter = filter
            done()
        }) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).frame(width: 16) }
                Text(title).font(.tRow).lineLimit(1)
                Spacer()
                Text("\(count)").font(.system(size: 12)).foregroundStyle(C.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
        }
    }
}

private struct ChannelList: View {
    @Environment(AppModel.self) private var vm
    let list: [Channel]

    var body: some View {
        if list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.filter == .favorites && vm.query.isEmpty ? "Nenhum favorito ainda" : "Nenhum canal encontrado")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(C.heading)
                if vm.filter == .favorites && vm.query.isEmpty {
                    Text("Use a ★ no vídeo ou o botão direito num canal.").font(.tSubtitle).foregroundStyle(C.body)
                }
            }
            .padding(12)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.element.url) { i, c in
                            ChannelRow(channel: c, number: i + 1, selected: c.url == vm.playing?.url) { vm.select(list, i) }
                                .id(c.url)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .onAppear { if let url = vm.playing?.url { proxy.scrollTo(url, anchor: .center) } }
            }
        }
    }
}

private struct ChannelRow: View {
    @Environment(AppModel.self) private var vm
    let channel: Channel
    let number: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let now = vm.nowFor(channel)
        RowButton(selected: selected, radius: 10, action: action) {
            HStack(spacing: 12) {
                ChannelLogo(channel: channel, number: number, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(channel.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? C.selection : C.heading)
                            .lineLimit(1)
                        if vm.favorites.contains(channel.url) {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(C.star)
                        }
                    }
                    Text(now?.title ?? channel.group).font(.tMeta).foregroundStyle(C.body).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "speaker.wave.2.fill").font(.system(size: 11)).foregroundStyle(C.selection) }
            }
            .padding(.horizontal, 10)
            .frame(height: 56)
        }
        .contextMenu {
            Button(vm.favorites.contains(channel.url) ? "Remover dos favoritos" : "Adicionar aos favoritos") {
                vm.toggleFavorite(channel)
            }
        }
    }
}

// MARK: - Vídeo + Agora/A seguir

private struct PlayerArea: View {
    @Environment(AppModel.self) private var vm
    let player: VideoPlayer
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let channel = vm.playing
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                VideoSurface(player: player)
                    .onTapGesture(count: 2) { vm.fullscreen.toggle() }
                    .onTapGesture { poke() }
                centerMessage(channel)
                if channel != nil && (showControls || player.paused || player.error != nil) {
                    ControlsBar(player: player, channel: channel!, poke: poke)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: vm.fullscreen ? 0 : 14))
            .padding(vm.fullscreen ? 0 : 16)
            .onContinuousHover { phase in if case .active = phase { poke() } }
            .animation(.easeOut(duration: 0.2), value: showControls)

            if !vm.fullscreen, let channel {
                NowNextCard(channel: channel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: channel?.url) { _, _ in poke() }
        .onAppear { vm.keyHandler = handle }
        .onDisappear { vm.keyHandler = nil }
    }

    @ViewBuilder
    private func centerMessage(_ channel: Channel?) -> some View {
        if channel == nil {
            VStack(spacing: 10) {
                Image(systemName: "tv").font(.system(size: 40, weight: .light)).foregroundStyle(C.muted)
                Text("Escolha um canal na lista").font(.tSubtitle).foregroundStyle(C.body)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let e = player.error {
            VStack(spacing: 12) {
                Text(e).font(.system(size: 15, weight: .semibold)).foregroundStyle(C.live)
                Pill("Tentar de novo", active: true) { player.retry() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if player.paused {
            Button { player.resume() } label: {
                VStack(spacing: 10) {
                    Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.9))
                    Text("Pausado · clique para voltar ao ao vivo").font(.tSubtitle).foregroundStyle(C.heading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.45))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if player.buffering {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handle(_ key: AppKey) -> Bool {
        switch key {
        case .up, .previous: vm.zap(-1)
        case .down, .next: vm.zap(1)
        case .fullscreen, .enter: vm.fullscreen.toggle()
        case .space: if player.error != nil { player.retry() } else { player.togglePause() }
        case .volumeUp, .right: player.changeVolume(by: 5)
        case .volumeDown, .left: player.changeVolume(by: -5)
        case .mute: player.toggleMute()
        default: return false
        }
        poke()
        return true
    }

    private func poke() {
        showControls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { showControls = false }
        }
    }
}

/// Controles sobre o vídeo: pausa, volume, favorito e tela cheia.
private struct ControlsBar: View {
    @Environment(AppModel.self) private var vm
    let player: VideoPlayer
    let channel: Channel
    let poke: () -> Void

    var body: some View {
        let fav = vm.favorites.contains(channel.url)
        VStack(alignment: .leading, spacing: 10) {
            if vm.fullscreen {
                HStack(spacing: 12) {
                    ChannelLogo(channel: channel, number: vm.playingNumber, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(C.heading)
                        if let now = vm.nowFor(channel) {
                            HStack(spacing: 6) { LiveTag(); Text(now.title).font(.system(size: 13)).foregroundStyle(C.body).lineLimit(1) }
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                PlayPauseButton(player: player, size: 18, onAction: poke)
                VolumeControl(player: player, width: 120, onAction: poke)
                Spacer()
                iconButton(fav ? "star.fill" : "star", tint: fav ? C.star : C.heading, help: fav ? "Remover dos favoritos" : "Favoritar") {
                    vm.toggleFavorite(channel)
                }
                iconButton(vm.fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           tint: C.heading, help: "Tela cheia (F)") { vm.fullscreen.toggle() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
    }

    private func iconButton(_ name: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button { action(); poke() } label: {
            Image(systemName: name).font(.system(size: 16)).foregroundStyle(tint).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// "Agora / A seguir" embaixo do vídeo (substitui o painel do guia).
private struct NowNextCard: View {
    @Environment(AppModel.self) private var vm
    let channel: Channel

    var body: some View {
        let now = vm.nowFor(channel)
        let next = vm.nextFor(channel)
        HStack(spacing: 16) {
            ChannelLogo(channel: channel, number: vm.playingNumber, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                if let now {
                    HStack(spacing: 8) {
                        LiveTag()
                        Text(now.title).font(.system(size: 13, weight: .medium)).foregroundStyle(C.heading).lineLimit(1)
                        Text("\(formatTime(now.start)) – \(formatTime(now.stop))").font(.tMeta).foregroundStyle(C.muted)
                    }
                    ProgressLine(value: now.progress(at: vm.now)).frame(maxWidth: 360)
                } else {
                    Text(channel.group).font(.tSubtitle).foregroundStyle(C.body)
                }
            }
            Spacer(minLength: 12)
            if let next {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("A SEGUIR · \(formatTime(next.start))").font(.tLabel).tracking(0.6).foregroundStyle(C.muted)
                    Text(next.title).font(.system(size: 13)).foregroundStyle(C.body).lineLimit(1)
                }
                .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(C.widget))
    }
}
