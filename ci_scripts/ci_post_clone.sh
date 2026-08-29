#!/bin/sh
# Xcode Cloud runs this right after cloning, before it resolves packages.
# The .xcodeproj is generated from project.yml and not committed, so make it here.
set -e
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
xcodegen generate
ls SuperAgent.xcodeproj/project.pbxproj
