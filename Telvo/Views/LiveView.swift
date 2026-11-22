import SwiftUI

/// Seletor Ao vivo | Filmes | Séries | Recentes no topo da coluna esquerda.
struct SectionPills: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        if vm.hasVod {
            HStack(spacing: 6) {
                ForEach(Section.allCases) { s in
                    Pill(s.rawValue, active: vm.section == s) { vm.openSection(s) }
                }
            }
            .padding(.bottom, 10)
        }
    }
}

// O player ao vivo só existe nesta seção: ao ir para Filmes/Séries ele é liberado,
// o que importa em contas com 1 conexão simultânea.
struct LiveView: View {
    @Environment(AppModel.self) private var vm
    @State private var player: VideoPlayer?

    var body: some View {
        HStack(spacing: 0) {
            if !vm.fullscreen {
                ChannelSidebar().frame(width: 300)
            }
            if let player {
                PlayerPane(player: player)
            } else {
                Color.black
            }
            if !vm.fullscreen && vm.showEpg && vm.hasEpg {
                EpgPanel().frame(width: 300)
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

// MARK: - Lista lateral (abas, busca, canais)

private struct ChannelSidebar: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let list = vm.visibleChannels()
        let showGroups = vm.tab == .groups && vm.group == nil && vm.query.trimmingCharacters(in: .whitespaces).isEmpty

        VStack(alignment: .leading, spacing: 0) {
            SectionPills()
            HStack(spacing: 6) {
                ForEach(SidebarTab.allCases) { t in
                    Pill(t.rawValue, active: vm.tab == t) { vm.tab = t }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 10)
            SearchField(placeholder: "Buscar canal", text: $vm.query)
                .padding(.bottom, 10)
            SectionLabel(text: {
                if showGroups { return "\(vm.groups.count) grupos" }
                if vm.tab == .groups, let g = vm.group { return g }
                return "\(list.count) canais"
            }())
            if showGroups {
                GroupList()
            } else {
                let header = vm.tab == .groups && vm.group != nil && vm.query.isEmpty
                ChannelList(list: list, showBack: header)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .background(C.rail)
    }
}

private struct GroupList: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(vm.groups, id: \.self) { g in
                    RowButton(radius: 8, action: { vm.showGroup(g) }) {
                        HStack {
                            Text(g).font(.tRow).lineLimit(1)
                            Spacer()
                            Text("\(vm.groupSize(g))").font(.system(size: 12)).foregroundStyle(C.muted)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                    }
                }
            }
        }
    }
}

private struct ChannelList: View {
    @Environment(AppModel.self) private var vm
    let list: [Channel]
    let showBack: Bool

    var body: some View {
        if list.isEmpty && !showBack {
            Text(vm.tab == .favorites
                 ? "Nenhum favorito ainda.\nClique com o botão direito num canal para favoritar."
                 : "Nenhum canal encontrado.")
                .font(.tSubtitle).foregroundStyle(C.body).padding(12)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if showBack {
                            RowButton(radius: 8, action: { vm.showGroup(nil) }) {
                                Label("Todos os grupos", systemImage: "chevron.left").font(.tRow)
                                    .padding(.horizontal, 12).frame(height: 38)
                            }
                        }
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
        RowButton(selected: selected, action: action) {
            HStack(spacing: 12) {
                ChannelLogo(channel: channel, number: number)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("\(number). \(channel.name)")
                            .font(.tChannel)
                            .foregroundStyle(selected ? C.selection : C.heading)
                            .lineLimit(1)
                        if vm.favorites.contains(channel.url) {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(C.selection)
                        }
                    }
                    if let now {
                        Text(now.title).font(.tMeta).foregroundStyle(C.body).lineLimit(1)
                        ProgressLine(value: now.progress(at: vm.now)).frame(width: 84)
                    }
                }
            }
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: 64)
        }
        .contextMenu {
            Button(vm.favorites.contains(channel.url) ? "Remover dos favoritos" : "Adicionar aos favoritos") {
                vm.toggleFavorite(channel)
            }
            Button("Copiar link do canal") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.url, forType: .string)
            }
        }
    }
}

// MARK: - Player

private struct PlayerPane: View {
    @Environment(AppModel.self) private var vm
    let player: VideoPlayer
    @State private var showInfo = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let channel = vm.playing
        let now = channel.flatMap { vm.nowFor($0) }
        VStack(spacing: 0) {
            if !vm.fullscreen { PlayerHeader(channel: channel, now: now) }
            ZStack(alignment: .bottomLeading) {
                VideoSurface(player: player)
                    .onTapGesture(count: 2) { vm.fullscreen.toggle() }
                    .onTapGesture { flashInfo() }
                overlay(channel: channel, now: now)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onContinuousHover { phase in if case .active = phase, vm.fullscreen { flashInfo() } }
            if !vm.fullscreen && channel != nil {
                HStack(spacing: 14) {
                    PlayPauseButton(player: player, size: 15)
                    VolumeControl(player: player, width: 100)
                    Spacer(minLength: 8)
                    Text("Espaço pausa · F tela cheia · ↑ ↓ canal · + − volume · Esc volta")
                        .font(.tMeta).foregroundStyle(C.muted).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(C.content)
            }
        }
        .onChange(of: channel?.url) { _, _ in flashInfo() }
        .onChange(of: vm.fullscreen) { _, _ in flashInfo() }
        .onAppear { vm.keyHandler = handle }
        .onDisappear { vm.keyHandler = nil }
    }

    private func handle(_ key: AppKey) -> Bool {
        switch key {
        case .up, .previous: vm.zap(-1); flashInfo()
        case .down, .next: vm.zap(1); flashInfo()
        case .fullscreen: vm.fullscreen.toggle()
        case .space:
            if player.error != nil { player.retry() } else { player.togglePause() }
            flashInfo()
        case .enter:
            if player.error != nil { player.retry() } else if vm.fullscreen { flashInfo() } else { vm.fullscreen = true }
        case .volumeUp: player.changeVolume(by: 5); flashInfo()
        case .volumeDown: player.changeVolume(by: -5); flashInfo()
        case .mute: player.toggleMute(); flashInfo()
        default: return false
        }
        return true
    }

    @ViewBuilder
    private func overlay(channel: Channel?, now: Programme?) -> some View {
        if channel == nil {
            Text("Escolha um canal na lista").font(.tSubtitle).foregroundStyle(C.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if player.paused && !(vm.fullscreen && showInfo) {
            VStack(spacing: 10) {
                Image(systemName: "pause.circle.fill").font(.system(size: 56)).foregroundStyle(.white.opacity(0.85))
                Text("Pausado · Espaço volta para o ao vivo").font(.tSubtitle).foregroundStyle(C.heading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.45))
            .onTapGesture { player.resume() }
        } else if let channel, vm.fullscreen && (showInfo || player.buffering || player.error != nil) {
            InfoOverlay(player: player, channel: channel, now: now, next: vm.nextFor(channel))
        } else if player.error != nil || player.buffering {
            HStack(spacing: 8) {
                if player.error == nil { ProgressView().controlSize(.small) }
                Text(player.error.map { "\($0) · Enter para tentar de novo" } ?? "Carregando…")
                    .font(.tSubtitle).foregroundStyle(player.error != nil ? C.live : C.body)
                if player.error != nil { Pill("Tentar de novo") { player.retry() } }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.8)))
            .padding(12)
        }
    }

    private func flashInfo() {
        showInfo = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { showInfo = false }
        }
    }
}

private struct PlayerHeader: View {
    @Environment(AppModel.self) private var vm
    let channel: Channel?
    let now: Programme?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(channel?.name ?? vm.current?.name ?? "")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                if let now {
                    Text(now.title).font(.system(size: 12)).foregroundStyle(C.body).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(C.widget))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                if let channel {
                    let fav = vm.favorites.contains(channel.url)
                    Pill(active: fav, action: { vm.toggleFavorite(channel) }) {
                        Image(systemName: fav ? "star.fill" : "star")
                    }
                    .help(fav ? "Remover dos favoritos" : "Favoritar")
                }
                Pill("Guia", active: vm.showEpg && vm.hasEpg, enabled: vm.hasEpg) { vm.showEpg.toggle() }
                Pill("Tela cheia", enabled: channel != nil) { vm.fullscreen = true }
                if let p = vm.current {
                    Pill(vm.loading ? "Atualizando…" : "Atualizar", enabled: !vm.loading) { vm.refresh(p) }
                }
                Pill("Listas", action: vm.goHome)
            }
            StatusLine()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.widgetHeader)
    }
}

private struct InfoOverlay: View {
    @Environment(AppModel.self) private var vm
    let player: VideoPlayer
    let channel: Channel
    let now: Programme?
    let next: Programme?

    var body: some View {
        HStack(spacing: 16) {
            ChannelLogo(channel: channel, number: vm.playingNumber, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("\(vm.playingNumber)").font(.system(size: 22, weight: .semibold)).foregroundStyle(C.selection)
                    Text(channel.name).font(.system(size: 22, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                }
                Text(channel.group).font(.tSubtitle).foregroundStyle(C.body)
                if let now {
                    HStack(spacing: 8) {
                        LiveTag()
                        Text(now.title).font(.tChannel).foregroundStyle(C.heading).lineLimit(1)
                    }
                    .padding(.top, 4)
                    HStack(spacing: 8) {
                        Text(formatTime(now.start)).font(.tMeta).foregroundStyle(C.body)
                        ProgressLine(value: now.progress(at: vm.now)).frame(width: 240)
                        Text(formatTime(now.stop)).font(.tMeta).foregroundStyle(C.body)
                    }
                }
                if let next {
                    Text("A seguir: \(next.title) às \(formatTime(next.start))").font(.system(size: 12)).foregroundStyle(C.body)
                }
                if let e = player.error {
                    Text("\(e) · Enter para tentar de novo").font(.tSubtitle).foregroundStyle(C.live)
                } else if player.paused {
                    Text("Pausado · Espaço volta para o ao vivo").font(.tSubtitle).foregroundStyle(C.selection)
                } else if player.buffering {
                    Text("Carregando…").font(.tSubtitle).foregroundStyle(C.body)
                }
                HStack(spacing: 14) {
                    PlayPauseButton(player: player, size: 16)
                    VolumeControl(player: player, width: 140)
                }
                .padding(.top, 6)
            }
        }
        .padding(20)
        .frame(maxWidth: 760, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(C.widget.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(C.separator))
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .transition(.opacity)
    }
}

// MARK: - Guia (EPG)

private let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "EEE, d 'de' MMM"
    return f
}()

private struct EpgPanel: View {
    @Environment(AppModel.self) private var vm
    @State private var dayOffset = 0

    var body: some View {
        let channel = vm.playing
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: Date()))!
        let all = channel.map { vm.programmes($0) } ?? []
        let programmes = all.filter { cal.isDate(Date(timeIntervalSince1970: Double($0.start) / 1000), inSameDayAs: day) }
        let now = channel.flatMap { vm.nowFor($0) }

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let channel { ChannelLogo(channel: channel, number: vm.playingNumber, size: 36) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel?.name ?? "Guia").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                    Text(now?.title ?? "Guia de programação").font(.system(size: 10)).foregroundStyle(C.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(C.widget)

            HStack {
                Pill(horizontalPadding: 10, action: { dayOffset -= 1 }) { Image(systemName: "chevron.left") }
                Spacer()
                Text(dayLabel(day)).font(.system(size: 13, weight: .medium)).foregroundStyle(C.heading)
                Spacer()
                Pill(horizontalPadding: 10, action: { dayOffset += 1 }) { Image(systemName: "chevron.right") }
            }
            .padding(2)
            .background(Capsule().fill(C.widgetHeader))
            .overlay(Capsule().strokeBorder(C.separator))
            .padding(.horizontal, 12).padding(.vertical, 10)

            if let empty = emptyText(channel: channel, all: all, day: programmes) {
                Text(empty).font(.tSubtitle).foregroundStyle(C.body).padding(18)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(programmes, id: \.start) { p in
                                ProgrammeRow(p: p, live: vm.now >= p.start && vm.now < p.stop, past: p.stop <= vm.now, now: vm.now)
                                    .id(p.start)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onAppear { if let now { proxy.scrollTo(now.start, anchor: .top) } }
                }
            }
        }
        .background(C.content)
        .onChange(of: channel?.url) { _, _ in dayOffset = 0 }
    }

    private func dayLabel(_ day: Date) -> String {
        switch dayOffset {
        case 0: return "Hoje"
        case 1: return "Amanhã"
        case -1: return "Ontem"
        default: return dayFormatter.string(from: day)
        }
    }

    private func emptyText(channel: Channel?, all: [Programme], day: [Programme]) -> String? {
        if vm.epgLoading && all.isEmpty { return "Carregando guia…" }
        if channel == nil { return "Escolha um canal" }
        if all.isEmpty { return "Sem programação para este canal" }
        if day.isEmpty { return "Sem programação neste dia" }
        return nil
    }
}

private struct ProgrammeRow: View {
    let p: Programme
    let live: Bool
    let past: Bool
    let now: Int64
    @State private var expanded = false

    var body: some View {
        RowButton(selected: live, radius: 10, action: { expanded.toggle() }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(formatTime(p.start)) – \(formatTime(p.stop))").font(.tMeta).foregroundStyle(C.muted)
                    if live { LiveTag() }
                }
                Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(C.heading).lineLimit(2)
                if live { ProgressLine(value: p.progress(at: now)).frame(width: 84) }
                if expanded, let d = p.description {
                    Text(d).font(.system(size: 12)).foregroundStyle(C.body).lineLimit(6)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .opacity(past && !expanded ? 0.55 : 1)
        .help(p.description ?? "")
    }
}
