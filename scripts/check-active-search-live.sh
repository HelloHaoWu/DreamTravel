#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcrun swiftc -swift-version 6 -module-cache-path /tmp/DreamTravelSwiftModuleCache \
  -o /tmp/DreamTravelDiscoveryLiveCheck \
  DreamTravelMobile/Agent/*.swift \
  DreamTravelMobile/Services/TravelProviderConfiguration.swift \
  DreamTravelMobile/Services/TravelHTTPTransport.swift \
  DreamTravelMobile/Services/TencentTravelAPI.swift \
  DreamTravelMobile/Services/DeepSeekConnection.swift \
  DreamTravelMobile/Services/DeepSeekResponsesPlanningAdapter.swift \
  DreamTravelMobile/Services/DiscoveryService.swift \
  DreamTravelMobile/Services/ReferenceLibrary.swift \
  DreamTravelMobile/Services/PlaceResearchService.swift \
  DreamTravelMobile/Services/PlaceReservation.swift \
  Tools/ActiveDiscoveryLiveCheck.swift
NSUnbufferedIO=YES /tmp/DreamTravelDiscoveryLiveCheck "$@"
