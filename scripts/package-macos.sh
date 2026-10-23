#!/bin/bash
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(git -C "$app_dir" rev-parse --show-toplevel)"
if [[ "$repo_dir" == "$app_dir" ]]; then source_path="."; else source_path="apps/creator"; fi
dirty="$(git -C "$repo_dir" status --porcelain --untracked-files=all -- "$source_path")"
if [[ -n "$dirty" ]]; then
  printf 'Refusing to package uncommitted Creator source; commit the exact app revision first.\n' >&2
  exit 2
fi
source_sha="$(git -C "$repo_dir" rev-parse HEAD)"
out_dir="${1:-$app_dir/build/replica-neutral-core/$source_sha}"
if [[ -e "$out_dir" ]]; then
  printf 'Refusing to overwrite existing package output: %s\n' "$out_dir" >&2
  exit 2
fi
mkdir -p "$out_dir"
manifest="$out_dir/release-manifest.txt"
printf 'variant=neutral-core\nsource_commit=%s\n' "$source_sha" > "$manifest"
cd "$app_dir"
swift build -c release --product CreatorReplica
binary="$app_dir/.build/release/CreatorReplica"
bundle="$out_dir/Creator Baseline.app"
mkdir -p "$bundle/Contents/MacOS"
cp "$binary" "$bundle/Contents/MacOS/CreatorReplica"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Creator Baseline</string>
<key>CFBundleDisplayName</key><string>Creator Baseline</string>
<key>CFBundleIdentifier</key><string>com.ghostzy.creatorreplica.neutral-core</string>
<key>CFBundleExecutable</key><string>CreatorReplica</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0-alpha.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>PIPCreatorSourceCommit</key><string>$source_sha</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
archive="$out_dir/neutral-core.zip"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$archive"
binary_sha="$(shasum -a 256 "$bundle/Contents/MacOS/CreatorReplica" | awk '{print $1}')"
archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
printf 'binary_sha256=%s\narchive_sha256=%s\n' "$binary_sha" "$archive_sha" | tee -a "$manifest"
printf 'source_sha=%s\noutput=%s\n' "$source_sha" "$out_dir"
