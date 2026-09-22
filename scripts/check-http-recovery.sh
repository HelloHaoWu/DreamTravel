#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcrun swiftc -swift-version 6 -module-cache-path /tmp/DreamTravelSwiftModuleCache \
  DreamTravelMobile/Services/TravelHTTPTransport.swift \
  DreamTravelMobile/Services/TravelProviderConfiguration.swift \
  DreamTravelMobile/Services/DeepSeekConnection.swift Tests/HTTPRecoveryCheck.swift \
  -o /tmp/DreamTravelHTTPRecoveryCheck
/tmp/DreamTravelHTTPRecoveryCheck
