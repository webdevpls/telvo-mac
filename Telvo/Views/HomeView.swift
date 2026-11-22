import SwiftUI

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "dd/MM/yyyy"
    return f
}()

private let dateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "dd/MM 'às' HH:mm"
    return f
}()

private func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

/// Barra do topo de todas as telas internas: ← Início, título e (opcional) busca.
struct TopBar<Trailing: View>: View {
    @Environment(AppModel.self) private var vm
    let title: String
    var subtitle: String? = nil
    var showBack = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                if let subtitle { Text(subtitle).font(.tSubtitle).foregroundStyle(C.body).lineLimit(1) }
            }
            Spacer(minLength: 12)
            StatusLine()
            trailing()
        }
        .padding(.leading, 8)
        .padding(.trailing, 24)
        .padding(.top, 28)
        .padding(.bottom, 14)
    }
}

extension TopBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showBack: Bool = true) {
        self.init(title: title, subtitle: subtitle, showBack: showBack) { EmptyView() }
    }
}

// MARK: - Início

private let clockFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private let longDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "EEEE, d 'de' MMMM"
    return f
}()

struct HubView: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppMark(size: 34)
                Text("Telvo").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                if let name = vm.current?.name {
                    Text(name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.45)).padding(.leading, 4)
                }
                Spacer()
                StatusLine()
            }
            .padding(.top, 44)

            Spacer(minLength: 24)

            HStack(alignment: .center, spacing: 40) {
                HStack(alignment: .bottom, spacing: 22) {
                    HubCard(title: "TV ao vivo", subtitle: "\(vm.channels.count) canais", icon: "tv", badge: "Ao vivo") {
                        vm.openSection(.live)
                    }
                    .keyboardShortcut("1", modifiers: [])
                    HubCard(title: "Séries", subtitle: vm.seriesList.isEmpty ? "Temporadas e episódios" : "\(vm.seriesList.count) séries",
                            icon: "rectangle.stack", badge: "Séries") { vm.openSection(.series) }
                        .keyboardShortcut("2", modifiers: [])
                        .disabled(!vm.hasVod)
                    HubCard(title: "Filmes", subtitle: vm.movies.isEmpty ? "Catálogo completo" : "\(vm.movies.count) filmes",
                            icon: "film", badge: "Filmes") { vm.openSection(.movies) }
                        .keyboardShortcut("3", modifiers: [])
                        .disabled(!vm.hasVod)
                }
                Spacer(minLength: 0)
                ClockView()
            }

            if !vm.recents.isEmpty {
                ContinueRow().padding(.top, 44)
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Relógio grande com a data, à direita do Início.
private struct ClockView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .center, spacing: 4) {
                Text(clockFormatter.string(from: context.date))
                    .font(.system(size: 104, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(longDateFormatter.string(from: context.date).capitalized(with: Locale(identifier: "pt_BR")))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// Cartão alto de vidro. Tamanho fixo (o hover só escala, sem empurrar os vizinhos):
/// acende o azul, mostra o selo e o traço embaixo.
private struct HubCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let badge: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)],
                            startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [C.accent.opacity(0.85), Color(hex: 0x1A2260).opacity(0.9), Color(hex: 0x10121F)],
                            startPoint: .top, endPoint: .bottom))
                        .opacity(hover ? 1 : 0)
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(hover ? 0.24 : 0.08))
                    Text(badge)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(C.accent))
                        .padding(12)
                        .opacity(hover ? 1 : 0)
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white.opacity(0.9))
                        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .frame(width: 210, height: 290)
                .shadow(color: hover ? C.accent.opacity(0.45) : .clear, radius: 28, y: 12)
                .scaleEffect(hover ? 1.06 : 1, anchor: .bottom)
                // Traço azul embaixo do cartão em foco.
                RoundedRectangle(cornerRadius: 2).fill(C.accent).frame(width: 48, height: 4).opacity(hover ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .zIndex(hover ? 1 : 0)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.18), value: hover)
    }
}

/// Faixa "Continuar assistindo" no Início.
private struct ContinueRow: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continuar assistindo").font(.system(size: 15, weight: .semibold)).foregroundStyle(C.heading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(vm.recents.prefix(20)) { RecentTile(progress: $0) }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private struct RecentTile: View {
    @Environment(AppModel.self) private var vm
    let progress: WatchProgress
    @State private var hover = false

    var body: some View {
        let item = progress.item
        Button { vm.openRecent(progress) } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterView(title: item.title, poster: item.poster, hover: hover)
                    .overlay(alignment: .bottom) {
                        ProgressLine(value: Double(progress.position) / Double(max(progress.duration, 1)))
                            .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 10)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                    }
                Text(item.subtitle ?? item.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hover ? C.heading : C.body).lineLimit(1)
            }
            .frame(width: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu { Button("Tirar de Continuar assistindo", role: .destructive) { vm.removeRecent(progress) } }
    }
}

// MARK: - Configurações (listas)

struct SettingsView: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Configurações", subtitle: "Suas listas IPTV") {
                Pill(active: true, action: vm.newPlaylist) {
                    Image(systemName: "plus")
                    Text("Adicionar lista")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            if vm.playlists.isEmpty {
                EmptyHome()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.playlists) { PlaylistRow(playlist: $0) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
            }
        }
    }
}

private struct EmptyHome: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(spacing: 14) {
            AppMark(size: 64)
            Text("Bem-vindo ao Telvo").font(.system(size: 22, weight: .semibold)).foregroundStyle(C.heading)
            Text("Cole a URL M3U ou Xtream (get.php) do seu provedor para começar.")
                .font(.tSubtitle).foregroundStyle(C.body)
            Pill(active: true, action: vm.newPlaylist) {
                Image(systemName: "plus")
                Text("Adicionar lista")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlaylistRow: View {
    @Environment(AppModel.self) private var vm
    let playlist: Playlist
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 8) {
            RowButton(selected: playlist.id == vm.current?.id, action: { vm.open(playlist) }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(C.widget)
                        Text(xtreamAccount(playlist.url) != nil ? "XC" : "M3U").font(.tTag).foregroundStyle(C.providerM3u)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.name).font(.tChannel).foregroundStyle(C.heading).lineLimit(1)
                        Text(meta).font(.system(size: 12)).foregroundStyle(C.body).lineLimit(1)
                    }
                    Spacer()
                    if playlist.id == vm.current?.id {
                        Text("EM USO").font(.tTag).foregroundStyle(C.selection)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            Menu {
                Button("Atualizar agora") { vm.refresh(playlist) }.disabled(vm.loading)
                Button("Editar…") { vm.edit(playlist) }
                Divider()
                Button("Excluir…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(C.body).frame(width: 34, height: 34)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 40)
        }
        .confirmationDialog("Excluir \"\(playlist.name)\"?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive) { vm.delete(playlist) }
        } message: {
            Text("Os canais baixados, o guia e os recentes desta lista também serão apagados.")
        }
    }

    private var meta: String {
        let updated = playlist.updatedAt > 0 ? " · Atualizada \(dateTimeFormatter.string(from: date(playlist.updatedAt)))" : ""
        return "\(playlist.channelCount) canais · Adicionada em \(dateFormatter.string(from: date(playlist.addedAt)))\(updated)"
    }
}

struct FormView: View {
    @Environment(AppModel.self) private var vm
    let editing: Playlist?
    @State private var form = PlaylistForm()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editing == nil ? "Adicionar lista por URL" : "Configurações da lista")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(C.heading)
                    Text("Listas M3U/M3U8 ou Xtream (get.php). O guia (EPG) aceita XMLTV, inclusive .xml.gz.")
                        .font(.tSubtitle).foregroundStyle(C.body)
                }
                field("URL da lista", "http://servidor/get.php?username=…&password=…", $form.url)
                field("Nome", "Se vazio, usa o nome do arquivo", $form.name)
                field("URL do guia EPG · opcional", "Se vazio, usa o url-tvg da própria lista", $form.epgUrl)
                field("User-Agent · opcional", defaultUserAgent, $form.userAgent)
                Toggle(isOn: $form.autoUpdate) {
                    Text("Atualizar a lista sempre que abrir").font(.tRow).foregroundStyle(C.body)
                }
                .toggleStyle(.switch)
                .tint(C.selection)
                .frame(width: 640, alignment: .leading)
                HStack(spacing: 12) {
                    Pill(active: true, enabled: !vm.loading, action: save) {
                        if vm.loading { ProgressView().controlSize(.mini) }
                        Text(vm.loading ? (vm.progress ?? "Baixando lista…") : "Salvar")
                    }
                    .keyboardShortcut(.defaultAction)
                    Pill("Cancelar", action: vm.back)
                }
                if let e = vm.error { Text(e).font(.tSubtitle).foregroundStyle(C.live) }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if let p = editing {
                form = PlaylistForm(name: p.name, url: p.url, epgUrl: p.epgUrl ?? "", userAgent: p.userAgent ?? "", autoUpdate: p.autoUpdate)
            }
        }
    }

    private func save() { vm.save(editing, form) }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.tLabel).tracking(0.8).foregroundStyle(C.muted)
            SearchField(placeholder: placeholder, text: text, icon: false, onSubmit: save)
                .frame(width: 640)
        }
    }
}

/// Marca do app: o mesmo "play" do ícone da TV.
struct AppMark: View {
    var size: CGFloat = 54
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(LinearGradient(colors: [C.selection, Color(hex: 0x4F7BD9)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Color(hex: 0x071225))
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
    }
}
