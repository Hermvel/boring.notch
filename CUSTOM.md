# Boring Notch — personal build (2.8.0)

Fork of [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) with extra sections.

## What's different

- **Sidebar layout** — sections on the left (1/5), content on the right (4/5).
- **Задачи** — Things 3 via a self-hosted [things-cloud-mcp](https://github.com/mattydsmith/things-cloud-mcp) server: list/project picker, tag filters, two columns, complete/undo. Visible areas/projects are chosen in Settings → Tasks.
- **Календарь** — month grid with arrows and event dots + upcoming events by day.
- **Буфер** — clipboard history (memory only, skips password-manager secrets) and screenshots side by side.
- **AirDrop** — the original shelf, renamed.
- Section is remembered for 3 minutes after the notch closes, then Home (music).
- Scrolling never closes the notch; swipe-up-to-close works on Home with a trackpad only.
- Full Russian localization (`scripts/add_ru_localization.py` re-applies it after upstream merges).
- Auto-updates are **off** — upstream updates would replace this build.

All new code lives in `boringNotch/Custom/`.

## Build and install

1. Open `boringNotch.xcodeproj` in Xcode 26+, set your Team for both targets (Signing & Capabilities).
2. **Product → Archive** → Organizer → **Distribute App → Custom → Copy App**.
3. Move `Boring Notch.app` to `/Applications`, launch it, enable *Launch at login* in Settings.
4. Settings → Tasks: server URL (`https://…/mcp`) → **Test connection**.
