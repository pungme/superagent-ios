# Superagent for iPhone

The phone half of [Superagent](https://github.com/pungme/superagent-desktop): follow the
agent running on your Mac, send it work, approve what it asks — from anywhere, with no
account. Pair once by scanning a code on the Mac; everything after that is end-to-end
encrypted between the two devices and only *relayed* by a blind server.

The phone mirrors the desktop one for one — the same sidebar (Computer, Browse, your project
groups, the nested repos / conversations / routines), the same project view (Files, Todo,
Routines, Browser, branch, New chat), the same chat (streaming Markdown, collapsed tool steps,
diffs, ask-block choices, per-turn cost). What's still missing is tracked in
[PARITY.md](PARITY.md).

Three repositories: [desktop](https://github.com/pungme/superagent-desktop) ·
**iOS** (this one) · [relay](https://github.com/pungme/superagent-relay).

## How it connects

- The Mac keeps one outbound WebSocket to a relay; the phone connects to the same room by the
  Mac's id. The relay ([superagent-relay](https://github.com/pungme/superagent-relay)) only
  forwards opaque frames — it never holds a key that could read one.
- Pairing: the Mac shows a QR (or a link); the phone shows the same 6-digit code; you accept on
  the Mac. That hands the phone a per-device secret; keys are derived from it (HKDF-SHA256),
  frames are AES-256-GCM.
- Push notifications (done / needs you / approvals with Approve & Deny) come through the relay,
  which holds the APNs key for the App Store build. A self-hosted relay works without push.
- With the Mac asleep the app still reads: sidebar, conversations and recent transcripts are
  cached on the phone.

## Build

```sh
brew install xcodegen      # once
make open                  # generates SuperAgent.xcodeproj and opens it
make test                  # Swift Testing, on the first iPhone simulator
```

The `.xcodeproj` is generated from `project.yml` and git-ignored — edit `project.yml`, not the
project. To run on a device, set your own `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode →
Signing & Capabilities) and change the bundle id; the default id belongs to the App Store build.

- iOS 17+, SwiftUI, Swift 6 strict concurrency
- Layout: `App/` (state, theme from the desktop's CSS), `Protocol/` (wire frames, shared with the
  desktop's `companion-protocol.ts`), `Connection/` (crypto, relay transport, connection),
  `Store/` (paired Macs, offline cache), `Pairing/`, `Push/`, `Features/` (sidebar, chat,
  files, board, routines, browser mirror)
- `SuperAgentTests/Fixtures` are copies of the desktop's wire fixtures (`make fixtures` refreshes
  them); both test suites decode the same files.

## Testing against a desktop

Run the desktop from source with a scratch profile and a local relay, then pair the simulator by
pasting the link the Mac's Settings → Phone offers:

```sh
# relay
cd ../relay && PORT=8790 npx tsx src/node.ts
# desktop
cd ../desktop/app && COVE_USER_DATA=/tmp/superagent-dev COVE_RELAY_URL=ws://127.0.0.1:8790 npx electron-vite dev
```

## License

MIT — see [LICENSE](LICENSE).
