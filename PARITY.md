# Desktop ⇄ iPhone feature parity

The rule: the phone copies the desktop — same rows, same actions, same look — not a
re-interpretation. This is the checklist. Update it when either side changes.

Legend: ✅ same on the phone · 🟡 partial (says how) · ❌ not on the phone yet · ➖ makes no sense on a phone

Last full pass: 29 Aug 2026 evening (ios sweep in dark mode; desktop `0068ba7`).

## Sidebar (`Sidebar.tsx`)

| Desktop | Phone | Notes |
|---|---|---|
| Computer row | ✅ | opens the Computer chat; the desk view itself is ❌ (see Computer) |
| Browse group, `+` new tab, "Open a tab to browse" | ✅ | `workspace.createBrowser` |
| Project groups, `+` add project (folder dialog) | ✅ | folder picker of the Mac (`fs.dirs`), home-rooted |
| Group rename / delete, `+ New group` | ✅ | context menu on the header |
| Group collapse caret | 🟡 | drawn, not yet toggling (`toggleCollapse`) |
| Project row: status, kind glyph/favicon, name, `⎇` chip | ✅ | |
| Ahead/behind on the chip | ❌ | `gitAheadBehind` exists on the Mac; add to `tree.list` |
| Unread dot on chats/projects | ❌ | needs `unread` in `chat.list` (the Mac tracks it per window today) |
| × remove project | ✅ | swipe |
| Nested repos tree, "Start session →" | ✅ | `workspace.add` |
| Nested conversations (when > 1), spinner while working | ✅ | |
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
| New chat creates a **worktree** on a git repo | ❌ | phone's `chat.create` makes a plain chat; add `worktree.create` + Keep/Discard on delete |
| Keep / discard a worktree chat's changes | ❌ | `keepWorktreeChat` |
| Browser preview beside the chat (real, interactive) | 🟡 | live mirror + URL + back/forward/reload + "Send to agent"; no tapping/typing into the page |
| Layout toggle (chat beside / below the page) | ➖ | |
| Files tree | ✅ | folder at a time + filter |
| File viewer (text, Markdown rendered, images, PDF) | 🟡 | text + images + Markdown rendered; PDF ❌ |
| File **editor** (Edit → Save) | ❌ | needs `files.write` |
| Drop files into the project | ➖ | share-sheet import later |
| Todo board: columns, add, edit, move, tags, images | 🟡 | columns/add/edit/move ✅; tags read-only; card images ❌ |
| Routines: list, enable, run now, last run | ✅ | |
| Routine run view (live transcript of a run) | ❌ | `lastRunTranscript` is on the Mac; a viewer is needed |
| Create a routine | 🟡 | ask the agent (`create_routine`), same as the desktop |
| Simulator pane (iOS simulator mirroring) | ❌ | would be a screenshot mirror like the browser; `sim_*` tools exist on the Mac |
| Background strip (long-running shells) | ❌ | `bg:tail` on the Mac; needs an RPC + a strip |
| Ports strip (dev servers) | ❌ | |

## Chat (`EasyChat.tsx`)

| Desktop | Phone | Notes |
|---|---|---|
| Streaming reply, Markdown, code blocks with Copy | ✅ | |
| Collapsed tool steps, results, diffs | ✅ | |
| Ask-block choices | ✅ | |
| Per-turn footer (time, tokens, cost) | ✅ | |
| Model / Mode pickers (restart on change) | ✅ | |
| Approvals (Ask mode), guardrail prompts | ✅ | + push with Approve/Deny |
| Interrupt (Stop) | ✅ | |
| Paste / attach images | ✅ | photos, browser capture |
| `/` commands | ✅ | |
| `@` file mentions in the composer | ❌ | needs `files.list` wired to the composer |
| Tasks panel (TodoWrite / TaskCreate) | ✅ | shown when the agent uses them |
| Unread marking | ❌ | |
| Rename / delete conversation | ✅ | |
| Search across conversations | ✅ | phone-only convenience |
| Optimistic send, offline queue | ✅ | phone-only |
| Voice dictation | ✅ | phone-only |

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
| iPad split layout | ❌ |
| Live Activity, widgets, share extension, Watch | ❌ (each needs a new target / capability) |

## Next, in order

1. Worktree chats from the phone (`worktree.create`, Keep/Discard) — the biggest behavioural gap.
2. Unread + ahead/behind in `tree.list` / `chat.list`; group collapse.
3. `files.write` (editor), PDF in the viewer.
4. `@` file mentions.
5. Routine run viewer; simulator mirror; background/ports strips.
6. Dashboard, Calendar, Skills screens.
7. Reorder by drag.
