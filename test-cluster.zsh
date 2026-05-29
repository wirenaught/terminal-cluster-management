#!/usr/bin/env zsh
# test-cluster.zsh — test suite for cluster.zsh

# lastpipe: run the last element of a pipeline in the current shell so that
# side effects inside cluster-join (CLUSTER_DIR, _last_attach) propagate back.
setopt lastpipe

SCRIPT_DIR="${0:A:h}"
_T_ID="$$"
_T_BASE="$(mktemp -d)"
_T_SESSIONS=()

# ── setup ─────────────────────────────────────────────────────────────────────

source "$SCRIPT_DIR/cluster.zsh"

# Isolate from real ~/.clusters
CLUSTER_BASE="$_T_BASE"
unset CLUSTER_DIR

# _cluster_tmux_attach is overridden to capture its argument rather than
# blocking on a TTY. All real side effects before the attach call run live.
_last_attach=""
function _cluster_tmux_attach() { _last_attach="$1"; }

# ── cleanup ───────────────────────────────────────────────────────────────────

function _t_cleanup() {
  for s in "${_T_SESSIONS[@]}"; do
    tmux kill-session -t "$s" 2>/dev/null
  done
  rm -rf "$_T_BASE"
}
trap _t_cleanup EXIT INT TERM

# ── assert helpers ────────────────────────────────────────────────────────────

_pass=0; _fail=0

function assert_eq() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    print "  ✓ $desc"; (( ++_pass ))
  else
    print "  ✗ $desc"
    print "    want: $want"
    print "    got:  $got"
    (( ++_fail ))
  fi
}

function assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    print "  ✓ $desc"; (( ++_pass ))
  else
    print "  ✗ $desc"
    print "    needle: $needle"
    print "    in:     $haystack"
    (( ++_fail ))
  fi
}

function assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    print "  ✓ $desc"; (( ++_pass ))
  else
    print "  ✗ $desc — missing: $path"; (( ++_fail ))
  fi
}

function assert_session_running() {
  local desc="$1" name="$2"
  if tmux has-session -t "$name" 2>/dev/null; then
    print "  ✓ $desc"; (( ++_pass ))
  else
    print "  ✗ $desc — session not found: $name"; (( ++_fail ))
  fi
}

function assert_session_gone() {
  local desc="$1" name="$2"
  if ! tmux has-session -t "$name" 2>/dev/null; then
    print "  ✓ $desc"; (( ++_pass ))
  else
    print "  ✗ $desc — session still exists: $name"; (( ++_fail ))
  fi
}

# Run cluster-join with a selection number. With setopt lastpipe, cluster-join
# runs in the current shell so CLUSTER_DIR and _last_attach propagate back.
# Output is captured in _join_out.
_join_out=""
function _run_join() {
  local input="$1" _f
  _f="$(mktemp)"
  _last_attach=""
  echo "$input" | cluster-join > "$_f" 2>&1
  _join_out="$(< "$_f")"
  rm -f "$_f"
}

# ── pre-test: seed two clusters ───────────────────────────────────────────────
# vet-a created first (older), vet-b created second (newer).
# cluster-list sorts by mtime newest-first: vet-b = item 1, vet-a = item 2.
#
# cluster-init no longer sets CLUSTER_DIR in the launching shell — cluster
# identity lives in the tmux session env, not the caller. Derive the dir
# from CLUSTER_BASE by matching the slug we passed.

unset CLUSTER_DIR; _last_attach=""
cluster-init "vet-a-$_T_ID" > /dev/null
_t_init_leak_a="${CLUSTER_DIR:-(unset)}"
_T_DIR_A=("$_T_BASE"/*-vet-a-"$_T_ID"(N))
_T_DIR_A="${_T_DIR_A[1]}"
_T_SESS_A="${_T_DIR_A:t}"
_T_SESSIONS+=("$_T_SESS_A")

unset CLUSTER_DIR; _last_attach=""
cluster-init "vet-b-$_T_ID" > /dev/null
_t_init_leak_b="${CLUSTER_DIR:-(unset)}"
_T_DIR_B=("$_T_BASE"/*-vet-b-"$_T_ID"(N))
_T_DIR_B="${_T_DIR_B[1]}"
_T_SESS_B="${_T_DIR_B:t}"
_T_SESSIONS+=("$_T_SESS_B")

# ── cluster-list ──────────────────────────────────────────────────────────────

print "\n── cluster-list ──"
_t_out="$(cluster-list)"
assert_contains "lists vet-a" "$_t_out" "vet-a-$_T_ID"
assert_contains "lists vet-b" "$_t_out" "vet-b-$_T_ID"

print "\n── cluster-list (empty base) ──"
_t_empty="$(mktemp -d)"
_t_saved_base="$CLUSTER_BASE"; CLUSTER_BASE="$_t_empty"
_t_out="$(cluster-list 2>&1)"
assert_contains "reports no clusters" "$_t_out" "No clusters yet"
CLUSTER_BASE="$_t_saved_base"; rm -rf "$_t_empty"

# ── cluster-status ────────────────────────────────────────────────────────────

print "\n── cluster-status (no active cluster) ──"
unset CLUSTER_DIR
_t_out="$(cluster-status)"
assert_contains "no active cluster" "$_t_out" "No active cluster"

print "\n── cluster-status (session running) ──"
export CLUSTER_DIR="$_T_DIR_B"
_t_out="$(cluster-status)"
assert_contains "shows cluster dir" "$_t_out" "vet-b-$_T_ID"
assert_contains "reports running"   "$_t_out" "running"

print "\n── cluster-status (session not running) ──"
export CLUSTER_DIR="$_T_DIR_A"
tmux kill-session -t "$_T_SESS_A" 2>/dev/null
_T_SESSIONS=("${_T_SESSIONS[@]:#$_T_SESS_A}")
_t_out="$(cluster-status)"
assert_contains "reports not running"   "$_t_out" "not running"
assert_contains "suggests cluster-join" "$_t_out" "cluster-join"

# ── cluster-init artifacts ────────────────────────────────────────────────────

print "\n── cluster-init ──"
assert_contains "dir derived from CLUSTER_BASE" "$_T_DIR_B"                  "vet-b-$_T_ID"
assert_file_exists "join.sh created"       "$_T_DIR_B/join.sh"
assert_file_exists "notes.txt created"     "$_T_DIR_B/notes.txt"
assert_file_exists "AGENTS.md created"     "$_T_DIR_B/AGENTS.md"
assert_contains "notes.txt seeded"         "$(< "$_T_DIR_B/notes.txt")"     "cluster:"
assert_contains "join.sh sets CLUSTER_DIR" "$(< "$_T_DIR_B/join.sh")"       "export CLUSTER_DIR="
assert_session_running "tmux session created" "$_T_SESS_B"
# New-model contract: launching shell stays clean; cluster identity lives
# in the tmux session env, not in the caller's environment.
assert_eq          "vet-a init: launching shell clean" "$_t_init_leak_a" "(unset)"
assert_eq          "vet-b init: launching shell clean" "$_t_init_leak_b" "(unset)"
_t_init_env="$(tmux showenv -t "$_T_SESS_B" CLUSTER_DIR 2>/dev/null)"
assert_contains    "tmux session env has CLUSTER_DIR"   "$_t_init_env" "vet-b-$_T_ID"

# ── cluster-note / cluster-notes ─────────────────────────────────────────────

print "\n── cluster-note / cluster-notes ──"
export CLUSTER_DIR="$_T_DIR_B"
cluster-note "alpha-$_T_ID"
cluster-note "beta-$_T_ID"
_t_out="$(cluster-notes)"
assert_contains "first note present"  "$_t_out" "alpha-$_T_ID"
assert_contains "second note present" "$_t_out" "beta-$_T_ID"
assert_contains "timestamp present"   "$_t_out" "$(date +%Y-%m-%d)"

print "\n── cluster-note (missing arg) ──"
_t_out="$(cluster-note 2>&1)"
assert_contains "usage error shown" "$_t_out" "usage:"

# ── cluster-history / precmd hook ────────────────────────────────────────────

print "\n── cluster-history (precmd hook) ──"
print -s "echo hook-marker-$_T_ID"
_cluster_log_command
_t_out="$(cluster-history)"
assert_contains "command logged" "$_t_out" "echo hook-marker-$_T_ID"

# ── cluster-join (existing session) ──────────────────────────────────────────

print "\n── cluster-join (existing session) ──"
unset CLUSTER_DIR
_run_join 1
assert_contains "list shown"               "$_join_out"  "Available clusters"
# Under the new model, cluster-join does NOT export CLUSTER_DIR in the
# launching shell — cluster identity lives in the tmux session env.
_t_env="$(tmux showenv -t "$_T_SESS_B" CLUSTER_DIR 2>/dev/null)"
assert_contains "tmux session env has CLUSTER_DIR" "$_t_env" "vet-b-$_T_ID"
assert_eq       "launching shell stays clean"      "${CLUSTER_DIR:-(unset)}" "(unset)"
assert_contains "attach called"            "$_last_attach" "vet-b-$_T_ID"
assert_session_running "session still running" "$_T_SESS_B"

# ── cluster-join (active cluster marked) ─────────────────────────────────────

print "\n── cluster-join (active marker) ──"
# The active marker is driven by $CLUSTER_DIR in the calling shell — set it
# manually since cluster-join no longer does so.
export CLUSTER_DIR="$_T_DIR_B"
_run_join 1
assert_contains "active marker shown" "$_join_out" "← active"
unset CLUSTER_DIR

# ── cluster-join (session missing → prompt to resurrect) ─────────────────────

print "\n── cluster-join (session missing, decline resurrect) ──"
# vet-a session was killed earlier; it is item 2 in the list. Selecting it
# triggers the resurrect prompt. Pipe "2\nn" to decline.
_t_pre_dir="${CLUSTER_DIR:-(unset)}"
_run_join $'2\nn'
assert_contains "not-running message"        "$_join_out" "not running"
assert_contains "resurrect prompt shown"     "$_join_out" "Resurrect"
assert_contains "aborted message"            "$_join_out" "aborted"
assert_eq       "CLUSTER_DIR unchanged"      "${CLUSTER_DIR:-(unset)}" "$_t_pre_dir"
assert_eq       "attach NOT called"          "$_last_attach" ""
assert_session_gone "session still gone (declined)" "$_T_SESS_A"

print "\n── cluster-join (session missing, accept resurrect) ──"
_run_join $'2\ny'
assert_contains "resurrect prompt shown"        "$_join_out" "Resurrect"
assert_contains "joined message"                "$_join_out" "Joined cluster"
assert_contains "attach called on resurrected"  "$_last_attach" "$_T_SESS_A"
assert_session_running "session resurrected"    "$_T_SESS_A"
_T_SESSIONS+=("$_T_SESS_A")
# Resurrected session env should carry CLUSTER_DIR for spawned shells.
_t_resurrected_env="$(tmux showenv -t "$_T_SESS_A" CLUSTER_DIR 2>/dev/null)"
assert_contains "resurrected session env has CLUSTER_DIR" "$_t_resurrected_env" "vet-a-$_T_ID"

# ── cluster-join (invalid selection) ─────────────────────────────────────────

print "\n── cluster-join (invalid selection) ──"
_run_join 999
assert_contains "invalid selection error" "$_join_out" "invalid selection"

# ── cluster-join (no clusters) ───────────────────────────────────────────────

print "\n── cluster-join (no clusters) ──"
_t_empty="$(mktemp -d)"
_t_saved_base="$CLUSTER_BASE"; CLUSTER_BASE="$_t_empty"
_t_out="$(cluster-join 2>&1)"
assert_contains "no clusters message" "$_t_out" "no clusters to join"
CLUSTER_BASE="$_t_saved_base"; rm -rf "$_t_empty"

# ── nn (no active cluster) ───────────────────────────────────────────────────

print "\n── nn (no active cluster) ──"
unset CLUSTER_DIR
_t_out="$(nn 2>&1)"
assert_contains "error: no active cluster" "$_t_out" "no active cluster"

# ── nn (session not running) ─────────────────────────────────────────────────

print "\n── nn (session not running) ──"
tmux kill-session -t "${_T_DIR_A:t}" 2>/dev/null
_T_SESSIONS=("${_T_SESSIONS[@]:#${_T_DIR_A:t}}")
export CLUSTER_DIR="$_T_DIR_A"
_t_out="$(nn 2>&1)"
assert_contains "error: session not running" "$_t_out" "not running"

# ── cluster-rename (happy path) ──────────────────────────────────────────────

print "\n── cluster-rename (happy path) ──"
# cluster-rename runs from a shell inside the cluster — it requires
# CLUSTER_DIR. Set it manually (cluster-join no longer does so in the
# launching shell). vet-b is the rename target; its session is still running.
export CLUSTER_DIR="$_T_DIR_B"
assert_contains "setup: CLUSTER_DIR set" "$CLUSTER_DIR" "vet-b-$_T_ID"
_t_rename_old_dir="$CLUSTER_DIR"
_t_rename_old_sess="${CLUSTER_DIR:t}"
_t_rename_new_slug="vet-renamed-$_T_ID"

# Run cluster-rename directly (not in $()) so CLUSTER_DIR propagates back
_t_f="$(mktemp)"
cluster-rename "$_t_rename_new_slug" > "$_t_f" 2>&1
_t_out="$(< "$_t_f")"; rm -f "$_t_f"
_t_rename_new_dir="$CLUSTER_DIR"

assert_eq           "old dir is gone"            "$([ -d "$_t_rename_old_dir" ] && echo yes || echo no)" "no"
assert_contains     "new dir exists"              "$_t_rename_new_dir"       "$_t_rename_new_slug"
assert_eq           "new dir is on disk"          "$([ -d "$_t_rename_new_dir" ] && echo yes || echo no)" "yes"
assert_contains     "CLUSTER_DIR updated"         "$CLUSTER_DIR"             "$_t_rename_new_slug"
assert_contains     "join.sh updated"             "$(< "$_t_rename_new_dir/join.sh")" "$_t_rename_new_slug"
assert_contains     "notes.txt header updated"    "$(< "$_t_rename_new_dir/notes.txt")" "$_t_rename_new_slug"
assert_session_running "tmux session renamed"     "${_t_rename_new_dir:t}"
assert_session_gone    "old session gone"         "$_t_rename_old_sess"
assert_contains     "success message shown"       "$_t_out" "Renamed:"
assert_contains     "stale-shell warning shown"   "$_t_out" "source"

# Update tracking vars so cluster-shutdown can clean up the renamed session
_T_SESS_B="${_t_rename_new_dir:t}"
_T_DIR_B="$_t_rename_new_dir"
_T_SESSIONS=("${_T_SESSIONS[@]:#$_t_rename_old_sess}")
_T_SESSIONS+=("$_T_SESS_B")

# ── cluster-rename (error cases) ─────────────────────────────────────────────

print "\n── cluster-rename (error cases) ──"

# empty slug
_t_out="$(cluster-rename "" 2>&1)"
assert_contains "empty slug error" "$_t_out" "cannot be empty"

# invalid chars
_t_out="$(cluster-rename "bad slug!" 2>&1)"
assert_contains "invalid chars error" "$_t_out" "letters, digits"

# same name — extract current slug from dir basename
_t_ts="$(echo "${_T_DIR_B:t}" | cut -d- -f1-4)"
_t_current_slug="${${_T_DIR_B:t}#${_t_ts}-}"
_t_out="$(cluster-rename "$_t_current_slug" 2>&1)"
assert_contains "same-name error" "$_t_out" "identical to current name"

# collision — create a dir whose name would match the rename target
_t_collision_slug="collision-$_T_ID"
_t_collision_ts="$(echo "${_T_DIR_B:t}" | cut -d- -f1-4)"
mkdir -p "$_T_BASE/${_t_collision_ts}-${_t_collision_slug}"
_t_out="$(cluster-rename "$_t_collision_slug" 2>&1)"
assert_contains "collision error" "$_t_out" "already exists"
rmdir "$_T_BASE/${_t_collision_ts}-${_t_collision_slug}"

# ── cluster-shutdown ─────────────────────────────────────────────────────────

print "\n── cluster-shutdown ──"
# cluster-shutdown requires an active cluster in this shell. Set CLUSTER_DIR
# manually (cluster-join no longer does so in the launching shell).
export CLUSTER_DIR="$_T_DIR_B"
assert_eq "setup: CLUSTER_DIR set for shutdown test" "$CLUSTER_DIR" "$_T_DIR_B"
assert_session_running "session running before shutdown" "$_T_SESS_B"
cluster-shutdown > /dev/null
assert_eq           "CLUSTER_DIR unset"      "${CLUSTER_DIR:-(unset)}" "(unset)"
assert_session_gone "tmux session killed"    "$_T_SESS_B"
assert_file_exists  "notes.txt preserved"    "$_T_DIR_B/notes.txt"
_T_SESSIONS=("${_T_SESSIONS[@]:#$_T_SESS_B}")

# ── cluster-leave ────────────────────────────────────────────────────────────

print "\n── cluster-leave ──"
# no active cluster
unset CLUSTER_DIR
_t_out="$(cluster-leave 2>&1)"
assert_contains "no-cluster error" "$_t_out" "no active cluster"

# active cluster, session not running (vet-b dir still exists post-shutdown)
export CLUSTER_DIR="$_T_DIR_B"
# Run directly (not in $()) so CLUSTER_DIR unset propagates back to this shell
_t_f="$(mktemp)"
cluster-leave > "$_t_f" 2>&1
_t_out="$(< "$_t_f")"; rm -f "$_t_f"
assert_contains    "left message shown"      "$_t_out" "Left cluster"
assert_contains    "rejoin hint shown"       "$_t_out" "cluster-join"
assert_eq          "CLUSTER_DIR unset"       "${CLUSTER_DIR:-(unset)}" "(unset)"
assert_file_exists "notes.txt preserved"     "$_T_DIR_B/notes.txt"

# ── cluster-leave (inside tmux) ──────────────────────────────────────────────
# Verify the tmux branch: when $TMUX is set, cluster-leave kills the current
# window, logs the leave to history.log, and detaches the client. The session
# runs detached (no client attached) so we drive it via send-keys and inspect
# state from outside.

print "\n── cluster-leave (inside tmux: not-last window) ──"
_t_lsess="cluster-leave-test-$_T_ID"
_t_lcluster="$_T_BASE/2026-05-29-1300-leave-test-$_T_ID"
mkdir -p "$_t_lcluster"
: > "$_t_lcluster/history.log"
# Create a detached session with two windows; cluster-leave runs in win2.
tmux new-session -d -s "$_t_lsess" -n win1 2>/dev/null
tmux new-window  -t "$_t_lsess" -n win2 2>/dev/null
_T_SESSIONS+=("$_t_lsess")
# Drive win2's shell: source cluster.zsh, set CLUSTER_DIR, run cluster-leave.
tmux send-keys -t "$_t_lsess:win2" "source $PWD/cluster.zsh"  Enter
tmux send-keys -t "$_t_lsess:win2" "export CLUSTER_DIR='$_t_lcluster'" Enter
tmux send-keys -t "$_t_lsess:win2" "cluster-leave"            Enter
# Poll up to ~1s for the window to disappear.
_t_wcount=99
for _ in 1 2 3 4 5 6 7 8 9 10; do
  _t_wcount=$(tmux list-windows -t "$_t_lsess" 2>/dev/null | wc -l | tr -d ' ')
  [[ "$_t_wcount" == "1" ]] && break
  sleep 0.1
done
assert_eq       "win2 killed; only win1 remains"   "$_t_wcount" "1"
assert_contains "leave logged to history.log"      "$(< "$_t_lcluster/history.log")" "cluster-leave"

print "\n── cluster-leave (inside tmux: last window) ──"
# Now run cluster-leave in win1 — the only remaining window. kill-window on
# the sole window kills the session entirely.
tmux send-keys -t "$_t_lsess:win1" "source $PWD/cluster.zsh"  Enter
tmux send-keys -t "$_t_lsess:win1" "export CLUSTER_DIR='$_t_lcluster'" Enter
tmux send-keys -t "$_t_lsess:win1" "cluster-leave"            Enter
# Poll for session death.
_t_alive=1
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! tmux has-session -t "$_t_lsess" 2>/dev/null; then
    _t_alive=0; break
  fi
  sleep 0.1
done
assert_eq "session died after last window killed" "$_t_alive" "0"
_T_SESSIONS=("${_T_SESSIONS[@]:#$_t_lsess}")

# ── summary ───────────────────────────────────────────────────────────────────

print "\n══════════════════════════════════════"
print "  Passed: $_pass   Failed: $_fail"
print "══════════════════════════════════════\n"
(( _fail == 0 ))
