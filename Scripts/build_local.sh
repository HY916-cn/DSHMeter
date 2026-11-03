#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$PWD"
TASK_SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
TASK_SDK_VERSION="$(xcrun --sdk "$TASK_SDK" --show-sdk-version)"
TASK_TRIPLE="$(uname -m)-apple-macosx13.0"
# The linked SDK version controls adoption of the system's native appearance.
xcrun swift build -c release --product DSHMeter --sdk "$TASK_SDK" --triple "$TASK_TRIPLE" \
    -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$TASK_SDK_VERSION"
TASK_BIN="$(xcrun swift build -c release --sdk "$TASK_SDK" --triple "$TASK_TRIPLE" --show-bin-path)"
TASK_APP="$TASK_ROOT/dist/DSHMeter.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN/DSHMeter" "$TASK_APP/Contents/MacOS/DSHMeter"
cp Config/Info.plist "$TASK_APP/Contents/Info.plist"
cp LICENSE "$TASK_APP/Contents/Resources/LICENSE"
install -m 644 .build/checkouts/Yams/LICENSE "$TASK_APP/Contents/Resources/Yams-LICENSE"
python3 - "$TASK_ROOT" "$TASK_APP" <<'PY'
from pathlib import Path
import json, plistlib, shutil, subprocess, sys
root, app = map(Path, sys.argv[1:])
catalog = json.loads((root / 'DSHMeter/Localizable.xcstrings').read_text())
for language in ('en', 'zh-Hans', 'zh-Hant'):
    directory = app / 'Contents/Resources' / f'{language}.lproj'
    directory.mkdir(parents=True, exist_ok=True)
    strings = {}
    for key, entry in catalog['strings'].items():
        localizations = entry.get('localizations', {})
        translated = localizations.get(language, localizations.get('en', {}))
        strings[key] = translated.get('stringUnit', {}).get('value', key)
    (directory / 'Localizable.strings').write_bytes(plistlib.dumps(strings, fmt=plistlib.FMT_BINARY))
iconset = root / '.build/AppIcon.iconset'
iconset.mkdir(exist_ok=True)
assets = root / 'DSHMeter/Assets.xcassets/AppIcon.appiconset'
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        suffix = '@2x' if scale == 2 else ''
        shutil.copy2(assets / f'AppIcon-{size * scale}.png', iconset / f'icon_{size}x{size}{suffix}.png')
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(app / 'Contents/Resources/AppIcon.icns')], check=True)
# SwiftPM may ship dependency privacy manifests as resource bundles.
for bundle in (root / '.build').rglob('release/*.bundle'):
    target = app / 'Contents/Resources' / bundle.name
    if not target.exists(): shutil.copytree(bundle, target)
PY
codesign --force --sign - --identifier com.huang.DSHMeter "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
printf '%s\n' "$TASK_APP"
