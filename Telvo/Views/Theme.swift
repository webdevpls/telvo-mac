import AppKit
import SwiftUI

// Mesmos tokens do app de TV (tema escuro do IPTVnator).
enum C {
    static let shell = Color(hex: 0x0D0F12)
    static let rail = Color(hex: 0x111318)
    static let content = Color(hex: 0x161A22)
    static let widget = Color(hex: 0x1E2330)
    static let widgetHeader = Color(hex: 0x232840)
    static let cardHover = Color(hex: 0x252B3A)
    static let heading = Color(hex: 0xD8DCE8)
    static let body = Color(hex: 0x8B93A8)
    static let muted = Color(hex: 0x5C6478)
    static let selection = Color(hex: 0x78ADFF)
    static let selectionSurface = selection.opacity(0.18)
    static let selectionBorder = selection.opacity(0.62)
    static let focusRing = Color(hex: 0x8CBAFF)
    static let live = Color(hex: 0xFF8F8F)
    static let success = Color(hex: 0x4ADE80)
    static let separator = Color.white.opacity(0.14)
    static let searchBg = Color.white.opacity(0.05)
    static let searchBorder = Color.white.opacity(0.09)
    static let providerM3u = Color(hex: 0xF59E0B)
    static let star = Color(hex: 0xFBBF24)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    static let tTitle = Font.system(size: 18, weight: .semibold)
    static let tSubtitle = Font.system(size: 13)
    static let tLabel = Font.system(size: 11, weight: .semibold)
    static let tRow = Font.system(size: 14)
    static let tChannel = Font.system(size: 15, weight: .semibold)
    static let tMeta = Font.system(size: 11)
    static let tTag = Font.system(size: 9.5, weight: .bold)
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.tLabel)
            .tracking(0.8)
            .foregroundStyle(C.muted)
            .lineLimit(1)
            .padding(.leading, 12)
            .padding(.bottom, 6)
    }
}

/// Linha clicável no estilo das listas do IPTVnator: transparente, tinta azul quando
/// selecionada e realce no hover do mouse.
struct RowButton<Content: View>: View {
    var selected = false
    var radius: CGFloat = 12
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? C.selection : (hover ? C.heading : C.body))
        .background(
            RoundedRectangle(cornerRadius: radius)
                .fill(selected ? (hover ? C.selection.opacity(0.28) : C.selectionSurface) : (hover ? C.cardHover : .clear))
        )
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(selected ? C.selectionBorder : .clear, lineWidth: 1))
        .onHover { hover = $0 }
    }
}

/// Botão "pílula" usado nos cabeçalhos.
struct Pill<Content: View>: View {
    var active = false
    var enabled = true
    var horizontalPadding: CGFloat = 14
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { content() }
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, horizontalPadding)
                .frame(height: 30)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(!enabled ? C.muted : active ? C.selection : (hover ? C.heading : C.body))
        .background(Capsule().fill(!enabled ? C.widgetHeader.opacity(0.5) : active ? C.selectionSurface : (hover ? C.cardHover : C.widgetHeader)))
        .overlay(Capsule().strokeBorder(active ? C.selectionBorder : C.separator, lineWidth: 1))
        .onHover { hover = $0 }
    }
}

extension Pill where Content == Text {
    init(_ title: String, active: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.init(active: active, enabled: enabled, action: action) { Text(title) }
    }
}

/// Campo de texto no estilo da busca do IPTVnator (fundo 5%, borda 9%, anel azul no foco).
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var icon = true
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if icon { Image(systemName: "magnifyingglass").foregroundStyle(C.muted).font(.system(size: 12)) }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(C.muted))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(C.heading)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(C.searchBg))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? C.focusRing : C.searchBorder, lineWidth: focused ? 2 : 1))
    }
}

struct ProgressLine: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(C.separator)
                RoundedRectangle(cornerRadius: 2).fill(C.selection).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

struct LiveTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(C.live).frame(width: 6, height: 6)
            Text("AO VIVO").font(.tTag).tracking(0.6).foregroundStyle(C.live)
        }
    }
}

// MARK: - Imagens com cache em memória (logos e capas)

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init() { cache.countLimit = 600 }

    func image(for url: String) -> NSImage? { cache.object(forKey: url as NSString) }

    func load(_ url: String) async -> NSImage? {
        if let hit = image(for: url) { return hit }
        if let task = inFlight[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let u = URL(string: url) else { return nil }
            var req = URLRequest(url: u, timeoutInterval: 20)
            req.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSString) }
        return image
    }
}

struct RemoteImage: View {
    let url: String?
    var fill = false
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ImageCache.shared.image(for: url)
            if image == nil { image = await ImageCache.shared.load(url) }
        }
    }
}

struct ChannelLogo: View {
    let channel: Channel
    let number: Int
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(C.widget)
            if channel.logo != nil {
                RemoteImage(url: channel.logo).padding(6)
            } else {
                Text("\(number)").font(.system(size: 12)).foregroundStyle(C.muted)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Capa 2:3 de filme/série com nome de reserva e nota.
struct PosterView: View {
    let title: String
    let poster: String?
    var rating: String? = nil
    var hover = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(C.widget)
            Text(title).font(.system(size: 12)).foregroundStyle(C.muted).multilineTextAlignment(.center).padding(12)
            RemoteImage(url: poster, fill: true)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if let rating {
                Text("★ \(rating)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(C.star)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .padding(6)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hover ? C.focusRing : C.separator, lineWidth: hover ? 3 : 1))
        .scaleEffect(hover ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Progresso ("Baixando filmes…") e mensagens de erro/sucesso da última ação.
struct StatusLine: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        if let p = vm.progress {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(p).font(.system(size: 12)).foregroundStyle(C.selection)
            }
        } else if let e = vm.error {
            Text(e).font(.system(size: 12)).foregroundStyle(C.live).lineLimit(2)
        } else if let n = vm.notice {
            Text(n).font(.system(size: 12)).foregroundStyle(C.success).lineLimit(2)
        }
    }
}
