# Desktop ⇄ iPhone feature parity

The rule: the phone copies the desktop — same rows, same actions, same look — not a
re-interpretation. This is the checklist. Update it when either side changes.

The look is the desktop's; the *structure and sizes* are the phone's — a native list with
sticky headers, separators and swipe actions, at 40–44 pt rows — every row is a 40–44 pt target, which is
why the sidebar is roomier than the Mac's 24 pt rows.

Type is the desktop's sizes *at the default text size only*: `.superFont(13)` renders 13 pt there
and scales from it, so Larger Text moves the app the way it moves the rest of iOS. Dense chrome —
the composer's round buttons, the connection banner's glyph — stops growing early so the words keep
the room; the project bar and the Model/Mode pills scroll sideways rather than truncate.

Legend: ✅ same on the phone · 🟡 partial (says how) · ❌ not on the phone yet · ➖ makes no sense on a phone

Last full pass: 31 Aug 2026 evening (desktop 1.7.16 — the folder's conversation stays
in the folder: only a chat opened with "+ New chat" cuts a branch, and opening a project
never creates one. Also new since the pass below: the simulator mirror, file handover
cards, relay usage in Settings, and unread.)

Previous pass: 30 Aug 2026 evening (desktop `8c71283`, 1.7.13 — the branch model:
the sidebar is one row per branch, main included; a branch is cut on a chat's
first message and named from it, so an unused chat leaves nothing behind; git is
asked what exists rather than the app trusting what it recorded).

## Sidebar (`Sidebar.tsx`)

| Desktop | Phone | Notes |
|---|---|---|
| Computer row | ✅ | opens the Computer chat; the desk view itself is ❌ (see Computer) |
| Chats row (the Computer's conversations, plain) | ✅ | opens its own list — New chat, rename, delete, previews |
| Browse group, `+` new tab, "Open a tab to browse" | ✅ | `workspace.createBrowser` |
| Project groups, `+` add project (folder dialog) | ✅ | folder picker of the Mac (`fs.dirs`), home-rooted |
| Group rename / delete, `+ New group` | ✅ | context menu on the header |
| Group collapse caret | 🟡 | collapses on the phone (44 pt target); the Mac keeps its own state — no `group.update` RPC yet |
| Project row: status, kind glyph/favicon, name, `⎇` chip | ✅ | |
| Ahead/behind on the chip | ❌ | `gitAheadBehind` exists on the Mac; add to `tree.list` |
| Unread dot on chats/projects | ✅ | the phone's own: a conversation that has moved since you last had it open, kept per Mac on the phone. The Mac's unread is its window's, and says nothing about what *you* have read |
| × remove project | ✅ | swipe |
| Nested repos tree, "Start session →" | ✅ | `workspace.add` |
| Project row **is** the folder's own conversation; the list below is the extras | ✅ | tapping the project opens the root chat, not whichever was touched last |
| Nested rows: one per branch, plus chats with no branch yet; none means no list | 🟡 | rows render from `worktrees.list`; needs a Mac new enough to answer it, and falls back to listing conversations otherwise |
| A branch with no conversation yet reads as one, and says so | ✅ | shown as `⎇ name · no chat yet`, not tappable |
| Nested routines | ✅ | tap opens the Routines panel |
| Drag to reorder projects / groups | ❌ | `moveWorkspace` / `moveGroup` need RPCs + drag UI |
| Settings ⚙ | ✅ | phone's own settings (pair, remove Mac) |
| Hide sidebar ⇤ | ➖ | |
| Design (flat rows, small-caps headers, tree lines) | ✅ | values from `main.css` |

## Project view (`WorkspaceView.tsx`)

| Desktop | Phone | Notes |
|---|---|---|
| Opens on the active conversation | ✅ | most recent, or a fresh one |
| Header: Files, Todo, name, path, branch chip, New chat | ✅ | bar above the chat; path omitted |
| First message cuts a branch, named from what you asked for | 🟡 | the Mac does it for a chat started with "+ New chat" wherever the message came from, and the phone sees the branch rows; the phone still cannot choose the name, or Keep/Throw away the work |
| Keep / discard a worktree chat's changes | ❌ | `keepWorktreeChat` |
| Browser preview beside the chat (real, interactive) | 🟡 | docked **above** the chat when the Mac has a page open (drag to resize, compass hides it, collapses for the keyboard), URL bar, back/forward/reload, "Send to agent"; no tapping/typing into the page |
| Layout toggle (chat beside / below the page) | ➖ | |
| Files tree | ✅ | a folder per screen (push, swipe back), filter searches everything below |
| File viewer (text, Markdown rendered, images, PDF) | ✅ | PDFs come over in `files.chunk` slices and render in PDFKit, so the text stays selectable |
| File **editor** (Edit → Save) | ❌ | needs `files.write` |
| Drop files into the project | ➖ | share-sheet import later |
| Todo board: columns, add, edit, move, tags, images | 🟡 | columns/add/edit/move ✅; tags read-only; card images ❌ |
| Routines: list, enable, run now, last run | ✅ | |
| Routine run view (live transcript of a run) | ❌ | `lastRunTranscript` is on the Mac; a viewer is needed |
| Create a routine | 🟡 | ask the agent (`create_routine`), same as the desktop |
| Simulator pane (iOS simulator mirroring) | 🟡 | mirrored like the browser, docked above the chat, and it takes taps; it backs off to 6s when nothing changes |
| Background strip (long-running shells) | ❌ | `bg:tail` on the Mac; needs an RPC + a strip |
| Ports strip (dev servers) | ❌ | |

## Chat (`EasyChat.tsx`)

| Desktop | Phone | Notes |
|---|---|---|
| Streaming reply, Markdown, code blocks with Copy | ✅ | |
| Collapsed tool steps, results, diffs | ✅ | |
| Ask-block choices | ✅ | |
| "Working Ns" while a turn runs | ✅ | the desktop shows no per-turn tokens or cost, and neither do we |
| Context meter (used / window, model) | ❌ | the desktop's bar under the composer |
| Model / Mode pickers (restart on change) | ✅ | |
| Approvals (Ask mode), guardrail prompts | ✅ | + push with Approve/Deny |
| Interrupt (Stop) | ✅ | |
| Paste / attach images | ✅ | photos, browser capture |
| `/` commands | ✅ | |
| `@` file mentions in the composer | ❌ | needs `files.list` wired to the composer |
| Tasks panel (TodoWrite / TaskCreate) | ✅ | shown when the agent uses them |
| Unread marking | ✅ | opening a conversation reads it, and it keeps pace while you stay in it |
| Rename / delete conversation | ✅ | |
| Search across conversations | ✅ | phone-only convenience |
| Optimistic send, offline queue | ✅ | phone-only |
| Voice dictation | ✅ | phone-only |
| Agent's `open_file` opens the viewer | ✅ | `openFile` push frame; opens only while you are in the chat that asked |

## Computer (`ComputerPanel`, `DesktopBrowser`, `DesktopWindow`, `FolderView`)

| Desktop | Phone | Notes |
|---|---|---|
| Computer chat (agent that drives the Mac), several conversations, New chat | ✅ | nested under the Computer row like a project's |
| The desk: windows, folders, desktop tabs, file windows | ❌ | a screenshot mirror (`describeDesktop` + captures) is the realistic phone form |

## Whole-window sections

| Desktop | Phone | Notes |
|---|---|---|
| Dashboard (usage, trends) | ❌ | `getDashboard()` exists; needs an RPC + a screen |
| Calendar | ❌ | `calendar:*` IPC exists; needs RPCs + a screen |
| Skills panel | ❌ | `skills.ts`; needs RPCs + a screen |
| Settings: appearance, notifications, advanced, about | 🟡 | phone has its own; Mac-side settings aren't editable from the phone |
| Settings → Phone (pair, test notification, keep-awake) | ➖ | Mac-side by nature |
| Onboarding / intro / hook consent / updates | ➖ | |

## Phone-only

| Feature | Status |
|---|---|
| Pairing by QR / link, multiple Macs | ✅ |
| Push notifications (done, needs-you, approvals with actions) | ✅ |
| Offline cache (sidebar, chats, recent transcripts) | ✅ |
| Dynamic Type — every size scales, Larger Text moves the whole app | ✅ |
| iPad split layout | ✅ | sidebar and detail side by side, and the page or simulator beside the conversation rather than above it |
| Live Activity, widgets, share extension, Watch | ❌ (each needs a new target / capability) |

## Next, in order

1. Worktree chats from the phone (`worktree.create`, Keep/Discard) — the biggest behavioural gap.
2. Ahead/behind in `tree.list`; group collapse. (Unread landed 31 Aug, phone-side.)
3. `files.write` (editor), PDF in the viewer.
4. `@` file mentions.
5. Routine run viewer; simulator mirror; background/ports strips.
6. Dashboard, Calendar, Skills screens.
7. Reorder by drag.
