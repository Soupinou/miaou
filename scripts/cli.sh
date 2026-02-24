#!/bin/bash
# miaou CLI — manage Miaou
# Usage: miaou <command>

set -e

# Resolve project directory (works whether called via symlink or directly)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APP_NAME="Miaou"
APP_BUNDLE="$PROJECT_DIR/.build/$APP_NAME.app"
INSTALL_DIR="/Applications"
NOTIFY_DEST="$HOME/.claude/claude-code-notify.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

# ─── Helpers ───

build() {
    echo "  Building $APP_NAME..."
    "$SCRIPT_DIR/bundle-app.sh" > /dev/null 2>&1
}

quit_app() {
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "  Stopping running instance..."
        pkill -x "$APP_NAME" 2>/dev/null || true
        sleep 1
    fi
}

install_app() {
    echo "  Installing app to $INSTALL_DIR/"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -r "$APP_BUNDLE" "$INSTALL_DIR/"
}

install_notify_script() {
    echo "  Installing notify script to $NOTIFY_DEST"
    mkdir -p "$(dirname "$NOTIFY_DEST")"
    cp "$SCRIPT_DIR/claude-code-notify.sh" "$NOTIFY_DEST"
    chmod +x "$NOTIFY_DEST"
}

install_hooks() {
    echo "  Configuring Claude Code hooks..."
    python3 -c "
import json, os, sys, shutil

path = os.path.expanduser('$SETTINGS_FILE')
os.makedirs(os.path.dirname(path), exist_ok=True)

# Read or create settings
if os.path.exists(path):
    # Backup before modifying
    shutil.copy2(path, path + '.bak')
    with open(path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault('hooks', {})

stop_hook = {'hooks': [{'type': 'command', 'command': '~/.claude/claude-code-notify.sh'}]}
notif_hook = {'matcher': 'permission_prompt', 'hooks': [{'type': 'command', 'command': '~/.claude/claude-code-notify.sh'}]}

changed = False

# Add Stop hook if not present
stop_list = hooks.setdefault('Stop', [])
if not any('claude-code-notify' in str(h) for h in stop_list):
    stop_list.append(stop_hook)
    changed = True

# Add Notification hook if not present
notif_list = hooks.setdefault('Notification', [])
if not any('claude-code-notify' in str(h) for h in notif_list):
    notif_list.append(notif_hook)
    changed = True

if changed:
    with open(path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('  Hooks added to $SETTINGS_FILE')
else:
    print('  Hooks already configured.')
"
}

uninstall_hooks() {
    python3 -c "
import json, os, sys

path = os.path.expanduser('$SETTINGS_FILE')
if not os.path.exists(path):
    sys.exit(0)

with open(path) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
changed = False

for key in ['Stop', 'Notification']:
    if key in hooks:
        before = len(hooks[key])
        hooks[key] = [h for h in hooks[key] if 'claude-code-notify' not in str(h)]
        if len(hooks[key]) < before:
            changed = True

if changed:
    with open(path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('  Removed hooks from $SETTINGS_FILE')
" 2>/dev/null || true
}

install_cli() {
    local dest="$HOME/.local/bin/miaou"
    mkdir -p "$HOME/.local/bin"
    ln -sf "$SCRIPT_DIR/cli.sh" "$dest"
    echo "  Symlinked CLI to $dest"

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
        echo ""
        echo "  Add to your shell profile:"
        echo '    export PATH="$HOME/.local/bin:$PATH"'
    fi
}

launch_app() {
    echo "  Launching $APP_NAME..."
    open "$INSTALL_DIR/$APP_NAME.app"
}

is_installed() {
    [ -d "$INSTALL_DIR/$APP_NAME.app" ]
}

# ─── Commands ───

cmd_install() {
    echo "Installing Miaou..."
    echo ""
    if ! is_installed; then
        build
        install_app
    else
        echo "  App already installed, skipping build."
    fi
    if [ ! -f "$NOTIFY_DEST" ]; then
        install_notify_script
    else
        echo "  Notify script already installed, skipping."
    fi
    if [ ! -L "$HOME/.local/bin/miaou" ]; then
        install_cli
    else
        echo "  CLI already linked, skipping."
    fi
    install_hooks
    if ! pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo ""
        launch_app
    fi
    echo ""
    echo "Done! Run 'miaou update' anytime to get the latest version."
}

cmd_update() {
    if ! is_installed; then
        echo "Miaou is not installed. Run 'miaou install' first."
        exit 1
    fi

    echo "Updating Miaou..."
    echo ""
    build
    quit_app
    install_app
    install_notify_script
    echo ""
    launch_app
    echo ""
    echo "Done!"
}

cmd_start() {
    if ! is_installed; then
        echo "Miaou is not installed. Run 'miaou install' first."
        exit 1
    fi
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "Miaou is already running."
        exit 0
    fi
    launch_app
    echo "Done!"
}

cmd_stop() {
    if ! pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "Miaou is not running."
        exit 0
    fi
    quit_app
    echo "Done!"
}

cmd_uninstall() {
    echo "Uninstalling Miaou..."
    echo ""
    quit_app
    if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
        echo "  Removing $INSTALL_DIR/$APP_NAME.app"
        rm -rf "$INSTALL_DIR/$APP_NAME.app"
    fi
    if [ -f "$NOTIFY_DEST" ]; then
        echo "  Removing $NOTIFY_DEST"
        rm -f "$NOTIFY_DEST"
    fi
    if [ -L "$HOME/.local/bin/miaou" ]; then
        echo "  Removing ~/.local/bin/miaou"
        rm -f "$HOME/.local/bin/miaou"
    fi
    uninstall_hooks
    echo ""
    echo "Done!"
}

cmd_help() {
    echo "miaou — a cute desktop cat that alerts you when your CLI needs attention"
    echo ""
    echo "Usage: miaou <command>"
    echo ""
    echo "Commands:"
    echo "  install     First-time setup: build, install app + notify script, add CLI to PATH"
    echo "  update      Rebuild from source, replace app, restart"
    echo "  start       Launch Miaou"
    echo "  stop        Quit Miaou"
    echo "  uninstall   Remove app, notify script, and CLI"
    echo "  help        Show this help"
}

# ─── Main ───

case "${1:-help}" in
    install)   cmd_install ;;
    update)    cmd_update ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    uninstall) cmd_uninstall ;;
    help)      cmd_help ;;
    *)
        echo "Unknown command: $1"
        echo ""
        cmd_help
        exit 1
        ;;
esac
