#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${1:-debug}"
build_dir="${project_dir}/Build"
app_dir="${build_dir}/DreamTravel.app"

cd "${project_dir}"
swift build --configuration "${configuration}"
binary_dir="$(swift build --configuration "${configuration}" --show-bin-path)"

mkdir -p "${app_dir}/Contents/MacOS"
cp "${binary_dir}/DreamTravelApp" "${app_dir}/Contents/MacOS/DreamTravelApp"
cp "${project_dir}/AppResources/Info.plist" "${app_dir}/Contents/Info.plist"

codesign --force --sign - "${app_dir}" >/dev/null
echo "Built ${app_dir}"
