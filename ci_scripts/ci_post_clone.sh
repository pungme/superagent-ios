#!/bin/sh
# Xcode Cloud runs this right after cloning, before it resolves packages.
# The .xcodeproj is generated from project.yml and not committed, so make it here.
set -eux
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

XCODEGEN_VERSION=2.46.0
if ! command -v xcodegen >/dev/null 2>&1; then
  # Homebrew when it's there; otherwise the release binary, which needs nothing.
  if command -v brew >/dev/null 2>&1 && brew install xcodegen; then
    :
  else
    curl -fsSL -o /tmp/xcodegen.zip \
      "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
    unzip -q -o /tmp/xcodegen.zip -d /tmp/xcodegen
    PATH="/tmp/xcodegen/xcodegen/bin:$PATH"
    export PATH
  fi
fi

xcodegen --version
xcodegen generate
ls SuperAgent.xcodeproj/project.pbxproj
