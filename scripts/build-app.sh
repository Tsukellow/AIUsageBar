#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:---signed}"
if (( $# > 1 )) || [[ "$mode" != --signed && "$mode" != --unsigned ]]; then
    print -u2 "Usage: ./scripts/build-app.sh [--signed|--unsigned]"
    exit 2
fi
if [[ "$mode" == --signed ]]; then
    app_path="${AI_USAGE_APP_PATH:-.build/AI Usage Bar.app}"
    python3 scripts/local-signing.py prepare >/dev/null
else
    app_path="${AI_USAGE_APP_PATH:-.build/unsigned/AI Usage Bar.app}"
    if [[ -e "$app_path/Contents/_CodeSignature" ]]; then
        print -u2 "Unsigned builds need a separate output path from existing signed apps."
        exit 2
    fi
fi
mkdir -p .build/icon-module-cache
swift -module-cache-path .build/icon-module-cache scripts/render-icon.swift Artwork/AppIconSource.png .build/generated-artwork
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp -X "$binary_dir/AIUsageBar" "$app_path/Contents/MacOS/AIUsageBar"
cp -X Sources/AIUsageBar/Resources/Info.plist "$app_path/Contents/Info.plist"
cp -X .build/generated-artwork/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
provider_icons="$app_path/Contents/Resources/ProviderIcons"
mkdir -p "$provider_icons"
cp -X Artwork/ProviderIcons/{claude,codex-dark,codex-light,antigravity,grok,deepSeek}.png "$provider_icons/"
if xattr -p com.apple.FinderInfo "$app_path" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$app_path"
fi
if [[ "$mode" == --signed ]]; then
    python3 scripts/local-signing.py sign "$app_path" com.yhzh.AIUsageBar
fi
print -r -- "Built ${app_path:A}"
