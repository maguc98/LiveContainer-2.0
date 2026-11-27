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

# Package SideStore from the locally built, patched source—not an upstream release.
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

# Remove existing signatures from nested products, then apply ad-hoc signatures required by packaging.
find Payload/LiveContainer.app -type d -name _CodeSignature -prune -exec rm -rf {} +
ldid -S.github/sidelc/LiveWidgetExtension_adhoc.xml Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension

# Restore framework and package the complete combined app.
mv tmp/SideStoreSupport.framework Payload/LiveContainer.app/Frameworks/
rm -rf tmp
zip -qr "${SCHEME}+SideStore.ipa" Payload -x "._*" ".DS_Store" "__MACOSX"
test -s "${SCHEME}+SideStore.ipa"
