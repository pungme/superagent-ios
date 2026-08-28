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
