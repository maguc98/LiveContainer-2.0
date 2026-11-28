#!/bin/bash
set -euo pipefail

# Run from LiveContainer source root.
SCHEME="${scheme:-LiveContainer}"
ARCHIVE_PATH="${archive_path:-archive}"
SIDESTORE_IPA="${SIDESTORE_IPA:-../build/SideStore.ipa}"

test -f "$SIDESTORE_IPA"
test -d "$ARCHIVE_PATH.xcarchive/Products/Applications"

curl -L --fail -o dylibify https://github.com/LiveContainer/dylibify/releases/download/1.0/dylibify
chmod +x dylibify
brew install ldid

rm -rf Payload tmp
mkdir -p tmp
mv "$ARCHIVE_PATH.xcarchive/Products/Applications" Payload
mv Payload/LiveContainer.app/Frameworks/SideStoreSupport.framework tmp/

# Package SideStore from the locally built source—not a standalone deliverable.
mkdir -p tmp/sidestore
unzip -q "$SIDESTORE_IPA" -d tmp/sidestore
test -d tmp/sidestore/Payload/SideStore.app
mv tmp/sidestore/Payload/SideStore.app Payload/LiveContainer.app/Frameworks/SideStoreApp.framework
./dylibify Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore.dylib
rm Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
mv Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore.dylib Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
ldid -S"" Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
cp .github/sidelc/LCAppInfo.plist Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/

# Preserve LiveContainer+SideStore integration metadata.
 /usr/libexec/PlistBuddy -c 'Add :ALTAppGroups array' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :ALTAppGroups: string group.com.SideStore.SideStore' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1 dict' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1:CFBundleURLName string com.kdt.livecontainer.sidestoreurlscheme' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1:CFBundleURLSchemes array' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string sidestore' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2 dict' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2:CFBundleURLName string com.kdt.livecontainer.sidestorebackupurlscheme' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2:CFBundleURLSchemes array' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2:CFBundleURLSchemes:0 string sidestore-com.kdt.livecontainer' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :INIntentsSupported array' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :INIntentsSupported:0 string RefreshAllIntent' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :INIntentsSupported:1 string ViewAppIntent' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :NSUserActivityTypes array' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :NSUserActivityTypes:0 string RefreshAllIntent' Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :NSUserActivityTypes:1 string ViewAppIntent' Payload/LiveContainer.app/Info.plist

# Add SideStore widget and intents to LiveContainer.
cp Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/Intents.intentdefinition Payload/LiveContainer.app/
cp Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/ViewApp.intentdefinition Payload/LiveContainer.app/
cp -r Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/Metadata.appintents Payload/LiveContainer.app/Metadata.appintents
sed -i '' 's/9SideStore20RefreshAllAppsIntentV/16SideStoreSupport20RefreshAllAppsIntentV/g' Payload/LiveContainer.app/Metadata.appintents/extract.actionsdata
sed -i '' 's/9SideStore26RefreshAllAppsWidgetIntentV/16SideStoreSupport26RefreshAllAppsWidgetIntentV/g' Payload/LiveContainer.app/Metadata.appintents/extract.actionsdata

# Embed the widget extension and rename its bundle metadata.
mv Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/PlugIns/AltWidgetExtension.appex Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.kdt.livecontainer.LiveWidget' Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LiveWidgetExtension' Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/Info.plist
mv Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/AltWidgetExtension Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension

# Remove CMS resource-signature directories from nested products. The ad-hoc
# Mach-O signatures remain and carry the entitlements required by the final re-signer.
find Payload/LiveContainer.app -type d -name _CodeSignature -prune -exec rm -rf {} +
ldid -S.github/sidelc/LiveWidgetExtension_adhoc.xml Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension

# Xcode archive runs without provisioning profiles in CI. Add the exact
# App Groups declared by Global.xcconfig to the Mach-O entitlement payloads so
# the user's final signing tool can carry them into the installed app.
sign_app_group_entitlements() {
    local bundle_path="$1"
    local entitlements_path="$2"
    local executable
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle_path/Info.plist")"
    ldid -S"$entitlements_path" "$bundle_path/$executable"
}

sign_app_group_entitlements "Payload/LiveContainer.app" ".github/sidelc/LiveContainer_Host_adhoc.xml"
sign_app_group_entitlements "Payload/LiveContainer.app/PlugIns/LiveProcess.appex" ".github/sidelc/LiveProcess_adhoc.xml"
sign_app_group_entitlements "Payload/LiveContainer.app/PlugIns/ShareExtension.appex" ".github/sidelc/LiveContainer_AppGroups_adhoc.xml"
sign_app_group_entitlements "Payload/LiveContainer.app/PlugIns/LaunchAppExtension.appex" ".github/sidelc/LiveContainer_AppGroups_adhoc.xml"

# Verify the App Group entitlement payloads are present on all app and extension targets.
verify_app_group_entitlements() {
    local bundle_path="$1"
    local expected_group
    shift
    local executable
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle_path/Info.plist")"
    local extracted="$TMPDIR/$(basename "$bundle_path").entitlements.plist"
    ldid -e "$bundle_path/$executable" > "$extracted"
    local declared_groups
    declared_groups="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$extracted")"
    for expected_group in "$@"; do
        if ! printf '%s\n' "$declared_groups" | grep -Fq "$expected_group"; then
            echo "Missing App Group entitlement '$expected_group' in $bundle_path/$executable" >&2
            exit 1
        fi
    done
}

verify_app_group_entitlements "Payload/LiveContainer.app" \
    "group.com.SideStore.SideStore" "group.com.rileytestut.AltStore"
verify_app_group_entitlements "Payload/LiveContainer.app/PlugIns/LiveProcess.appex" \
    "group.com.SideStore.SideStore" "group.com.rileytestut.AltStore"
verify_app_group_entitlements "Payload/LiveContainer.app/PlugIns/ShareExtension.appex" \
    "group.com.SideStore.SideStore" "group.com.rileytestut.AltStore"
verify_app_group_entitlements "Payload/LiveContainer.app/PlugIns/LaunchAppExtension.appex" \
    "group.com.SideStore.SideStore" "group.com.rileytestut.AltStore"
verify_app_group_entitlements "Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex" \
    "group.com.SideStore.SideStore"

verify_required_entitlements() {
    local bundle_path="$1"
    local expected_key="$2"
    local executable
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle_path/Info.plist")"
    local extracted="$TMPDIR/$(basename "$bundle_path").entitlements.plist"
    ldid -e "$bundle_path/$executable" > "$extracted"
    /usr/libexec/PlistBuddy -c "Print :$expected_key" "$extracted" >/dev/null
}

for bundle in "Payload/LiveContainer.app" "Payload/LiveContainer.app/PlugIns/LiveProcess.appex"; do
    verify_required_entitlements "$bundle" "com.apple.developer.healthkit"
    verify_required_entitlements "$bundle" "com.apple.developer.kernel.increased-memory-limit"
    verify_required_entitlements "$bundle" "keychain-access-groups"
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Info.plist")"
    extracted="$TMPDIR/$(basename "$bundle").entitlements.plist"
    ldid -e "$bundle/$executable" > "$extracted"
    python3 - "$extracted" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as source:
    entitlements = plistlib.load(source)
groups = entitlements.get("keychain-access-groups", [])
expected = [f"AAAAA11111.com.kdt.livecontainer.shared" + (f".{i}" if i else "") for i in range(128)]
if groups != expected:
    raise SystemExit(f"Expected 128 preserved LiveContainer Keychain groups, found {len(groups)}")
PY
done

# Restore framework and package the complete combined app.
mv tmp/SideStoreSupport.framework Payload/LiveContainer.app/Frameworks/
rm -rf tmp
zip -qr "${SCHEME}+SideStore.ipa" Payload -x "._*" ".DS_Store" "__MACOSX"
test -s "${SCHEME}+SideStore.ipa"
