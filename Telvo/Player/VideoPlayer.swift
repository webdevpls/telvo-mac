import AppKit
import Observation
import SwiftUI
import VLCKit

/// Player baseado no VLC. Mesma lógica do TvPlayer do Android: User-Agent de player conhecido,
/// buffer generoso e um vigia que reabre o link quando o servidor para de mandar dados.
@MainActor
@Observable
final class VideoPlayer: NSObject {
    private(set) var buffering = false
    private(set) var error: String?
    private(set) var isPlaying = false
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    /// 0–100. Fica guardado entre sessões, vale para TV, filmes e séries.
    private(set) var volume: Int = UserDefaults.standard.object(forKey: "volume") as? Int ?? 100
    private(set) var muted: Bool = UserDefaults.standard.bool(forKey: "muted")
    /// Pausado pelo usuário (no ao vivo, despausar volta para o ao vivo).
    private(set) var paused = false

    @ObservationIgnored let vlc = VLCMediaPlayer()
    @ObservationIgnored private let userAgent: String
    @ObservationIgnored private var url: String?
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var reconnects = 0
    @ObservationIgnored private var lastProgress = Date()
    @ObservationIgnored private var lastTime: Int64 = -1
    @ObservationIgnored private var watchdog: Timer?

    private static let stallTimeout: TimeInterval = 15
    private static let maxReconnects = 3

    init(userAgent: String) {
        self.userAgent = userAgent
        super.init()
        vlc.delegate = self
        // Confere o andamento uma vez por segundo (posição, travamento).
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var isLive: Bool { durationMs <= 0 }

    func play(_ url: String, startMs: Int64 = 0) {
        self.url = url
        error = nil
        reconnects = 0
        open(url, startMs: startMs)
    }

    func retry() {
        error = nil
        reconnects = 0
        reconnect()
    }

    /// Abre o link de novo com conexão nova: filme no ponto onde parou, ao vivo no ao vivo.
    func reconnect() {
        guard let url else { return }
        reconnects += 1
        error = nil
        open(url, startMs: isLive ? 0 : positionMs)
    }

    func togglePause() {
        if paused || !vlc.isPlaying { resume() } else { pause() }
    }

    func pause() {
        wantsPlay = false
        paused = true
        buffering = false
        vlc.pause()
    }

    func resume() {
        guard let url else { return }
        paused = false
        wantsPlay = true
        lastProgress = Date()
        if isLive {
            // Ao vivo não continua de onde parou: reabre o canal para voltar ao vivo.
            error = nil
            reconnects = 0
            open(url, startMs: 0)
        } else if vlc.state == .stopped || vlc.state == .ended || vlc.state == .error {
            reconnect()
        } else {
            vlc.play()
        }
    }

    // MARK: - Volume

    func setVolume(_ value: Int) {
        volume = min(max(value, 0), 100)
        if volume > 0 && muted { muted = false }
        applyAudio()
        UserDefaults.standard.set(volume, forKey: "volume")
        UserDefaults.standard.set(muted, forKey: "muted")
    }

    func changeVolume(by delta: Int) { setVolume(volume + delta) }

    func toggleMute() {
        muted.toggle()
        applyAudio()
        UserDefaults.standard.set(muted, forKey: "muted")
    }

    private func applyAudio() {
        guard let audio = vlc.audio else { return }
        audio.volume = Int32(volume)
        audio.isMuted = muted
    }

    func seek(by deltaMs: Int64) {
        guard !isLive else { return }
        let target = min(max(positionMs + deltaMs, 0), durationMs > 0 ? durationMs : .max)
        seek(to: target)
    }

    func seek(to ms: Int64) {
        vlc.time = VLCTime(int: Int32(clamping: ms))
        positionMs = ms
        lastProgress = Date()
    }

    func stop() {
        wantsPlay = false
        vlc.stop()
        isPlaying = false
        buffering = false
    }

    func release() {
        watchdog?.invalidate()
        watchdog = nil
        stop()
        vlc.delegate = nil
        vlc.drawable = nil
    }

    private func open(_ url: String, startMs: Int64) {
        guard let u = URL(string: url) else {
            error = "Link inválido"
            return
        }
        let media = VLCMedia(url: u)
        var options = [
            ":http-user-agent=\(userAgent)",
            // Buffer maior para engasgos curtos do servidor passarem despercebidos.
            ":network-caching=3000",
            ":http-reconnect",
        ]
        if startMs > 0 { options.append(":start-time=\(Double(startMs) / 1000)") }
        media.addOptions(Dictionary(uniqueKeysWithValues: options.map { ($0, NSNull()) }))
        vlc.media = media
        paused = false
        wantsPlay = true
        buffering = true
        lastTime = -1
        lastProgress = Date()
        vlc.play()
    }

    private func tick() {
        let time = Int64(vlc.time.intValue)
        let length = Int64(vlc.media?.length.intValue ?? 0)
        if time != positionMs { positionMs = max(time, 0) }
        if length != durationMs { durationMs = max(length, 0) }
        isPlaying = vlc.isPlaying

        guard wantsPlay, error == nil else { return }
        if time != lastTime {
            lastTime = time
            lastProgress = Date()
            if time > 0 {
                buffering = false
                reconnects = 0
            }
            return
        }
        // Parado sem avançar: o servidor parou de mandar dados sem fechar a conexão.
        buffering = true
        if Date().timeIntervalSince(lastProgress) > Self.stallTimeout {
            if reconnects < Self.maxReconnects { reconnect() } else { fail("O servidor parou de responder") }
        }
    }

    private func fail(_ message: String) {
        error = message
        buffering = false
        wantsPlay = false
    }

    fileprivate func stateChanged() {
        switch vlc.state {
        case .opening, .buffering:
            if !isPlaying { buffering = true }
        case .playing:
            isPlaying = true
            applyAudio()
        case .paused:
            isPlaying = false
            buffering = false
        case .error:
            // Conexão caiu no meio: reconecta sozinho algumas vezes antes de mostrar o erro.
            if reconnects < Self.maxReconnects { reconnect() } else { fail("Não foi possível reproduzir este link") }
        case .ended:
            isPlaying = false
            // Ao vivo não "acaba": se acabou, o servidor derrubou o stream.
            if isLive && wantsPlay && reconnects < Self.maxReconnects { reconnect() }
        default:
            break
        }
    }
}

extension VideoPlayer: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in self.stateChanged() }
    }
}

/// Superfície de vídeo do VLC dentro do SwiftUI.
struct VideoSurface: NSViewRepresentable {
    let player: VideoPlayer

    func makeNSView(context: Context) -> VLCVideoView {
        let view = VLCVideoView()
        view.backColor = .black
        view.fillScreen = false
        player.vlc.drawable = view
        return view
    }

    func updateNSView(_ view: VLCVideoView, context: Context) {
        if player.vlc.drawable as? VLCVideoView !== view { player.vlc.drawable = view }
    }
}
