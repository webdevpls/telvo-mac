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

struct HomeView: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                AppMark(size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Telvo").font(.system(size: 24, weight: .semibold)).foregroundStyle(C.heading)
                    Text("Escolha uma lista ou adicione uma nova pela URL").font(.system(size: 14)).foregroundStyle(C.body)
                }
                Spacer()
                Pill(active: true, action: vm.newPlaylist) {
                    Image(systemName: "plus")
                    Text("Adicionar por URL")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 22)
            .background(C.rail)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Listas")
                if vm.loading && vm.progress == nil {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Carregando…").font(.tSubtitle).foregroundStyle(C.body) }
                        .padding(.horizontal, 12)
                } else {
                    StatusLine().padding(.horizontal, 12)
                }
                if vm.playlists.isEmpty {
                    EmptyHome()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(vm.playlists) { PlaylistRow(playlist: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(C.shell)
    }
}

private struct EmptyHome: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.tv").font(.system(size: 44, weight: .light)).foregroundStyle(C.muted)
            Text("Nenhuma lista ainda").font(.tTitle).foregroundStyle(C.heading)
            Text("Cole a URL M3U ou Xtream (get.php) do seu provedor para começar.")
                .font(.tSubtitle).foregroundStyle(C.body)
            Pill("Adicionar por URL", active: true, action: vm.newPlaylist)
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            Pill("Atualizar", enabled: !vm.loading) { vm.refresh(playlist) }
            Pill("Editar") { vm.edit(playlist) }
            Pill("Excluir") { confirmDelete = true }
        }
        .confirmationDialog("Excluir \"\(playlist.name)\"?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive) { vm.delete(playlist) }
        } message: {
            Text("Os canais baixados, o guia e os recentes desta lista também serão apagados.")
        }
    }

    private var meta: String {
        let updated = playlist.updatedAt > 0 ? " · Atualizada \(dateTimeFormatter.string(from: date(playlist.updatedAt)))" : ""
        return "Canais: \(playlist.channelCount) · Adicionada em \(dateFormatter.string(from: date(playlist.addedAt)))\(updated)"
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
