# App Store submission: Superagent for iPhone and iPad

Everything the App Store Connect version page asks for, ready to paste or already pasted.
App Store Connect app: **SuperAgent - Companion app** (id 6806598776), version **1.0**.

## What App Review sees

The app needs a Mac running Superagent to be useful, and a reviewer has none. So:

- **Demo mode** (in the app): the first screen has **Try the demo**. It opens the real app
  with a made-up Mac: sample projects and conversations, the Today tab, an approval, the
  browser page, "Control this Mac". Nothing is sent anywhere. Settings → Paired Macs →
  **Leave the demo** goes back to the first screen.
- No sign-in. Untick "Sign-in required" in App Review Information.

## Fields

**Name** `SuperAgent - Companion app` (as created; 30 characters at most)
**Subtitle** `A home for your agent` (already set)
**Promotional text** (170)
> Follow your coding agents from anywhere. Approve what they ask, answer their questions, hand them to-dos and take over your Mac when you need to.

**Keywords** (100) `coding agent,ai,remote,mac,developer,approve,todo,calendar,companion,terminal,programming,assistant`
(No other company's product names in the keywords: App Review rejects those.)

**Support URL** https://superagent.computer/support
**Marketing URL** https://superagent.computer
**Privacy Policy URL** https://superagent.computer/privacy
**Copyright** `2026 Worathiti Manosroi`
**Category** Developer Tools (primary), Productivity (secondary)

**Description** (4000)
```
Superagent for iPhone is the companion to Superagent on your Mac, the home for your coding agent.

Your agents keep working on your Mac. This app lets you follow them, answer them and send them work from anywhere.

• Today: your day on one screen. The calendar, every project's open to-dos and the agents at work. Hand a to-do to an agent with one tap.
• Follow every conversation: each step the agent takes, the files it reads and edits, and its answers.
• Approve or deny what it asks to run. Answer its questions with a tap.
• Send it work: type it, dictate it, or share a link, a photo or a file from any app.
• See the page it is working on: the Mac's browser floats above the conversation.
• Take over your Mac: its screen, trackpad and keyboard on your phone, after you allow it on the Mac and confirm with Face ID.
• Save a prompt for later, see your Mac's battery, and get a notification when an agent is done or needs you.
• Works on iPhone and iPad.

Private by design. There is no Superagent account and no Superagent server. Your phone and your Mac talk through an end-to-end encrypted relay that cannot read a thing. No analytics, no ads, no tracking.

You need Superagent on a Mac to use it (free, at superagent.computer). No Mac yet? Tap "Try the demo" to look around with sample data.

Open source (MIT): github.com/pungme/superagent-ios
```

**Review notes** (4000)
```
Superagent for iPhone is a companion to the Superagent app on a Mac. It does not need an account or a sign-in.

To review without a Mac: open the app and tap "Try the demo" on the first screen. It opens the full app with a made-up Mac (sample projects, conversations, calendar and to-dos). Nothing is sent anywhere. Things to look at:
- Today tab: calendar, to-dos (tap "Hand to agent"), agents.
- Projects tab, then a conversation: the agent's steps, its answer and a question with options.
- Settings → Skills; Settings → Paired Macs → Leave the demo returns to the first screen.

What the demo cannot show, because it needs a real Mac: pairing (the camera scans a code shown by the Mac), push notifications, and "Control this Mac" (the Mac must allow it in a dialog on the Mac, then the phone shows the Mac's screen). The app's camera, microphone, speech and Face ID permissions are used only for those: scanning the pairing code, dictating a message, and confirming control of the Mac.

The source of this app and of the Mac app and relay is public (MIT): github.com/pungme/superagent-ios
```

## Screenshots

`screenshots/store/` (made by `make-screenshots.py` from the raw captures in `screenshots/iphone` and `screenshots/ipad`):

| Set | Size | Files |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | `iphone-1-today` … `iphone-6-projects` |
| iPad 13" | 2064 × 2752 | `ipad-1-chat`, `ipad-2-approve`, `ipad-3-remote` |

To retake the raw ones: build the Debug app for a 6.9" iPhone simulator and a 13" iPad simulator,
copy a page picture to the app's Documents as `harness-page.jpg`, and launch with the demo flags:

```
-sidebarHarness -tab activity -withBattery                                       # Today
-sidebarHarness -openChat c1 -tab projects -storeChat -noKeyboard                # conversation
-sidebarHarness -openChat c1 -tab projects -storeChat -toolApproval -noKeyboard  # approval
-sidebarHarness -openChat c1 -tab projects -storeChat -withPage -noKeyboard      # page beside the chat
-remoteHarness -remoteState active                                               # control this Mac
-sidebarHarness -tab projects -withBattery                                       # projects
```

## Answers for the questionnaires (yours to confirm in App Store Connect)

- **App Privacy**: Data Not Collected. (No analytics, no ads, no tracking, no SDKs; the privacy manifest says the same.)
- **Age rating**: 4+. No objectionable content. Web access: the app can show a page from the user's own Mac, it has no browser of its own.
- **Encryption**: `ITSAppUsesNonExemptEncryption` is false in the Info.plist (only Apple's own encryption and standard end-to-end encryption libraries).
- **Content rights / third-party content**: none.
- **Pricing**: free. **Availability**: all territories, or as you prefer.

## Before pressing Add for Review

1. A build that has Try the demo and the privacy manifest: push this repo (Xcode Cloud makes a TestFlight build), then pick it under Build.
2. Upload the screenshots (store folder) in the version's Screenshots section.
3. Contact information (name, phone, email) under App Review Information.
4. App Privacy, Age Rating, App Compliance, Pricing and Availability.
