#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcrun swiftc -swift-version 6 -module-cache-path /tmp/DreamTravelSwiftModuleCache \
  DreamTravelMobile/Style/PlanThemeCatalog.swift Tests/PlanThemeCheck.swift \
  -o /tmp/DreamTravelThemeCheck
# Optional explicit output path exports theme presets; no sibling repository is required.
/tmp/DreamTravelThemeCheck "$@"
