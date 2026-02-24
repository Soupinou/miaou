# Miaou

A macOS desktop pet that notifies you when Claude Code (or Codex) needs attention. Built in Swift, distributed as a self-built `.app` bundle.

## Build & Test

```bash
# Build and install to /Applications (also configures hooks + CLI)
./install.sh

# Or use the CLI
miaou update      # Rebuild, reinstall, restart
miaou stop        # Quit the app
miaou start       # Launch the app
```

Build uses `swift build -c release`. The `scripts/bundle-app.sh` script wraps the binary into a `.app` bundle with Info.plist and resources.

**Bundle identifier:** `com.miaou.app`
**URL scheme:** `miaou://`
**Preferences:** stored in UserDefaults (accessed via `defaults read com.miaou.app`)

## Architecture

```
Miaou/
  App/
    MiaouApp.swift              SwiftUI entry point (@main)
    AppDelegate.swift           URL scheme handler, status bar, hotkey (⌥⌥)
  Views/
    CatWindowController.swift   Main window (NonActivatingWindow), tooltip, tmux switching
    CatView.swift               NSView subclass, rendering, drag & drop, click handling
  Models/
    CatState.swift              State enum (idle/walking/sleeping/attentionNeeded), CatType registry
    CatPreferences.swift        UserDefaults wrapper, posts NotificationCenter notifications on change
    RoamingBehavior.swift       State machine, movement timer (60fps), decision timer (4s)
  Animation/
    CatAnimator.swift           Frame-based sprite animation at 3fps
    SpriteManager.swift         Loads PNGs from Resources, caches frames, handles sprite aliases

scripts/
    cli.sh                      CLI entry point (install/update/start/stop/uninstall)
    bundle-app.sh               Builds .app from swift binary + resources + Info.plist
    claude-code-notify.sh       Hook script (installed to ~/.claude/) — detects tmux session, fires miaou://notify
    miaou-codex-notify.sh       Same but for OpenAI Codex
```

## Key patterns

- **NonActivatingWindow**: subclass of NSWindow with `canBecomeKey = false` and `canBecomeMain = false` — prevents the cat from stealing focus.
- **Preferences**: `CatPreferences.shared` is a singleton wrapping UserDefaults. All setters post `Notification.Name.catPreferencesChanged` so UI reacts immediately.
- **Sprite aliases**: in `SpriteManager.spriteAliases`, maps pet IDs to share sprites (e.g. `"chawy": "soupinou"`). Avoids duplicating PNG files.
- **State machine**: `RoamingBehavior` drives everything. The 60fps movement timer only runs during `walking` or `attentionNeeded` states. During `sleeping`/`idle`, no timer runs (0 CPU).
- **Hotkey**: double-tap Option key detected via both global + local NSEvent monitors in AppDelegate (global catches events to other apps, local catches events to our app).

## Adding a new pet

1. Create `Miaou/Resources/<petname>/` with these PNGs (6 frames each, 64x64 base size):
   ```
   00_petname_walk.png  through  05_petname_walk.png
   00_petname_sleep.png  (only 1 frame needed)
   00_petname_notification.png  through  05_petname_notification.png
   ```
2. Add to `CatType.allCats` in `Miaou/Models/CatState.swift`:
   ```swift
   CatType(id: "petname", displayName: "Display Name", notificationMovement: .side)
   ```
   Use `.side` for horizontal bounce on notification, `.none` for vertical-only bounce.
3. If the new pet reuses another pet's sprites, add an alias in `SpriteManager.spriteAliases` instead of copying PNGs.
4. `miaou update` to rebuild and test.

## Hook system

The install script (`scripts/cli.sh`) auto-configures hooks in `~/.claude/settings.json`:
- **Stop hook**: fires `claude-code-notify.sh` when Claude Code finishes
- **Notification hook**: fires on permission prompts

The Python inline script in `install_hooks()` merges into existing settings (never overwrites). It creates a `.bak` backup before modifying. `uninstall_hooks()` only removes hooks containing `claude-code-notify` — all other hooks are preserved.

## Notification flow

```
Hook fires → claude-code-notify.sh detects tmux session → open "miaou://notify?target=SESSION:WINDOW.PANE&title=..."
→ AppDelegate receives URL → CatWindowController.triggerAttention() → cat bounces + status bar animates
→ User clicks cat → tmux switch-client + activate terminal app → cat returns to idle
```

Auto-dismiss: if the user manually switches to the target tmux pane, the notification clears automatically (polled every 2s).

## Security

tmux targets from `miaou://` URLs are validated with regex `^[A-Za-z0-9_.:-]+$` before any shell execution. This prevents command injection via crafted URLs.
