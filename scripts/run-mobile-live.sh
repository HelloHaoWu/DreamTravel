#!/bin/zsh
set -euo pipefail

device="${1:-booted}"
app_path="${DREAMTRAVEL_APP_PATH:-/tmp/DreamTravelDerivedData/Build/Products/Debug-iphonesimulator/DreamTravelMobile.app}"
if ! security find-generic-password -s com.dreamtravel.test.tencent-map -a web-service >/dev/null 2>&1; then
    print -u2 '未找到腾讯测试 Key，请按 TravelProviderSetup.md 存入钥匙串。'
    exit 1
fi
if [[ ! -d "$app_path" ]]; then
    print -u2 '没有找到 Debug App，请先用 Xcode 构建。'
    exit 1
fi

tencent_key="$(security find-generic-password -s com.dreamtravel.test.tencent-map -a web-service -w)"
xcrun simctl install "$device" "$app_path"
SIMCTL_CHILD_DREAMTRAVEL_TENCENT_MAP_KEY="$tencent_key" \
    xcrun simctl launch --terminate-running-process "$device" com.dreamtravel.mobile
