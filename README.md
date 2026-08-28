# SuperAgent iOS

iOS companion app for [SuperAgent desktop](https://github.com/pungme/superagent-desktop).

## Setup

```sh
brew install xcodegen   # once
make open               # generates SuperAgent.xcodeproj and opens it
```

The `.xcodeproj` is generated from `project.yml` and git-ignored — edit `project.yml`, not the project file.
Set your team ID in `project.yml` (`DEVELOPMENT_TEAM`) or in Xcode → Signing & Capabilities.

- Bundle ID: `dev.superagent.ios`
- Min iOS: 17.0, SwiftUI, Swift 6 (strict concurrency)
- Tests: `make test` (Swift Testing)
