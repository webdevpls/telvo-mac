# Telvo para Mac

Versão nativa para macOS do [Telvo](https://github.com/nerigleston/iptv-tv) (player IPTV da TV),
feita em SwiftUI com o VLC embutido para tocar TS, HLS, MP4 e MKV.

Mesmas funções do app de TV: listas M3U e Xtream Codes, guia EPG (XMLTV ou `get_short_epg`),
favoritos, filmes e séries, recentes com "continuar de onde parou" e reconexão automática
quando o servidor trava.

## Build

Requisitos: macOS 14+, Xcode 16+ e [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
./scripts/fetch-vlckit.sh      # baixa o VLCKit 3.7.3 da VideoLAN para Vendor/
xcodegen generate              # gera o Telvo.xcodeproj a partir do project.yml
xcodebuild -project Telvo.xcodeproj -scheme Telvo -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Telvo.app
```

## Navegação

O **Início** tem quatro cartões: **TV**, **Séries**, **Filmes** e **Configurações** (onde ficam as listas),
mais a faixa **Continuar assistindo**. Em cada tela, a barra do topo tem **← Início** e a busca.

Na TV, a coluna da esquerda tem um seletor único (Todos, Favoritos ou um grupo) e o vídeo fica à
direita com "Agora / A seguir" embaixo. Os controles (pausa, volume, ★, tela cheia) aparecem sobre o vídeo.

## Atalhos

| Tecla | TV | Filmes e séries |
|---|---|---|
| Espaço | pausa (despausar volta ao ao vivo) | pausa / continua |
| ↑ ↓ | troca de canal | volume |
| ← → / + − | volume | volta / avança 10 s (+ − volume) |
| M | mudo | mudo |
| F ou clique duplo | tela cheia | tela cheia |
| N / P | próximo / canal anterior | próximo / episódio anterior |
| Esc | volta | volta |
| ⌘0–3 | Início, TV, Séries, Filmes | |
| ⌘, / ⌘R | Configurações / atualizar lista | |

Botão direito num canal favorita; num item de Continuar assistindo, tira da lista.

## Estrutura

- `Telvo/Data`: modelos, parser M3U, cliente Xtream, EPG (XMLTV), HTTP e armazenamento
  (UserDefaults + `~/Library/Application Support/Telvo`). Porte direto do código Kotlin do app de TV.
- `Telvo/App`: `AppModel` (equivalente ao `MainViewModel`) e entrada do app, com o monitor de teclas.
- `Telvo/Player`: `VideoPlayer` (VLCKit) e controles de pausa/volume.
- `Telvo/Views`: telas no tema escuro do app de TV.
