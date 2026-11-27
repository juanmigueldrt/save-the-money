#!/bin/sh
# Regenera los catálogos de textos (ORC-110) con lo que extrae el compilador. Uso: scripts/catalogo-textos.sh
# Compila de cero para Mac y para iPhone (hay textos dentro de #if os) y sincroniza cada catálogo con sus .stringsdata:
# entran las claves nuevas y salen las que ya no están en el código; las variantes de plural escritas a mano se conservan.
set -eu
cd "$(dirname "$0")/.."
datos=DerivedData/catalogo
intermedios=$datos/Build/Intermediates.noindex

[ -f Config/Secrets.xcconfig ] || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
xcodegen generate --quiet
rm -rf "$datos"
for destino in 'platform=macOS,arch=arm64' 'generic/platform=iOS Simulator'; do
    xcodebuild build -quiet -project SaveTheMoney.xcodeproj -scheme SaveTheMoney -destination "$destino" \
        -derivedDataPath "$datos" CODE_SIGNING_ALLOWED=NO
done

# sincroniza <catálogo> <carpeta de intermedios del target>
sincroniza() {
    find "$intermedios/$2" -name '*.stringsdata' -exec xcrun xcstringstool sync "$1" --stringsdata {} +
    echo "$1: $(xcrun xcstringstool print "$1" | wc -l | tr -d ' ') claves"
}
sincroniza App/Localizable.xcstrings SaveTheMoney.build
for paquete in STMCore STMUI STMData; do
    sincroniza "Packages/$paquete/Sources/$paquete/Localizable.xcstrings" "$paquete.build"
done

# Un texto con traducciones o plurales cuya clave ya no está en el código no se borra: queda marcado y hay que revisarlo.
if grep -l '"stale"' App/Localizable.xcstrings Packages/*/Sources/*/Localizable.xcstrings; then
    echo "Hay textos que ya no están en el código (extractionState stale) en los catálogos de arriba." >&2
    exit 1
fi
