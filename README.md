# Lumen ✨

**Your Mac, one keystroke away.** Lumen is a fast, native macOS launcher with a
built-in AI assistant — search anything, do anything, ask anything. Press
`⌥ Space` and go.

Built in pure Swift + SwiftUI. No Electron. A single small binary that starts
instantly and lives quietly in your menu bar.

## Lumen AI

AI is built in and works out of the box — no account, no API key, no setup.

- **Quick AI** — type any question, press `Tab`, get a streaming answer right
  in the launcher. Follow-ups, regenerate, copy, or paste the answer straight
  into the app you came from
- **AI Chat** — a full chat workspace: persistent history, search across
  conversations, pin/rename/archive, editable messages, file attachments,
  model picker, creativity control, always-on-top
- **AI Commands** — Improve Writing, Fix Spelling & Grammar, Explain Simply,
  Change Tone, Find Bugs in Code, Summarize — run on your selected text in any
  app, and paste the result back in place
- **Quick Fix** — double-tap Right Shift to fix the grammar of selected text
  anywhere, instantly, in place
- **Multiple models** — from fast everyday models to reasoning and live
  web-search models, switchable mid-conversation
- **Personalization** — tell Lumen AI who you are once (Edit AI Profile) and
  every answer fits you

## Daily driver

- **Widgets** — the launcher opens to your day: date, next meeting, reminders
  due, and live local weather
- **Calendar** — see upcoming events by typing `today` / `schedule`. Works
  with iCloud and **Google Calendar** (add your Google account in System
  Settings → Internet Accounts, or run *Connect Google Calendar* in Lumen)
- **Reminders** — due reminders show in the launcher; create them naturally:
  type `remind me to call John at 5pm` and hit ⏎
- **Notion** — search your Notion workspace from the launcher (*Set Notion
  Token* to connect)

## Launcher

- App search with frecency (your most-used apps rank first), `⌘1–9` shortcuts
- File search via the Spotlight index
- Clipboard history (password-manager-safe), searchable, `clip` to browse
- Snippets (paste anywhere), Quicklinks with `{query}` templates
- Calculator + unit conversions: `2^10/4`, `10 km to mi`, `72 f to c`
- Window management: halves, quarters, maximize, center
- Emoji picker, system commands (Sleep, Empty Trash, Dark Mode), web fallback

## Build

Requires macOS 13+ and Xcode Command Line Tools.

```bash
./make-app.sh     # builds Lumen.app (bakes in the AI key — see below)
open Lumen.app
```

Development: `swift build && .build/debug/Lumen --show`

### AI service key (maintainers only)

End users never handle keys. The build machine provides one, via either:

- `LUMEN_AI_KEY=<key> ./make-app.sh`, or
- the key already saved in the build machine's Lumen settings

`make-app.sh` bakes it into the app bundle (`LumenAIKey` in Info.plist).
**The key is never committed to this repository.** For production distribution,
route requests through your own backend proxy instead of shipping a key.

## Permissions (all optional)

| Permission | Unlocks |
|---|---|
| Accessibility | Paste-back, Quick Fix, window management |
| Calendars & Reminders | Schedule widgets, events, reminders |
| Automation | Empty Trash, Toggle Dark Mode |

## Keys

`⌥ Space` open · `Tab` Ask AI · `↑↓` navigate · `⏎` open/run · `⌘1–9` quick
open · `⎋` close · double Right-Shift = Quick Fix

## Roadmap

- Custom AI command builder with hotkeys
- AI tool-calling (search files, run safe commands, with confirmation)
- Extension/plugin system, MCP support
- Dictation
- Onboarding, preferences UI, custom hotkeys, themes
- Team features: shared snippets, quicklinks and AI commands
