# SuperAgent iOS — plan

The full cross-repo plan (protocol, desktop changes, milestones) lives in the desktop repo:
`superagent-desktop/docs/SPEC-companion.md`. This file is the iOS-side summary so it is visible from here.

## What the app is

A thin client for the SuperAgent desktop app running on your own Mac. The Mac is the source of truth;
the phone subscribes to per-chat event logs, sends prompts, and answers approvals — from anywhere.
Both sides dial OUT to a tiny blind relay (open source, project-hosted by default, one Docker command
to self-host), so it works behind any NAT with no router or network setup. Frames are end-to-end
encrypted with a per-device key from the pairing QR; push notifications are sent by the Mac straight
to APNs with your own `.p8` key.

## Status (29 Aug 2026)

Phase 1 ("feels like SuperAgent") is built and verified in the simulator against a dev desktop:
desktop palette light+dark, app icon, sidebar-style home (groups, favicons, `⎇ main` chips,
status, previews), conversation list with rename/delete, block Markdown with code blocks,
collapsed step groups with results, diff cards, ask-block choices, per-turn footers, Model/Mode
pills (agent restarts on the same session when they change), photos, dictation, "/" commands.
Next: Phase 2 panels (Tasks, Board, Routines, Files, git), then Phase 3 (Live Activity, widgets,
iPad, share sheet, Watch).

## Milestones (iOS side)

| M | Deliver | Depends on desktop |
|---|---|---|
| M2 | Pair via QR (camera), relay transport + E2E crypto (HKDF + ChaChaPoly), machines → workspaces → chat navigation, live transcript with streaming row, composer with photos, resume-after-background | M1 event log + M2 relay + companion |
| M3 | Reconnect hardening, "Mac unreachable" states, in-app approval banner + sheet, presence reporting | M3 approvals over the wire |
| M4 | Push registration, notification categories (Approve `.authenticationRequired` / Deny / Open), approve from the lock screen in a background task | M4 direct APNs |
| M5 | Live Activity for a running turn, Notification Service Extension, browser screenshots, TestFlight | — |

## Layout (target state)

```
SuperAgent/Sources/
  App/  Protocol/  Connection/  Pairing/  Store/  Push/
  Features/{Machines,Workspaces,Chat,Settings}
SuperAgentTests/           protocol fixtures shared with desktop (fixtures/companion/*.json)
SuperAgentNotifications/   NSE (M5)
SuperAgentActivity/        Live Activity widget (M5)
```

Info.plist additions: `NSCameraUsageDescription` only. Capabilities: Push Notifications, Time Sensitive
Notifications, App Groups (`group.dev.superagent`, from M5). No local-network keys.

## Rules of the road

- The wire format is defined by the desktop (`src/shared/companion-protocol.ts`); `Sources/Protocol/Frames.swift`
  mirrors it and both test suites decode the same JSON fixtures.
- Never trust a `seq` gap: drop and re-subscribe with `afterSeq: lastSeen`.
- Device secret, token, relay URL and machine id live in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`), never in UserDefaults.
- Every frame is sealed/opened with the per-direction keys; a frame whose counter does not increase is dropped.
- Foreground-first: assume the socket is dead every time the app comes back.
