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
  mkdir -p "${CLUSTER_STATE:h}"
  echo "$dir" > "$CLUSTER_STATE"
}

# Source a cluster's join.sh, refusing if the file is missing. Returns 1 on
# failure so the caller can bail before printing a misleading success line.
function _cluster_source_join() {
  local caller="$1" dir="$2"
  if [[ ! -f "$dir/join.sh" ]]; then
    echo "${caller}: $dir/join.sh missing — cluster dir looks corrupted" >&2
    return 1
  fi
  source "$dir/join.sh"
}

# ── auto-restore on shell startup ────────────────────────────────────────────
# Silently re-activate the last cluster if the directory still exists.
# This runs when the file is sourced (i.e. every new shell via .zshrc).
if [[ -z "$CLUSTER_DIR" && -f "$CLUSTER_STATE" ]]; then
  _last="$(cat "$CLUSTER_STATE")"
  if [[ -d "$_last" ]]; then
    export CLUSTER_DIR="$_last"
  else
    rm -f "$CLUSTER_STATE"
  fi
  unset _last
fi

# ── cluster-init ─────────────────────────────────────────────────────────────
# Usage: cluster-init [slug]
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

  # Start the tmux session detached, with the first window sourcing join.sh
  # (which sets CLUSTER_DIR) and then opening notes.txt in nano.
  tmux new-session -d -s "$name" -x 220 -y 50 \; \
    send-keys "source \"$dir/join.sh\" && nano \"$dir/notes.txt\"" Enter

  # Stamp the tmux session env so new panes/windows inherit CLUSTER_DIR
  # without needing to source join.sh.
  tmux setenv -t "$name" CLUSTER_DIR "$dir"

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
    local -a _matches
    _matches=($CLUSTER_BASE/*/(Nom))
    dir="${_matches[1]%/}"
  fi
  if [[ ! -d "$dir" ]]; then
    echo "cluster-join: no cluster found at '${dir:-<none>}'" >&2
    return 1
  fi
  _cluster_source_join cluster-join "$dir" || return 1
  _cluster_activate "$CLUSTER_DIR"
  # If the cluster's tmux session is running, refresh its env so panes split
  # inside it (Ctrl-a ") inherit CLUSTER_DIR. cluster-join only sets the var
  # in *this* shell; the tmux session env is independent and would otherwise
  # carry whatever the server had cached when the session was created.
  _cluster_refresh_tmux_env
  echo "Joined cluster: $CLUSTER_DIR"
}

# Update the active cluster's tmux session env (if running) to match the
# current $CLUSTER_DIR. Safe to call from any context — no-op when no session.
function _cluster_refresh_tmux_env() {
  [[ -z "$CLUSTER_DIR" ]] && return
  local _sess="${CLUSTER_DIR:t}"
  if tmux has-session -t "$_sess" 2>/dev/null; then
    tmux setenv -t "$_sess" CLUSTER_DIR "$CLUSTER_DIR"
  fi
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
    local -a _matches
    _matches=($CLUSTER_BASE/*${query}*/(Nom))
    dir="${_matches[1]%/}"
    if [[ ! -d "$dir" ]]; then
      echo "cluster-activate: no cluster matching '$query'" >&2
      cluster-list
      return 1
    fi
  else
    local -a clusters
    clusters=($CLUSTER_BASE/*/(Nom))
    if [[ ${#clusters[@]} -eq 0 ]]; then
      echo "No clusters found in $CLUSTER_BASE" >&2
      return 1
    fi
    echo "Available clusters:"
    local i=1
    for c in "${clusters[@]}"; do
      printf "  %d) %s\n" "$i" "${${c%/}:t}"
      (( i++ ))
    done
    printf "Select cluster [1]: "
    read -r selection
    selection="${selection:-1}"
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#clusters[@]} )); then
      echo "cluster-activate: invalid selection '$selection' (expected 1-${#clusters[@]})" >&2
      return 1
    fi
    dir="${clusters[$selection]%/}"
    if [[ ! -d "$dir" ]]; then
      echo "cluster-activate: invalid selection" >&2
      return 1
    fi
  fi

  _cluster_source_join cluster-activate "$dir" || return 1
  _cluster_activate "$CLUSTER_DIR"
  # See _cluster_refresh_tmux_env above — keeps split-panes consistent.
  _cluster_refresh_tmux_env
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
    # If no fragment was passed, the stale $CLUSTER_DIR is the problem —
    # do not silently fall through to a different cluster.
    if [[ -z "$1" ]]; then
      echo "cluster-reopen: active cluster dir is missing: $CLUSTER_DIR" >&2
      echo "Stale state cleared. Run 'cluster-activate <fragment>' to pick another." >&2
      unset CLUSTER_DIR
      rm -f "$CLUSTER_STATE"
      return 1
    fi
    # Maybe it's a name fragment — try to find the cluster dir
    local -a _matches
    _matches=($CLUSTER_BASE/*${1}*/(Nom))
    dir="${_matches[1]%/}"
  fi

  if [[ ! -d "$dir" ]]; then
    echo "cluster-reopen: no cluster found at '$1'" >&2
    return 1
  fi

  # Activate in current shell
  _cluster_source_join cluster-reopen "$dir" || return 1
  _cluster_activate "$CLUSTER_DIR"

  # Derive tmux session name from the cluster dir basename
  local name="$(basename "$dir")"

  # Check if tmux session exists
  if tmux has-session -t "$name" 2>/dev/null; then
    echo "Attaching to existing tmux session: $name"
    # Refresh session env (continuum-restored sessions may not have CLUSTER_DIR)
    tmux setenv -t "$name" CLUSTER_DIR "$dir"
    _cluster_tmux_attach "$name"
  else
    echo "tmux session '$name' not found — creating fresh session."
    echo "(tmux-continuum should have restored it; if not, the session was never saved.)"
    tmux new-session -d -s "$name" -x 220 -y 50 \; \
      send-keys "source \"$dir/join.sh\"" Enter
    tmux setenv -t "$name" CLUSTER_DIR "$dir"
    _cluster_tmux_attach "$name"
  fi
}

# ── _cluster_tmux_attach (internal) ──────────────────────────────────────────
# Attach to a tmux session using the appropriate method for the terminal.
# iTerm2: uses -CC for native tab/window integration.
# Others: plain attach.
function _cluster_tmux_attach() {
  local name="$1"
  # If already inside a tmux session, attach can't nest — switch instead.
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$name"
    return $?
  fi
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
    echo "nn: no active cluster (start one with: cluster-init [slug])" >&2
    return 1
  fi

  local join_cmd="source \"$CLUSTER_DIR/join.sh\""
  local name="$(basename "$CLUSTER_DIR")"

  if [[ -n "$TMUX" ]]; then
    # Already inside a tmux session — create a new window directly
    tmux new-window -t "$name" \; send-keys "$join_cmd" Enter
  else
    # Outside tmux — create a new tmux window server-side first, then open
    # a fresh terminal window and attach. Attach alone does NOT create a
    # window; we have to call new-window explicitly.
    if ! tmux has-session -t "$name" 2>/dev/null; then
      echo "nn: tmux session '$name' is not running. Start it with: cluster-reopen" >&2
      return 1
    fi
    tmux new-window -t "$name" \; send-keys -t "$name" "$join_cmd" Enter
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
        echo "nn: created new tmux window in '$name'. Attach with:" >&2
        echo "  tmux attach-session -t ${name}" >&2
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
# Guard for commands that depend on an active, on-disk cluster.
function _cluster_require_active() {
  local caller="$1"
  if [[ -z "$CLUSTER_DIR" ]]; then
    echo "${caller}: no active cluster" >&2
    return 1
  fi
  if [[ ! -d "$CLUSTER_DIR" ]]; then
    echo "${caller}: cluster dir missing: $CLUSTER_DIR" >&2
    return 1
  fi
}

function notes() {
  _cluster_require_active notes || return
  nano "$CLUSTER_DIR/notes.txt"
}

# ── cluster-note — append a timestamped entry to the cluster's notes.txt ─────
# Usage: cluster-note "<text>"
# Owns formatting (timestamp + trailing blank line). Used by AI agents per
# the cluster's AGENTS.md, and usable directly from the shell.
function cluster-note() {
  _cluster_require_active cluster-note || return
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
  _cluster_require_active cluster-notes || return
  cat "$CLUSTER_DIR/notes.txt"
}

function cluster-history() {
  _cluster_require_active cluster-history || return
  cat "$CLUSTER_DIR/history.log"
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
    echo "cluster-shutdown: no active cluster" >&2
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
