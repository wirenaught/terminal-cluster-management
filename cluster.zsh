# cluster.zsh — terminal cluster management
# Source this file from ~/.zshrc

CLUSTER_BASE="$HOME/.clusters"
CLUSTER_STATE="$HOME/.config/cluster/last-cluster"

# ── prompt ────────────────────────────────────────────────────────────────────
# Shows: [cluster-name] user@host path %
# Cluster name is omitted entirely when no cluster is active.
# Uses zsh prompt substitution (setopt PROMPT_SUBST).
setopt PROMPT_SUBST

function _cluster_prompt_segment() {
  if [[ -n "$CLUSTER_DIR" ]]; then
    echo "%F{blue}[${CLUSTER_DIR:t}]%f "
  fi
}

# Line 1: colored info — cluster (if active), user@host, path
# Line 2: clean input line starting with ❯
PROMPT=$'$(_cluster_prompt_segment)%F{green}%n@%m%f %F{yellow}%~%f\n%F{cyan}❯%f '

# ── _cluster_activate (internal) ─────────────────────────────────────────────
# Set CLUSTER_DIR and persist it to the state file
function _cluster_activate() {
  local dir="$1"
  export CLUSTER_DIR="$dir"
  echo "$dir" > "$CLUSTER_STATE"
}

# ── auto-restore on shell startup ────────────────────────────────────────────
# Silently re-activate the last cluster if the directory still exists.
# This runs when the file is sourced (i.e. every new shell via .zshrc).
if [[ -z "$CLUSTER_DIR" && -f "$CLUSTER_STATE" ]]; then
  _last="$(cat "$CLUSTER_STATE")"
  if [[ -d "$_last" ]]; then
    export CLUSTER_DIR="$_last"
  fi
  unset _last
fi

# ── cluster-init ─────────────────────────────────────────────────────────────
# Usage: cluster-init [name]
# Creates a cluster directory, starts a named tmux session, opens notes.txt.
# The tmux session name IS the cluster name — it appears in the status bar
# and is what resurrect/continuum saves and restores.
# In iTerm2: attaches via -CC so tmux windows appear as native tabs.
# In Terminal.app or plain shell: attaches normally.
function cluster-init() {
  local slug="${1:+"-$1"}"
  local ts="$(date +%Y-%m-%d-%H%M)"
  local name="${ts}${slug}"
  local dir="$CLUSTER_BASE/${name}"

  mkdir -p "$dir"

  # Write join.sh — sets CLUSTER_DIR when sourced in any shell
  cat > "$dir/join.sh" <<EOF
export CLUSTER_DIR="$dir"
EOF
  chmod +x "$dir/join.sh"

  # Activate and persist
  _cluster_activate "$dir"

  # Seed notes.txt
  cat > "$dir/notes.txt" <<EOF
# cluster: ${name}
# started: $(date)
# ─────────────────────────────────────────
# session ids, commands, breadcrumbs below:

EOF

  # Seed AGENTS.md — instructions for any AI tool launched from this cluster
  cat > "$dir/AGENTS.md" <<'AGENTSEOF'
# Cluster instructions for AI sessions

This file teaches any AI tool (Claude Code, OpenCode, etc.) how to interact
with this specific cluster. Edit it any time to adjust per-cluster
conventions.

## Capture protocol
When the user asks to "capture this", "jot this down", "log this", "stick
this in cluster notes", or similar:

1. Write a 1-3 line crystallized summary of the decision, insight, or
   conclusion from the recent exchange.
2. Append it by running: `cluster-note "<your summary>"`
3. Do NOT echo to notes.txt directly — `cluster-note` handles the
   timestamp and format.

## Recall protocol
- "What's in the cluster notes?" / "what have we written down?" → run
  `cluster-notes` and summarize.
- "What have we been doing in this cluster?" → run `cluster-notes`, and
  optionally `tail -50 "$CLUSTER_DIR/history.log"`.

## Per-cluster context
<!-- Free-form. Write what this cluster is about, key files, hypotheses,
     conventions specific to this thread. The AI reads this when
     triggered. -->
AGENTSEOF

  echo "Cluster initialized: $CLUSTER_DIR"
  echo "tmux session: $name"
  echo "Notes: $CLUSTER_DIR/notes.txt"

  # Build the startup command for the first tmux window:
  # source join.sh (sets CLUSTER_DIR), then open notes.txt
  local startup="source \"$dir/join.sh\" && nano \"$dir/notes.txt\""

  # Start the tmux session detached first, then attach appropriately
  tmux new-session -d -s "$name" -x 220 -y 50 \; \
    send-keys "source \"$dir/join.sh\" && nano \"$dir/notes.txt\"" Enter

  # Attach: iTerm2 uses -CC for native tab integration; others attach normally
  _cluster_tmux_attach "$name"
}

# ── cluster-join ─────────────────────────────────────────────────────────────
# Usage: cluster-join [cluster-dir]
# Join a cluster in the current shell — sets $CLUSTER_DIR and activates
# history logging. Does NOT open a new window or attach to tmux.
# Use nn or cluster-reopen to get into the tmux session.
function cluster-join() {
  local dir="${1:-}"
  if [[ -z "$dir" ]]; then
    dir="$(command ls -td $CLUSTER_BASE/*/ 2>/dev/null | head -1)"
    dir="${dir%/}"
  fi
  if [[ ! -d "$dir" ]]; then
    echo "cluster-join: no cluster found at '$dir'" >&2
    return 1
  fi
  source "$dir/join.sh"
  _cluster_activate "$CLUSTER_DIR"
  echo "Joined cluster: $CLUSTER_DIR"
}

# ── cluster-activate ─────────────────────────────────────────────────────────
# Usage: cluster-activate [name-fragment]
# Re-activate a cluster's $CLUSTER_DIR in the current shell.
# Does NOT open windows or attach to tmux. Use cluster-reopen after this
# if you want to re-enter the tmux session.
# No arg = interactive pick. With arg = most recent name match.
function cluster-activate() {
  local query="${1:-}"
  local dir=""

  if [[ -n "$query" ]]; then
    dir="$(command ls -td $CLUSTER_BASE/*/ 2>/dev/null | grep "$query" | head -1)"
    dir="${dir%/}"
    if [[ ! -d "$dir" ]]; then
      echo "cluster-activate: no cluster matching '$query'" >&2
      cluster-list
      return 1
    fi
  else
    local -a clusters
    clusters=("${(@f)$(command ls -td $CLUSTER_BASE/*/ 2>/dev/null)}")
    if [[ ${#clusters[@]} -eq 0 ]]; then
      echo "No clusters found in $CLUSTER_BASE" >&2
      return 1
    fi
    echo "Available clusters:"
    local i=1
    for c in "${clusters[@]}"; do
      printf "  %d) %s\n" "$i" "${c%/}"
      (( i++ ))
    done
    printf "Select cluster [1]: "
    read -r selection
    selection="${selection:-1}"
    dir="${clusters[$selection]%/}"
    if [[ ! -d "$dir" ]]; then
      echo "cluster-activate: invalid selection" >&2
      return 1
    fi
  fi

  source "$dir/join.sh"
  _cluster_activate "$CLUSTER_DIR"
  echo "Activated cluster: $CLUSTER_DIR"
  echo "Notes: $CLUSTER_DIR/notes.txt"
  echo "Tip: run 'cluster-reopen' to attach to the tmux session."
}

# ── cluster-reopen ────────────────────────────────────────────────────────────
# Usage: cluster-reopen [cluster-dir-or-name]
# Attach to the tmux session for the active (or specified) cluster.
# If the tmux session no longer exists (e.g. after reboot), tmux-continuum
# will have already restored it on tmux server start. If it still doesn't
# exist, a new session is created with the cluster's name and CLUSTER_DIR set.
function cluster-reopen() {
  local dir="${1:-$CLUSTER_DIR}"

  if [[ -z "$dir" ]]; then
    echo "cluster-reopen: no active cluster. Run: cluster-reopen <name-fragment>  or: cluster-activate <name-fragment> && cluster-reopen" >&2
    return 1
  fi

  # Accept either a path or a bare session name
  if [[ ! -d "$dir" ]]; then
    # Maybe it's a name fragment — try to find the cluster dir
    dir="$(command ls -td $CLUSTER_BASE/*/ 2>/dev/null | grep "$1" | head -1)"
    dir="${dir%/}"
  fi

  if [[ ! -d "$dir" ]]; then
    echo "cluster-reopen: no cluster found at '$1'" >&2
    return 1
  fi

  # Activate in current shell
  source "$dir/join.sh"
  _cluster_activate "$CLUSTER_DIR"

  # Derive tmux session name from the cluster dir basename
  local name="$(basename "$dir")"

  # Check if tmux session exists
  if tmux has-session -t "$name" 2>/dev/null; then
    echo "Attaching to existing tmux session: $name"
    _cluster_tmux_attach "$name"
  else
    echo "tmux session '$name' not found — creating fresh session."
    echo "(tmux-continuum should have restored it; if not, the session was never saved.)"
    tmux new-session -d -s "$name" -x 220 -y 50 \; \
      send-keys "source \"$dir/join.sh\"" Enter
    _cluster_tmux_attach "$name"
  fi
}

# ── _cluster_tmux_attach (internal) ──────────────────────────────────────────
# Attach to a tmux session using the appropriate method for the terminal.
# iTerm2: uses -CC for native tab/window integration.
# Others: plain attach.
function _cluster_tmux_attach() {
  local name="$1"
  case "$TERM_PROGRAM" in
    iTerm.app)
      # -CC enables iTerm2 native integration: tmux windows become tabs
      tmux -CC attach-session -t "$name"
      ;;
    *)
      tmux attach-session -t "$name"
      ;;
  esac
}

# ── nn — new window in the current cluster's tmux session ────────────────────
# Creates a new tmux window in the active session, already joined to the cluster.
# Falls back to opening a plain terminal window if not inside tmux.
function nn() {
  if [[ -z "$CLUSTER_DIR" ]]; then
    echo "No active cluster. Start one with: cluster-init [name]" >&2
    return 1
  fi

  local join_cmd="source \"$CLUSTER_DIR/join.sh\""
  local name="$(basename "$CLUSTER_DIR")"

  if [[ -n "$TMUX" ]]; then
    # Already inside a tmux session — create a new window directly
    tmux new-window -t "$name" \; send-keys "$join_cmd" Enter
  else
    # Outside tmux — open a new terminal window and attach to the session
    # The attach will create a new window in the session via iTerm2 -CC
    case "$TERM_PROGRAM" in
      iTerm.app)
        osascript <<APPLESCRIPT
tell application "iTerm2"
  set newWindow to (create window with default profile)
  tell current session of newWindow
    write text "tmux -CC attach-session -t ${name}"
  end tell
end tell
APPLESCRIPT
        ;;
      Apple_Terminal)
        osascript <<APPLESCRIPT
tell application "Terminal"
  do script "tmux attach-session -t ${name}"
  activate
end tell
APPLESCRIPT
        ;;
      *)
        echo "nn: run this to open a new cluster window:" >&2
        echo "  tmux new-window -t ${name} \\; send-keys \"${join_cmd}\" Enter" >&2
        ;;
    esac
  fi
}

# ── precmd hook — cluster history logging ────────────────────────────────────
# Appends the last command to $CLUSTER_DIR/history.log if set.
# Fires after every command in any shell where $CLUSTER_DIR is active.
function _cluster_log_command() {
  [[ -z "$CLUSTER_DIR" ]] && return
  [[ ! -d "$CLUSTER_DIR" ]] && return
  local last_cmd
  last_cmd="$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')"
  [[ -z "$last_cmd" ]] && return
  printf '[%s shell:%d] %s\n' "$(date +%H:%M:%S)" "$$" "$last_cmd" >> "$CLUSTER_DIR/history.log"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _cluster_log_command

# ── convenience functions ─────────────────────────────────────────────────────
function notes() {
  [[ -n "$CLUSTER_DIR" ]] && nano "$CLUSTER_DIR/notes.txt" || echo "No active cluster"
}

# ── cluster-note — append a timestamped entry to the cluster's notes.txt ─────
# Usage: cluster-note "<text>"
# Owns formatting (timestamp + trailing blank line). Used by AI agents per
# the cluster's AGENTS.md, and usable directly from the shell.
function cluster-note() {
  if [[ -z "$CLUSTER_DIR" ]]; then
    echo "cluster-note: no active cluster" >&2
    return 1
  fi
  local text="$*"
  if [[ -z "$text" ]]; then
    echo "usage: cluster-note \"<text>\"" >&2
    return 2
  fi
  printf '[%s] %s\n\n' "$(date +'%Y-%m-%d %H:%M')" "$text" >> "$CLUSTER_DIR/notes.txt"
}

# ── cluster-notes — print the cluster's notes.txt ────────────────────────────
# Companion reader for cluster-note. Use `notes` to open in nano instead.
function cluster-notes() {
  if [[ -z "$CLUSTER_DIR" ]]; then
    echo "cluster-notes: no active cluster" >&2
    return 1
  fi
  cat "$CLUSTER_DIR/notes.txt"
}

function cluster-history() {
  [[ -n "$CLUSTER_DIR" ]] && cat "$CLUSTER_DIR/history.log" || echo "No active cluster"
}

function cluster-status() {
  if [[ -n "$CLUSTER_DIR" ]]; then
    local name="$(basename "$CLUSTER_DIR")"
    echo "Active cluster: $CLUSTER_DIR"
    if tmux has-session -t "$name" 2>/dev/null; then
      echo "tmux session '$name': running"
    else
      echo "tmux session '$name': not running (run cluster-reopen to attach)"
    fi
  else
    echo "No active cluster"
  fi
}

function cluster-list() {
  CLICOLOR=0 command ls -1t "$CLUSTER_BASE" 2>/dev/null || echo "No clusters yet"
}

# ── cluster-shutdown ──────────────────────────────────────────────────────────
# Ends the active cluster's live session. The cluster directory (notes.txt,
# history.log) is preserved intact. Use this when you are done with a cluster
# for good but want to keep its notes and history for reference.
#
# If called from inside the session being shut down, all tabs will close.
# If called from outside the session, the session is killed silently.
function cluster-shutdown() {
  local dir="${CLUSTER_DIR:-}"

  if [[ -z "$dir" ]]; then
    echo "cluster-shutdown: no active cluster." >&2
    return 1
  fi

  local name="$(basename "$dir")"

  if ! tmux has-session -t "$name" 2>/dev/null; then
    echo "cluster-shutdown: no running session found for '$name'."
    echo "Clearing active cluster state."
    unset CLUSTER_DIR
    [[ -f "$CLUSTER_STATE" ]] && rm -f "$CLUSTER_STATE"
    return 0
  fi

  # Warn if we are about to kill our own session
  if [[ -n "$TMUX" ]]; then
    local current_session
    current_session="$(tmux display-message -p '#S' 2>/dev/null)"
    if [[ "$current_session" == "$name" ]]; then
      echo "Shutting down this session — all tabs will close."
    fi
  fi

  echo "Shutting down cluster: $name"
  echo "Notes and history preserved at: $dir"
  echo "Run 'cluster-reopen <name-fragment>' to start a fresh session — e.g. cluster-reopen $(basename "$dir")"

  # Clear shell state before killing the session (in case we survive the kill)
  unset CLUSTER_DIR
  [[ -f "$CLUSTER_STATE" ]] && rm -f "$CLUSTER_STATE"

  tmux kill-session -t "$name" 2>/dev/null
}
