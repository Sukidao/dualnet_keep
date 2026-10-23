#!/usr/bin/env bash
# 编译 java/dualnet/*.java 为 dualnet/tools/label.dex（Linux / macOS / CI）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_JAR="${ANDROID_JAR:-}"
D8="${D8:-}"

if [[ -z "$ANDROID_JAR" || -z "$D8" ]]; then
  SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
  [[ -z "$ANDROID_JAR" ]] && ANDROID_JAR="$(find "$SDK/platforms" -name android.jar | sort -V | tail -1)"
  [[ -z "$D8" ]] && D8="$(find "$SDK/build-tools" -name d8 | sort -V | tail -1)"
fi

[[ -f "$ANDROID_JAR" ]] || { echo "找不到 android.jar"; exit 1; }
[[ -x "$D8" ]] || { echo "找不到 d8"; exit 1; }

CLASSES="$ROOT/build/classes"
DEXOUT="$ROOT/build/dexout"
rm -rf "$CLASSES" "$DEXOUT"
mkdir -p "$CLASSES" "$DEXOUT"

echo "android.jar: $ANDROID_JAR"
echo "d8:          $D8"

javac -nowarn -source 8 -target 8 -bootclasspath "$ANDROID_JAR" \
  -d "$CLASSES" "$ROOT"/java/dualnet/*.java

"$D8" --lib "$ANDROID_JAR" --min-api 26 --output "$DEXOUT" \
  $(find "$CLASSES" -name '*.class')

cp "$DEXOUT/classes.dex" "$ROOT/dualnet/tools/label.dex"
echo "生成: dualnet/tools/label.dex ($(stat -c%s "$ROOT/dualnet/tools/label.dex" 2>/dev/null || stat -f%z "$ROOT/dualnet/tools/label.dex") 字节)"
