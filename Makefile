.PHONY: project build test open

# First available iPhone simulator UDID (override: make test SIM=<udid>)
SIM ?= $(shell xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')

project:
	xcodegen generate

build: project
	xcodebuild -project SuperAgent.xcodeproj -scheme SuperAgent -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -quiet && echo "BUILD OK"

test: project
	xcodebuild -project SuperAgent.xcodeproj -scheme SuperAgent -destination 'platform=iOS Simulator,id=$(SIM)' test CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'Test run with|TEST (SUCCEEDED|FAILED)|error:'

open: project
	open SuperAgent.xcodeproj

# Refresh the wire-format fixtures from the desktop repo (they are the contract
# both test suites decode). Run after the desktop fixtures change.
fixtures:
	cp ../desktop/app/src/shared/fixtures/companion/frames.json ../desktop/app/src/shared/fixtures/companion/crypto-vectors.json SuperAgentTests/Fixtures/
