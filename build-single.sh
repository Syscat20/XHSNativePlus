#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")" && pwd)"
source_dir="$project/SingleSource"
logos="${1:-}"
output="${2:-$project/single/XHSNative-1.4-2.dylib}"

if [[ -z "$logos" ]]; then
    for cand in "${THEOS:-}/bin/logos.pl" "$HOME/theos/bin/logos.pl" /opt/theos/bin/logos.pl /usr/local/theos/bin/logos.pl "$(command -v logos.pl 2>/dev/null || true)"; do
        if [[ -n "$cand" && -f "$cand" ]]; then logos="$cand"; break; fi
    done
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
if [[ -n "$logos" ]]; then
    "$logos" -c generator=internal "$source_dir/XHSNative.xm" > "$staging/XHSNative.mm"
else
    python3 "$source_dir/logos-lite.py" "$source_dir/XHSNative.xm" "$staging/XHSNative.mm"
fi

xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -dynamiclib -fobjc-arc -O2 \
    -Werror=implicit-function-declaration -Wno-unguarded-availability-new -Wno-unused-parameter \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework Photos -lc++ \
    -I "$source_dir" -install_name @rpath/XHSNative.dylib \
    -o "$staging/XHSNative.dylib" "$staging/XHSNative.mm" \
    "$source_dir/XHSNativeHelper.m" "$source_dir/XHSNativeTabBar.m" \
    "$source_dir/XHSNativeGlassShared.m" "$source_dir/XHSNativeNoteGlass.m" \
    "$source_dir/XHSNativeVideoGlass.m" "$source_dir/XHSNativeChatGlass.m" \
    "$source_dir/XHSNativeSave.m" \
    "$source_dir/XHSNativeSettings.m" "$source_dir/XHSNativeConfig.m"
codesign --force --sign - --identifier XHSNative.VideoGlass "$staging/XHSNative.dylib"
codesign --verify --strict "$staging/XHSNative.dylib"
mkdir -p "$(dirname "$output")"
cp "$staging/XHSNative.dylib" "$output"
mkdir -p "$project/release"
cp "$staging/XHSNative.dylib" "$project/release/XHSNative-1.4-2.dylib"
rm -f "$project/release/XHSNative-VideoGlass.dylib"
