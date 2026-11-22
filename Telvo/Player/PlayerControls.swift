import SwiftUI

/// Botão de pausa/continuar usado nos players de TV, filmes e séries.
struct PlayPauseButton: View {
    let player: VideoPlayer
    var size: CGFloat = 20
    var onAction: () -> Void = {}

    var body: some View {
        let playing = player.isPlaying && !player.paused
        Button {
            player.togglePause()
            onAction()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size))
                .foregroundStyle(C.selection)
                .frame(width: size + 8, height: size + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(playing ? "Pausar (Espaço)" : (player.isLive ? "Voltar ao ao vivo (Espaço)" : "Continuar (Espaço)"))
    }
}

/// Alto-falante (clique = mudo) + barra de volume.
struct VolumeControl: View {
    let player: VideoPlayer
    var width: CGFloat = 110
    var onAction: () -> Void = {}

    private var icon: String {
        if player.muted || player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 34 { return "speaker.wave.1.fill" }
        if player.volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                player.toggleMute()
                onAction()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(player.muted ? C.muted : C.heading)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.muted ? "Tirar do mudo (M)" : "Mudo (M)")
            Slider(
                value: Binding(get: { Double(player.muted ? 0 : player.volume) }, set: { player.setVolume(Int($0)); onAction() }),
                in: 0...100
            )
            .tint(C.selection)
            .frame(width: width)
            .help("Volume: \(player.muted ? 0 : player.volume)% (+ / −)")
        }
    }
}
