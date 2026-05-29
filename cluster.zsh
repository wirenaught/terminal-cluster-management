# cluster.zsh — terminal cluster management
# Source this file from ~/.zshrc

CLUSTER_BASE="$HOME/.clusters"

# Path to this file, captured at source time. cluster-help parses it to
# build the command listing from the section-header / Usage convention.
typeset -g _CLUSTER_ZSH_PATH="${${(%):-%x}:A}"

# Default geometry for detached tmux sessions created by cluster-init / cluster-join.
CLUSTER_TMUX_GEOMETRY=(-x 220 -y 50)

# ── output conventions ───────────────────────────────────────────────────────
# Errors:   "<cmd>: <message>"            → stderr
# Info:     plain "key:  value" lines     → stdout, no command prefix
# Summary block used after init/join/rename/status/shutdown:
#   cluster:  <name>
#   path:     <dir>
#   tmux:     <starting|running|created|stopped|not running>
#   notes:    <path>           (init only)
function _cluster_print_summary() {
  local name="$1" dir="$2" tmux_state="$3" notes_path="${4:-}"
  printf "cluster:  %s\n" "$name"
  printf "path:     %s\n" "$dir"
  printf "tmux:     %s\n" "$tmux_state"
  [[ -n "$notes_path" ]] && printf "notes:    %s\n" "$notes_path"
}

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
# Set CLUSTER_DIR for this shell. Activation is shell-local — no persistent
# state file. New shells are not in a cluster until they explicitly join.
function _cluster_activate() {
  local dir="$1"
  export CLUSTER_DIR="$dir"
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

  # Note: we deliberately do NOT _cluster_activate here. Cluster identity
  # lives in the tmux session (via setenv below + the first window sourcing
  # join.sh). The launching shell stays clean — that way, when the user
  # detaches from tmux or runs cluster-leave, no stale CLUSTER_DIR lingers.

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

  echo "Cluster initialized."
  _cluster_print_summary "$name" "$dir" "starting" "$dir/notes.txt"

  # Start the tmux session detached, with the first window sourcing join.sh
  # (which sets CLUSTER_DIR) and then opening notes.txt in nano.
  tmux new-session -d -s "$name" "${CLUSTER_TMUX_GEOMETRY[@]}" \; \
    send-keys "source \"$dir/join.sh\" && nano \"$dir/notes.txt\"" Enter

  # Stamp the tmux session env so new panes/windows inherit CLUSTER_DIR
  # without needing to source join.sh.
  tmux setenv -t "$name" CLUSTER_DIR "$dir"

  # Attach: iTerm2 uses -CC for native tab integration; others attach normally
  _cluster_tmux_attach "$name"
}

# ── cluster-join ─────────────────────────────────────────────────────────────
# Usage: cluster-join
# Shows all clusters (most recent first). Pick one to attach to its tmux
# session. If the session is not running, prompts to resurrect it before
# attaching — never silently. CLUSTER_DIR is set in the tmux session env,
# not in the calling shell.
function cluster-join() {
  local -a clusters
  clusters=($CLUSTER_BASE/*/(Nom))
  if [[ ${#clusters[@]} -eq 0 ]]; then
    echo "cluster-join: no clusters to join" >&2
    echo "  hint: cluster-init [slug]" >&2
    return 1
  fi

  echo "Available clusters:"
  local i=1
  for c in "${clusters[@]}"; do
    local cname="${${c%/}:t}"
    local cdir="${c%/}"
    if [[ "$cdir" == "$CLUSTER_DIR" ]]; then
      printf "  %d) %s  ← active\n" "$i" "$cname"
    else
      printf "  %d) %s\n" "$i" "$cname"
    fi
    (( i++ ))
  done

  printf "Select cluster [1]: "
  read -r selection
  selection="${selection:-1}"
  if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#clusters[@]} )); then
    echo "cluster-join: invalid selection '$selection' (expected 1-${#clusters[@]})" >&2
    return 1
  fi

  local dir="${clusters[$selection]%/}"
  if [[ ! -d "$dir" ]]; then
    echo "cluster-join: invalid selection" >&2
    return 1
  fi

  # Sanity check: cluster dir is intact. We need join.sh either to attach
  # to a live session or to bootstrap a resurrected one, so check up front.
  if [[ ! -f "$dir/join.sh" ]]; then
    echo "cluster-join: $dir/join.sh missing — cluster dir looks corrupted" >&2
    return 1
  fi

  # Probe for a live session. If none, prompt the user — cluster-join doesn't
  # silently self-heal, but it offers an explicit one-keystroke resurrect so
  # you're not bounced back to the shell to type a tmux incantation.
  local name="${dir:t}"
  if ! tmux has-session -t "$name" 2>/dev/null; then
    echo "cluster-join: tmux session '$name' is not running." >&2
    printf "Resurrect it now? [y/N]: " >&2
    local _reply
    read -r _reply
    if [[ ! "$_reply" =~ ^[Yy]$ ]]; then
      echo "cluster-join: aborted." >&2
      return 1
    fi
    # Resurrect: start a detached session that sources join.sh in window 1,
    # mirroring cluster-init's bootstrap (minus the nano-on-notes.txt step,
    # which is a one-time startup nicety).
    if ! tmux new-session -d -s "$name" -c "$dir" \
           "${CLUSTER_TMUX_GEOMETRY[@]}" \; \
           send-keys "source \"$dir/join.sh\"" Enter 2>/dev/null; then
      echo "cluster-join: failed to create tmux session '$name'" >&2
      return 1
    fi
  fi

  # Refresh tmux session env so shells spawned inside the session get
  # CLUSTER_DIR. We deliberately do NOT export CLUSTER_DIR in this shell —
  # the launching shell stays clean so detach lands you in a plain shell
  # with no stale cluster state.
  tmux setenv -t "$name" CLUSTER_DIR "$dir"

  echo "Joined cluster."
  _cluster_print_summary "$name" "$dir" "running"
  _cluster_tmux_attach "$name"
}

# ── cluster-rename ────────────────────────────────────────────────────────────
# Usage: cluster-rename [new-slug]
# Renames the active cluster's slug, keeping the timestamp prefix.
# Updates the directory, join.sh, notes.txt header, tmux session name,
# and shell state. Warns about stale shells/panes.
function cluster-rename() {
  _cluster_require_active cluster-rename || return 1

  # Step 1: input + validate
  local new_slug="${1:-}"
  if [[ -z "$new_slug" ]]; then
    printf "New slug: "
    read -r new_slug
  fi
  if [[ -z "$new_slug" ]]; then
    echo "cluster-rename: slug cannot be empty" >&2
    return 1
  fi
  if [[ "$new_slug" =~ [^a-zA-Z0-9_-] ]]; then
    echo "cluster-rename: slug must contain only letters, digits, hyphens, and underscores" >&2
    return 1
  fi

  # Step 2: derive names + collision check
  local old_name="${CLUSTER_DIR:t}"
  local timestamp
  timestamp="$(echo "$old_name" | cut -d- -f1-4)"
  local new_name="${timestamp}-${new_slug}"
  local new_dir="${CLUSTER_BASE}/${new_name}"

  if [[ "$new_name" == "$old_name" ]]; then
    echo "cluster-rename: new name is identical to current name" >&2
    return 1
  fi
  if [[ -d "$new_dir" ]]; then
    echo "cluster-rename: '$new_name' already exists" >&2
    return 1
  fi

  # Step 3: mv first — abort before touching anything else on failure
  mv "$CLUSTER_DIR" "$new_dir" || {
    echo "cluster-rename: mv failed — no changes made" >&2
    return 1
  }

  # Step 4: rewrite join.sh via temp file
  local tmp
  tmp="$(mktemp "$new_dir/join.sh.XXXXXX")"
  if echo "export CLUSTER_DIR=\"$new_dir\"" > "$tmp" && mv "$tmp" "$new_dir/join.sh"; then
    : # success
  else
    rm -f "$tmp"
    echo "cluster-rename: failed to update join.sh (directory renamed to $new_name)" >&2
    return 1
  fi

  # Step 5: update notes.txt header + verify
  sed -i '' "s/^# cluster: .*/# cluster: ${new_name}/" "$new_dir/notes.txt" 2>/dev/null
  if ! grep -q "^# cluster: ${new_name}" "$new_dir/notes.txt" 2>/dev/null; then
    echo "cluster-rename: warning — notes.txt header not updated (edit manually if needed)" >&2
  fi

  # Step 6: update shell state
  _cluster_activate "$new_dir"

  # Steps 7 + 8: rename tmux session and update its env (both inside the guard)
  if tmux has-session -t "$old_name" 2>/dev/null; then
    if tmux rename-session -t "$old_name" "$new_name" 2>/dev/null; then
      tmux setenv -t "$new_name" CLUSTER_DIR "$new_dir"
    else
      echo "cluster-rename: warning — tmux session rename failed." >&2
      echo "  Session is still named '$old_name'. To fix:" >&2
      echo "  tmux rename-session -t '$old_name' '$new_name'" >&2
    fi
  fi

  # Step 9: success + stale-shell warning
  local tmux_state="not running"
  tmux has-session -t "$new_name" 2>/dev/null && tmux_state="running"
  echo "Renamed: $old_name → $new_name"
  _cluster_print_summary "$new_name" "$new_dir" "$tmux_state"
  echo
  echo "Warning: every open shell/pane — including existing tmux panes — still has"
  echo "  the old path. History logging has stopped in those shells."
  echo "  Run in each:  source \"$new_dir/join.sh\""
}

# ── _cluster_refresh_tmux_env (internal) ─────────────────────────────────────
# Update the active cluster's tmux session env (if running) to match the
# current $CLUSTER_DIR. Safe to call from any context — no-op when no session.
function _cluster_refresh_tmux_env() {
  [[ -z "$CLUSTER_DIR" ]] && return
  local _sess="${CLUSTER_DIR:t}"
  if tmux has-session -t "$_sess" 2>/dev/null; then
    tmux setenv -t "$_sess" CLUSTER_DIR "$CLUSTER_DIR"
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
  _cluster_require_active nn || return 1

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
      echo "nn: tmux session '$name' is not running" >&2
      echo "  hint: cluster-join" >&2
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
        echo "Created new tmux window in '$name'. Attach with:"
        echo "  tmux attach-session -t ${name}"
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
    echo "  hint: cluster-init [slug]" >&2
    return 1
  fi
  if [[ ! -d "$CLUSTER_DIR" ]]; then
    echo "${caller}: cluster dir missing: $CLUSTER_DIR" >&2
    return 1
  fi
}

# ── notes ────────────────────────────────────────────────────────────────────
# Usage: notes
# Open the active cluster's notes.txt in nano. Companion to cluster-note
# (append a timestamped entry) and cluster-notes (print to stdout).
# The short `notes` alias is intentional; the cluster-* pair is what AI
# agents use per AGENTS.md.
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
    echo "cluster-note: missing text argument" >&2
    echo "  usage: cluster-note \"<text>\"" >&2
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

# ── cluster-history ──────────────────────────────────────────────────────────
# Usage: cluster-history
# Print the active cluster's history.log (commands run in any cluster shell).
function cluster-history() {
  _cluster_require_active cluster-history || return
  cat "$CLUSTER_DIR/history.log"
}

# ── cluster-status ───────────────────────────────────────────────────────────
# Usage: cluster-status
# Show the active cluster's name, path, and tmux session state.
function cluster-status() {
  if [[ -n "$CLUSTER_DIR" ]]; then
    local name="$(basename "$CLUSTER_DIR")"
    local tmux_state="not running"
    tmux has-session -t "$name" 2>/dev/null && tmux_state="running"
    _cluster_print_summary "$name" "$CLUSTER_DIR" "$tmux_state"
    if [[ "$tmux_state" == "not running" ]]; then
      echo
      echo "hint: cluster-join"
    fi
  else
    echo "No active cluster"
    echo
    echo "hint: cluster-init [slug]"
  fi
}

# ── cluster-list ─────────────────────────────────────────────────────────────
# Usage: cluster-list
# List all clusters under $CLUSTER_BASE, most-recently-modified first,
# marking the active one.
function cluster-list() {
  local -a entries
  entries=("${(@f)$(CLICOLOR=0 command ls -1t "$CLUSTER_BASE" 2>/dev/null)}")
  if [[ ${#entries[@]} -eq 0 || -z "${entries[1]}" ]]; then
    echo "No clusters yet"
    echo
    echo "hint: cluster-init [slug]"
    return
  fi
  local active="${CLUSTER_DIR:t}"
  for e in "${entries[@]}"; do
    if [[ "$e" == "$active" ]]; then
      printf "%s  ← active\n" "$e"
    else
      printf "%s\n" "$e"
    fi
  done
}

# ── cluster-leave ────────────────────────────────────────────────────────────
# Usage: cluster-leave
# Step away from the active cluster in this shell. Unsets CLUSTER_DIR so the
# prompt, history hook, and nn all stop targeting the cluster. If this shell
# is inside any tmux session, detaches the client too (session keeps running;
# other clients/panes are unaffected). Notes and history are preserved —
# rejoin any time with cluster-join.
#
# Only affects this shell + this tmux client. Other open shells/panes that
# already have CLUSTER_DIR set are unchanged (same caveat as cluster-rename).
function cluster-leave() {
  # If this shell is inside any tmux session, detach the client and kill
  # the current window so the user lands back in their original (non-tmux)
  # terminal with a clean slate — no cluster context, no neighboring tmux
  # window grabbed focus.
  #
  # Order matters: detach-client first, then kill-window. kill-window on
  # the window hosting *this* shell terminates the shell, so anything after
  # it never runs. detach-client doesn't kill the shell — it only disconnects
  # the iTerm-side client — so subsequent commands still execute. We capture
  # the window target up front because after detach there's no "current
  # client" for tmux to resolve a target-less kill-window against.
  if [[ -n "$TMUX" ]]; then
    # precmd hook won't fire after we exit tmux — log the leave explicitly.
    if [[ -n "$CLUSTER_DIR" && -w "$CLUSTER_DIR/history.log" ]]; then
      print "[$(date +%H:%M:%S) shell:$$] cluster-leave (detach + kill-window)" \
        >> "$CLUSTER_DIR/history.log"
    fi
    unset CLUSTER_DIR
    local _win_target
    _win_target="$(tmux display-message -p '#S:#I' 2>/dev/null)"
    tmux detach-client
    tmux kill-window -t "$_win_target" 2>/dev/null
    return 0
  fi

  if [[ -z "$CLUSTER_DIR" ]]; then
    echo "cluster-leave: no active cluster" >&2
    return 1
  fi

  local dir="$CLUSTER_DIR"
  local name="${dir:t}"
  local tmux_state="not running"
  tmux has-session -t "$name" 2>/dev/null && tmux_state="running"

  unset CLUSTER_DIR

  echo "Left cluster (this shell only)."
  _cluster_print_summary "$name" "$dir" "$tmux_state"
  echo
  echo "Rejoin:    cluster-join"
  echo "Note: existing shells/panes still have CLUSTER_DIR set."
}

# ── cluster-shutdown ──────────────────────────────────────────────────────────
# Ends the active cluster's live session. The cluster directory (notes.txt,
# history.log) is preserved intact. Use this when you are done with a cluster
# for good but want to keep its notes and history for reference.
#
# If called from inside the session being shut down, all tabs will close.
# If called from outside the session, the session is killed silently.
function cluster-shutdown() {
  if [[ -z "$CLUSTER_DIR" ]]; then
    echo "cluster-shutdown: no active cluster" >&2
    echo "  hint: cluster-init [slug]" >&2
    return 1
  fi

  local dir="$CLUSTER_DIR"
  local name="$(basename "$dir")"

  if ! tmux has-session -t "$name" 2>/dev/null; then
    echo "No running session for '$name'. Clearing active cluster state."
    unset CLUSTER_DIR
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

  # Clear shell state before killing the session (in case we survive the kill)
  unset CLUSTER_DIR

  if tmux kill-session -t "$name" 2>/dev/null; then
    echo "Cluster shut down."
    _cluster_print_summary "$name" "$dir" "stopped"
    echo
    echo "Notes and history preserved at: $dir"
    echo "Run 'cluster-join' to select and enter a session."
  else
    echo "cluster-shutdown: failed to kill tmux session '$name'" >&2
    return 1
  fi
}

# ── cluster-help ─────────────────────────────────────────────────────────────
# Usage: cluster-help
# List all cluster commands with their usage signature and one-line summary.
# Parses this file's own section-header convention — no hardcoded command list.
# Convention: each public command is preceded by
#   # ── <name> ────...
#   # Usage: <signature>
#   # <description line(s)>
#   function <name>() { ... }
function cluster-help() {
  local src="$_CLUSTER_ZSH_PATH"
  if [[ ! -f "$src" ]]; then
    echo "cluster-help: cannot locate cluster.zsh (looked for: $src)" >&2
    return 1
  fi

  echo "Cluster commands:"
  echo
  awk '
    function flush(name,   usage, desc, i, l) {
      usage = ""; desc = ""
      for (i = 1; i <= n; i++) {
        l = buf[i]
        if (l ~ /^Usage:[[:space:]]*/) {
          usage = l
          sub(/^Usage:[[:space:]]*/, "", usage)
        } else if (desc == "" && l != "" && l !~ /^──/) {
          desc = l
        }
      }
      if (usage == "") usage = name
      printf "  %-30s  %s\n", usage, desc
      n = 0
    }
    /^# ──/ {
      n = 0
      line = $0; sub(/^#[[:space:]]?/, "", line)
      buf[++n] = line
      next
    }
    /^#/ {
      line = $0; sub(/^#[[:space:]]?/, "", line)
      buf[++n] = line
      next
    }
    /^function[[:space:]]+(cluster-[a-zA-Z0-9_-]+|nn|notes)[[:space:]]*\(\)/ {
      name = $2
      sub(/\(\).*/, "", name)
      flush(name)
      next
    }
    /^$/ { n = 0; next }
    { n = 0 }
  ' "$src"
}
