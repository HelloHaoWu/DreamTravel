#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcrun swiftc -parse-as-library -swift-version 6 -module-cache-path /tmp/DreamTravelSwiftModuleCache \
  Tools/PublicationCheck.swift -o /tmp/DreamTravelPublicationCheck
/tmp/DreamTravelPublicationCheck --self-test
/tmp/DreamTravelPublicationCheck "$@"
