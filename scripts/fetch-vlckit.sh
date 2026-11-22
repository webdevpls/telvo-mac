#!/usr/bin/env bash
# Baixa o VLCKit oficial da VideoLAN para Vendor/ (não vai para o git: ~400 MB).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="VLCKit-3.7.3-319ed2c0-79128878"
if [ -d Vendor/VLCKit.xcframework ]; then echo "VLCKit já está em Vendor/"; exit 0; fi
mkdir -p Vendor && cd Vendor
curl -fL -o vlckit.tar.xz "https://download.videolan.org/pub/cocoapods/prod/${VERSION}.tar.xz"
tar -xf vlckit.tar.xz && rm vlckit.tar.xz
mv "VLCKit - binary package/VLCKit.xcframework" . && rm -rf "VLCKit - binary package"
echo "VLCKit pronto em Vendor/VLCKit.xcframework"
