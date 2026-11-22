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
            if showBack {
                Pill(horizontalPadding: 12, action: vm.goHome) {
                    Image(systemName: "chevron.left")
                    Text("Início")
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(C.heading).lineLimit(1)
                if let subtitle { Text(subtitle).font(.tSubtitle).foregroundStyle(C.body).lineLimit(1) }
            }
            Spacer(minLength: 12)
            StatusLine()
            trailing()
        }
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .background(C.rail)
    }
}

extension TopBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showBack: Bool = true) {
        self.init(title: title, subtitle: subtitle, showBack: showBack) { EmptyView() }
    }
}

// MARK: - Início

struct HubView: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                AppMark(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Telvo").font(.system(size: 22, weight: .semibold)).foregroundStyle(C.heading)
                    Text(vm.current?.name ?? "").font(.tSubtitle).foregroundStyle(C.body)
                }
                Spacer()
                StatusLine()
            }
            .padding(.horizontal, 48)
            .padding(.top, 36)

            Spacer(minLength: 24)

            HStack(spacing: 20) {
                HubCard(title: "TV", subtitle: "\(vm.channels.count) canais ao vivo", icon: "tv", tint: C.selection) {
                    vm.openSection(.live)
                }
                .keyboardShortcut("1", modifiers: [])
                HubCard(title: "Séries", subtitle: vm.seriesList.isEmpty ? "Temporadas e episódios" : "\(vm.seriesList.count) séries",
                        icon: "rectangle.stack", tint: Color(hex: 0xC084FC)) { vm.openSection(.series) }
                    .keyboardShortcut("2", modifiers: [])
                    .disabled(!vm.hasVod)
                HubCard(title: "Filmes", subtitle: vm.movies.isEmpty ? "Catálogo completo" : "\(vm.movies.count) filmes",
                        icon: "film", tint: Color(hex: 0xFBBF24)) { vm.openSection(.movies) }
                    .keyboardShortcut("3", modifiers: [])
                    .disabled(!vm.hasVod)
                HubCard(title: "Configurações", subtitle: "Listas e conta", icon: "gearshape", tint: C.body) {
                    vm.openSettings()
                }
                .keyboardShortcut("4", modifiers: [])
            }
            .padding(.horizontal, 48)

            if !vm.recents.isEmpty {
                ContinueRow().padding(.top, 36)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(C.shell)
    }
}

private struct HubCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(tint)
                Spacer()
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(C.heading)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(C.body).lineLimit(1).padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 240, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [tint.opacity(hover ? 0.22 : 0.12), C.widget], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(hover ? C.focusRing : C.separator, lineWidth: hover ? 2 : 1))
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
    }
}

/// Faixa "Continuar assistindo" no Início.
private struct ContinueRow: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continuar assistindo").font(.system(size: 15, weight: .semibold)).foregroundStyle(C.heading)
                .padding(.horizontal, 48)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(vm.recents.prefix(20)) { RecentTile(progress: $0) }
                }
                .padding(.horizontal, 48)
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
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
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
            TopBar(title: "Configurações", subtitle: "Suas listas IPTV", showBack: vm.current != nil) {
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
        .background(C.shell)
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
                        RoundedRectangle(cornerRadius: 10).fill(C.widget)
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
        .background(C.shell)
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
