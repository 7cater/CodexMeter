#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/cache .build/module-cache build
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build -c release --product CodexMeter --disable-sandbox --cache-path "$PWD/.build/cache" \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
bin_dir=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")
app_path="$PWD/build/CodexMeter.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/CodexMeter" "$app_path/Contents/MacOS/CodexMeter"
for bundle in "$bin_dir"/*.bundle; do
  if [[ -d "$bundle" ]]; then cp -R "$bundle" "$app_path/Contents/Resources/"; fi
done
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexMeter</string>
<key>CFBundleIdentifier</key><string>com.chenyu.CodexMeter</string>
<key>CFBundleName</key><string>CodexMeter</string>
<key>CFBundleDisplayName</key><string>CodexMeter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp LICENSE "$app_path/Contents/Resources/LICENSE"
codesign --force --deep --sign - "$app_path"
print "已构建：$app_path"
if [[ "${1:-}" == "--run" ]]; then open "$app_path"; fi
