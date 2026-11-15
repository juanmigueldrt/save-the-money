#!/bin/sh
# Captura pantallas de la app en el emulador: tools/capturar.sh <carpeta> <claro|oscuro> <n> [n…]
# Abre cada pantalla con --ei pantalla N, espera a que termine la animación y guarda NN.png.
set -e
out=$1; mode=$2; shift 2
mkdir -p "$out"
adb shell cmd uimode night "$([ "$mode" = oscuro ] && echo yes || echo no)" >/dev/null
for n in "$@"; do
  adb shell am force-stop com.savethemoney.android
  adb shell am start -n com.savethemoney.android/.MainActivity --ei pantalla "$n" >/dev/null
  sleep 3
  adb exec-out screencap -p > "$out/$(printf %02d "$n").png"
done
