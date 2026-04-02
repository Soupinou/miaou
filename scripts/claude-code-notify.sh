#!/bin/bash
# Miaou notify script for Claude Code hooks.
# Detects multiplexer (cmux or tmux), finds the target pane/workspace,
# checks if the user is already focused, and skips the notification if so.

MUX=""
TARGET=""

# --- cmux detection ---
# cmux sets CMUX_WORKSPACE_ID and CMUX_SURFACE_ID in child processes
if [ -n "$CMUX_SURFACE_ID" ]; then
    MUX="cmux"
    TARGET="$CMUX_SURFACE_ID"

    # Check if cmux is frontmost — if so, user is already looking
    FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
    FRONTMOST_LOWER=$(echo "$FRONTMOST" | tr '[:upper:]' '[:lower:]')
    if [ "$FRONTMOST_LOWER" = "cmux" ]; then
        exit 0
    fi

# --- tmux detection ---
else
    # Find tmux pane by walking up process tree and matching pane PID
    find_tmux_pane() {
        local pid=$$

        declare -A pane_map
        while read -r pane_id pane_pid; do
            pane_map["$pane_pid"]="$pane_id"
        done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_pid}' 2>/dev/null)

        while [ "$pid" != "1" ] && [ -n "$pid" ]; do
            if [ -n "${pane_map[$pid]}" ]; then
                echo "${pane_map[$pid]}"
                return 0
            fi
            pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        done
        return 1
    }

    MUX="tmux"

    if tmux list-sessions &>/dev/null; then
        TARGET=$(find_tmux_pane)
        if [ -n "$TARGET" ]; then
            ACTIVE_WINDOW=$(tmux display-message -t "${TARGET}" -p '#{window_active}' 2>/dev/null)
            ACTIVE_PANE=$(tmux display-message -t "${TARGET}" -p '#{pane_active}' 2>/dev/null)

            TERMINAL_APP=$(defaults read com.miaou.app terminalApp 2>/dev/null || echo "Alacritty")
            TERMINAL_LOWER=$(echo "$TERMINAL_APP" | tr '[:upper:]' '[:lower:]')

            FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
            FRONTMOST_LOWER=$(echo "$FRONTMOST" | tr '[:upper:]' '[:lower:]')

            if [ "$ACTIVE_WINDOW" = "1" ] && [ "$ACTIVE_PANE" = "1" ] && [ "$FRONTMOST_LOWER" = "$TERMINAL_LOWER" ]; then
                exit 0
            fi
        else
            TARGET="default"
        fi
    else
        TARGET="default"
    fi
fi

# URL encode the target (basic)
TARGET_ENCODED=$(echo "$TARGET" | sed 's/:/%3A/g; s/\./%2E/g')

# Only notify if Miaou is already running (don't relaunch after quit)
if pgrep -x Miaou > /dev/null 2>&1; then
    open -g "miaou://notify?target=${TARGET_ENCODED}&mux=${MUX}"
fi
