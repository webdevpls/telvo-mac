import AppKit
import SwiftUI

@main
struct TelvoApp: App {
    @State private var vm = AppModel()

    var body: some Scene {
        WindowGroup("Telvo") {
            RootView()
                .environment(vm)
                .frame(minWidth: 1100, minHeight: 680)
                .preferredColorScheme(.dark)
                .onAppear { KeyMonitor.shared.install(vm) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Adicionar lista…") { vm.newPlaylist() }.keyboardShortcut("n")
            }
            CommandMenu("Assistir") {
                Button("Ao vivo") { vm.openSection(.live) }.keyboardShortcut("1").disabled(vm.current == nil)
                Button("Filmes") { vm.openSection(.movies) }.keyboardShortcut("2").disabled(!vm.hasVod)
                Button("Séries") { vm.openSection(.series) }.keyboardShortcut("3").disabled(!vm.hasVod)
                Button("Recentes") { vm.openSection(.recent) }.keyboardShortcut("4").disabled(!vm.hasVod)
                Divider()
                Button("Mostrar/ocultar guia") { vm.showEpg.toggle() }.keyboardShortcut("g").disabled(!vm.hasEpg)
                if let p = vm.current {
                    Button("Atualizar lista") { vm.refresh(p) }.keyboardShortcut("r").disabled(vm.loading)
                }
                Button("Listas") { vm.goHome() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        Group {
            switch vm.screen {
            case .home: HomeView()
            case .form(let editing): FormView(editing: editing)
            case .watch: WatchView()
            }
        }
        .background(C.shell)
        .ignoresSafeArea(edges: .top)
    }
}

struct WatchView: View {
    @Environment(AppModel.self) private var vm

    var body: some View {
        if let prompt = vm.resumePrompt {
            ResumeView(prompt: prompt)
        } else if let playback = vm.vodPlayback {
            VodPlayerView(playback: playback)
        } else {
            switch vm.section {
            case .live: LiveView()
            case .recent: RecentView()
            case .movies, .series:
                if vm.openSeries != nil { SeriesDetail() } else { VodBrowser() }
            }
        }
    }
}

/// Atalhos do player em qualquer tela, como nos players nativos do Mac. Enquanto um campo
/// de texto está em edição, só o Esc é interceptado (para sair do campo / voltar).
@MainActor
final class KeyMonitor {
    static let shared = KeyMonitor()
    private var monitor: Any?

    func install(_ vm: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak vm] event in
            guard let vm else { return event }
            // Atalhos com ⌘/⌃/⌥ ficam para o menu.
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            let editing = NSApp.keyWindow?.firstResponder is NSTextView
            guard let key = Self.key(for: event) else { return event }
            if key == .escape {
                if editing {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    return nil
                }
                if vm.keyHandler?(.escape) == true { return nil }
                // Em tela cheia do macOS, o primeiro Esc só sai da tela cheia.
                if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true, vm.vodPlayback != nil || vm.fullscreen {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                vm.back()
                return nil
            }
            if editing { return event }
            return vm.keyHandler?(key) == true ? nil : event
        }
    }

    private static func key(for event: NSEvent) -> AppKey? {
        switch event.keyCode {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 49: return .space
        case 36, 76: return .enter
        case 53: return .escape
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f": return .fullscreen
        case "n": return .next
        case "p": return .previous
        case "+", "=": return .volumeUp
        case "-", "_": return .volumeDown
        case "m": return .mute
        default: return nil
        }
    }
}
