import SwiftUI

extension C {
    /// Azul forte dos destaques (ícone ativo, selos, brilho do fundo).
    static let accent = Color(hex: 0x3D5AFE)
    static let ink = Color(hex: 0x0A0B10)
}

/// Fundo escuro com o brilho azul do lado direito.
struct GlowBackground: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                C.ink
                RadialGradient(
                    colors: [C.accent.opacity(0.55), C.accent.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.92, y: 0.72),
                    startRadius: 0,
                    endRadius: max(g.size.width, g.size.height) * 0.6
                )
                RadialGradient(
                    colors: [Color(hex: 0x1B2A8F).opacity(0.25), .clear],
                    center: UnitPoint(x: 0.25, y: 0.35),
                    startRadius: 0,
                    endRadius: g.size.width * 0.35
                )
            }
        }
        .ignoresSafeArea()
    }
}

enum RailItem: Hashable {
    case search, home, tv, favorites, series, movies, settings
}

/// Barra lateral de ícones redondos (navegação principal).
struct NavRail: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            item(.search, "magnifyingglass", "Buscar canal", nil)
            item(.home, "house", "Início", "⌘0")
            item(.tv, "tv", "TV ao vivo", "⌘1")
            item(.favorites, "heart", "Favoritos", nil)
            if vm.hasVod {
                item(.series, "rectangle.stack", "Séries", "⌘2")
                item(.movies, "film", "Filmes", "⌘3")
            }
            item(.settings, "gearshape", "Configurações", "⌘,")
            Spacer(minLength: 0)
        }
        .frame(width: 76)
        .padding(.vertical, 24)
        .frame(maxHeight: .infinity)
        // Vidro fosco do macOS, com uma linha fina separando do conteúdo.
        .background(.ultraThinMaterial.opacity(0.6))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
    }

    private var active: RailItem {
        switch vm.screen {
        case .hub: return .home
        case .settings, .form: return .settings
        case .section:
            switch vm.section {
            case .live: return vm.filter == .favorites ? .favorites : .tv
            case .series: return .series
            case .movies: return .movies
            }
        }
    }

    private func item(_ which: RailItem, _ icon: String, _ label: String, _ shortcut: String?) -> some View {
        RailButton(icon: icon, label: label, shortcut: shortcut, active: active == which,
                   enabled: which == .settings || vm.current != nil) {
            go(which)
        }
    }

    private func go(_ which: RailItem) {
        switch which {
        case .home: vm.goHome()
        case .settings: vm.openSettings()
        case .tv:
            if vm.filter == .favorites { vm.filter = .all }
            vm.openSection(.live)
        case .favorites:
            vm.filter = .favorites
            vm.openSection(.live)
        case .search:
            vm.openSection(.live)
            vm.searchRequest += 1
        case .series: vm.openSection(.series)
        case .movies: vm.openSection(.movies)
        }
    }
}

private struct RailButton: View {
    let icon: String
    let label: String
    let shortcut: String?
    let active: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: active ? "\(icon).fill" : icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active ? .white : (hover ? C.heading : C.body))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? C.accent : Color.white.opacity(hover ? 0.12 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hover && !active ? Color.white.opacity(0.25) : .clear))
                .shadow(color: active ? C.accent.opacity(0.6) : .clear, radius: 12)
                .animation(.easeOut(duration: 0.15), value: hover)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hover = $0 }
        // Tooltip imediato ao lado do ícone (o .help nativo demora e é pequeno).
        .overlay(alignment: .leading) {
            if hover {
                HStack(spacing: 8) {
                    Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    if let shortcut {
                        Text(shortcut).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                .fixedSize()
                .offset(x: 54)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
