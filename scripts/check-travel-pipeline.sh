#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcrun swiftc -swift-version 6 -module-cache-path /tmp/DreamTravelSwiftModuleCache \
    -o /tmp/DreamTravelTravelToolFixtureCheck \
    DreamTravelMobile/Agent/AgentContracts.swift \
    DreamTravelMobile/Agent/TripVerifier.swift \
    DreamTravelMobile/Agent/MockTravelPlanning.swift \
    DreamTravelMobile/Agent/AgentRuntime.swift \
    DreamTravelMobile/Services/TravelProviderConfiguration.swift \
    DreamTravelMobile/Services/TravelHTTPTransport.swift \
    DreamTravelMobile/Services/TencentTravelAPI.swift \
    DreamTravelMobile/Services/DeepSeekConnection.swift \
    DreamTravelMobile/Services/DeepSeekResponsesPlanningAdapter.swift \
    DreamTravelMobile/Services/DiscoveryService.swift \
    DreamTravelMobile/Services/ReferenceLibrary.swift \
    DreamTravelMobile/Services/PlaceResearchService.swift \
    DreamTravelMobile/Services/PlaceReservation.swift \
    DreamTravelMobile/Models/MobileItinerary.swift \
    DreamTravelMobile/Style/PlanThemeCatalog.swift \
    DreamTravelMobile/Features/Planning/TripPlanningViewModel.swift \
    Tests/DiscoveryFixtureCheck.swift \
    Tests/PlaceResearchFixtureCheck.swift \
    Tests/TravelToolFixtureCheck.swift
NSUnbufferedIO=YES /tmp/DreamTravelTravelToolFixtureCheck
