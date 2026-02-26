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
- **Bundle loading**: `SpriteManager` loads sprites from `Bundle.main.resourcePath` with a fallback to `Bundle(identifier: "Miaou.Miaou")` (Swift PM resource bundle). `Bundle(identifier:)` is unreliable for SPM bundles — they have no Info.plist.

## Adding a new pet

### Required sprites

Create `Miaou/Resources/<petname>/` with PNGs at 512x512 pixels (displayed at 64x64 base window size). Naming convention: `{NN}_{petname}_{animation}.png` (e.g., `00_lou_walk.png`, `03_lou_notification.png`).

`SpriteManager` loads up to 6 frames per animation and handles fewer gracefully. The 7 animation types (from `AnimationType` enum):

**Required:**
| Animation | Frames | Description |
|-----------|--------|-------------|
| `walk` | up to 6 | Walking cycle |
| `sleep` | 1 | Sleeping pose |
| `notification` | up to 6 | Attention-needed bounce/alert |

**Optional (enhanced animations):**
| Animation | Frames | Description |
|-----------|--------|-------------|
| `lifted` | up to 6 | Swinging when dragged by scruff |
| `lifted_idle` | up to 6 | Held still after dragging stops |
| `walk_to_sleep` | up to 6 | Transition from walking to sleeping |
| `sleep_to_walk` | up to 6 | Transition from sleeping to walking |

Minimal sprite set: 13 PNGs (6 walk + 1 sleep + 6 notification). Full set with all optional animations: up to 37 PNGs.

### Code changes

1. Add to `CatType.allCats` in `Miaou/Models/CatState.swift`:
   ```swift
   CatType(id: "petname", displayName: "Display Name", notificationMovement: .side)
   ```
   Use `.side` for horizontal bounce on notification, `.none` for vertical-only bounce.
2. If the new pet reuses another pet's sprites, add an alias in `SpriteManager.spriteAliases` instead of copying PNGs.
3. `miaou update` to rebuild and test.

### Sprite generation with AI

Use Gemini to generate pixel art sprite sheets on a **solid blue background** (not green — pets may have green features; not checkered — impossible to cleanly remove).

Grid layout: 6 columns × rows, 512x512 per cell.

**Example Gemini prompt:**
```
Create a pixel art sprite sheet for a [color] [animal] desktop pet on a solid blue background.
Draw a 6-column grid at 512x512 per cell:
- Row 1: 6 walking frames (left to right cycle)
- Row 2: 1 sleeping frame, then 5 notification/alert frames (bouncing or excited)
- Row 3: remaining 1 notification frame, then 3 "held by scruff" swinging frames, 1 "held still" frame, empty
Style: cute, chibi proportions, consistent colors across all frames. No text labels.
```

Row 3 is optional — skip it for a minimal 13-sprite set (2 rows only).

### Extracting sprites from composite image

Use a Python script with PIL to:
1. Remove blue background: any pixel where `b > 150 and b > r + 50 and b > g + 50` → transparent
2. Despill blue fringe on edges: if `b > 80 and b > r + 20 and b > g + 20` and excess > 30 → transparent, otherwise clamp blue to `max(r, g)`
3. Find connected opaque regions via flood fill (min_size=80 to skip label text)
4. Sort regions by `(y // 500, x)` to group by row then column
5. Center each sprite on a 512x512 transparent canvas

Scale sprites to match existing pet sizes (~400x350 art within 512x512). Use `magick -filter point -resize 140%` for nearest-neighbor scaling to keep pixel art crisp.

Files go in `Miaou/Resources/{petname}/`.

### Creating animation GIFs (for PRs)

```bash
magick -dispose Background -delay 33 -loop 0 \
  Miaou/Resources/lou/0{0..5}_lou_notification.png \
  lou_notification.gif
```
- `-dispose Background` is critical — clears each frame before drawing the next, otherwise previous frames bleed through
- `-delay 33` = ~3fps (matches the app's animation speed)
- Use `<img src="..." width="128" />` in GitHub markdown to control display size

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
