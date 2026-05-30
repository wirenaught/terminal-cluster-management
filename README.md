# cluster.zsh

A zsh + tmux workflow for keeping each task you work on isolated in its own
named **cluster**: a directory, a tmux session, a notes file, and a command
history log — all bound together and rejoinable on demand.

If you regularly juggle several pieces of work in parallel and lose track of
which terminal tabs belong to which task, this is for you.

For the conceptual framing — what a cluster is and what problem it solves — see
[CONCEPT.md](./CONCEPT.md).

---

## What's a "cluster"?

A cluster is a single unit of work. Concretely, each cluster has:

| Piece | Where | Purpose |
|---|---|---|
| Directory | `~/.clusters/<timestamp>-<slug>/` | Filesystem home for the cluster |
| `notes.txt` | inside the dir | Free-form scratchpad, opened on init |
| `history.log` | inside the dir | Every command run in any shell joined to the cluster |
| `join.sh` | inside the dir | Sourceable shim that exports `CLUSTER_DIR` |
| tmux session | named the same as the dir | All your windows for this task |
| `$CLUSTER_DIR` | shell env var | "I am joined to this cluster" marker |

Anything you do while `CLUSTER_DIR` is set gets logged. Anything you open with
`nn` becomes a tab in the cluster's tmux session. The prompt shows you the
cluster name in blue brackets so you never have to guess.

Activation is **shell-local and explicit**: a shell is "in" a cluster only if
it joined one (via `cluster-init`, `cluster-join`, or by being spawned inside
the cluster's tmux session). New terminal windows (`cmd-t`) start clean — no
silent restoration. To get back into a cluster from a fresh shell, run
`cluster-join`.

---

## Requirements

- **zsh** (the prompt and hooks rely on zsh features)
- **tmux** with these plugins for crash/reboot survival:
  - [`tmux-resurrect`](https://github.com/tmux-plugins/tmux-resurrect)
  - [`tmux-continuum`](https://github.com/tmux-plugins/tmux-continuum)
- **nano** (used to open `notes.txt`; swap in your editor of choice by editing
  the two `nano` calls in `cluster.zsh`)
- **iTerm2** *(optional)* — enables native-tab integration via `tmux -CC`.
  Apple Terminal and other terminals fall back to plain `tmux attach`.

## Installation

See [INSTALL.md](./INSTALL.md) for the full setup (sourcing from `~/.zshrc`,
tmux plugin install, resurrect/continuum config).

---

## Quick start

```zsh
# Start a new cluster called "auth-bug"
cluster-init auth-bug

# You're now inside tmux. Open more windows in this cluster:
nn

# Edit cluster notes any time:
notes

# Done for the day — just close the terminal. tmux session keeps running.
# Next shell starts clean (no cluster). To pick back up:

# Come back to it (interactive picker, defaults to most recent):
cluster-join
```

That's it. Read on for the full command set and workflows.

---

## Command reference

| Command | What it does |
|---|---|
| `cluster-init [slug]` | Create a new cluster dir, start a named tmux session, open `notes.txt`, attach |
| `cluster-join` | Numbered interactive list of all clusters (most recent first, active cluster marked). Pick one to attach to its tmux session. If the session isn't running, prompts `Resurrect it now? [y/N]` — `y` recreates the session and attaches, anything else aborts. `$CLUSTER_DIR` lands in shells spawned inside the session, not in the calling shell |
| `cluster-leave` | Step away from the active cluster in this shell. Unsets `$CLUSTER_DIR`; if this client is attached to the cluster's tmux session, also detaches it (session keeps running, other clients/panes unaffected). On-disk artifacts untouched |
| `cluster-shutdown` | Kill the active cluster's tmux session and clear `$CLUSTER_DIR`. Notes and history are preserved on disk |
| `cluster-list` | List all clusters under `~/.clusters/`, most recent first |
| `cluster-status` | Show active cluster and whether its tmux session is running |
| `cluster-history` | Print the active cluster's `history.log` |
| `cluster-help` | List all cluster commands with usage signatures and one-line summaries (parsed from `cluster.zsh` itself) |
| `notes` | Open the active cluster's `notes.txt` in nano |
| `cluster-note "<text>"` | Append a timestamped entry to the cluster's `notes.txt` — usable by you or by AI agents (see [AI integration](#ai-integration)) |
| `cluster-notes` | Print the cluster's `notes.txt` to stdout (use `notes` if you want to edit instead) |
| `nn` | New tmux window in the active cluster, already joined. Outside tmux it opens a new terminal window and attaches |

### Naming and selection

`cluster-init` names the cluster `YYYY-MM-DD-HHMM` plus an optional `-slug`,
e.g. `2026-05-25-1430-auth-bug`. The directory basename **is** the tmux session
name — that's what `tmux-resurrect` saves.

`cluster-join` always shows the full interactive picker (numbered list, most
recent first). Default selection `[1]` picks the most recent cluster.

---

## Workflows

### Starting a new task

```zsh
cluster-init fix-login-redirect
```

You'll land in a fresh tmux session, `notes.txt` open in nano. Jot down
context — ticket link, repro steps, hypothesis — and Ctrl+X to save. Open more
windows with `nn` as you need them: one for the test runner, one for git, one
for `tail -f` on logs.

### Switching tasks

Don't bother shutting things down. Just open a new terminal window outside the
current tmux session and:

```zsh
cluster-init other-thing
```

The old cluster's tmux session stays running. The new shell is now bound to the
new cluster. To go back to the previous one:

```zsh
cluster-join
```

### Coming back after a reboot

`tmux-continuum` automatically restarts the tmux server on login and restores
saved sessions. Your shells start clean (no auto-restore of `$CLUSTER_DIR`),
so when you're ready to resume:

```zsh
cluster-join          # pick from the list — attaches to the live session
```

If continuum hasn't restored the session yet (or never saved it),
`cluster-join` notices and asks `Resurrect it now? [y/N]`. Answer `y` and it
recreates the tmux session (sourcing `join.sh` in window 1) and attaches.
Notes and history are still on disk; only the live tmux state was missing.

### Wrapping up a task for good

```zsh
cluster-shutdown
```

The tmux session is killed; the directory, `notes.txt`, and `history.log` are
preserved. To revive it later, run `cluster-join` and pick it — it'll notice
the session is gone and prompt to resurrect it on the spot.

### Stepping away without shutting down

```zsh
cluster-leave
```

Unsets `$CLUSTER_DIR` in this shell. If you're inside the cluster's tmux
session, also detaches this client — your terminal returns to a plain shell
and stops showing tmux. The session itself keeps running and other
clients/panes are unaffected. Useful when you want a clean shell for
unrelated work but aren't done with the cluster. Rejoin any time with
`cluster-join`.

### Joining an existing cluster in one extra shell

You opened a new terminal tab outside tmux but want it logged to the active
cluster:

```zsh
cluster-join          # interactive picker — default [1] selects most recent
```

This activates `$CLUSTER_DIR`, starts logging, and attaches to the cluster's
tmux session. If you want to join a cluster for logging only without
touching tmux, source its `join.sh` directly:

```zsh
source ~/.clusters/2026-05-25-1430-auth-bug/join.sh
```

---

## Files & state

```
~/.clusters/
  2026-05-25-1430-auth-bug/
    join.sh           # sourceable: exports CLUSTER_DIR
    notes.txt         # scratchpad, seeded with name+start time
    history.log       # appended by precmd hook on every command
    AGENTS.md         # per-cluster instructions for AI tools (see AI integration)
  2026-05-24-0915-other-thing/
    ...
```

**`CLUSTER_DIR`** is the single source of truth for "which cluster is this
shell on." Under the current model, `cluster-init` and `cluster-join` do
**not** export `CLUSTER_DIR` in the calling shell — they only set it in the
tmux session env. The variable lands in your shell when:

- A new tmux window/pane opens inside a cluster session (tmux propagates the
  session env to spawned shells).
- You `source $CLUSTER_DIR/join.sh` manually (the only way to put a non-tmux
  shell into a cluster).

And it is unset by:

- `cluster-leave` (this shell only; also detaches if you're inside the
  cluster's tmux session).
- `cluster-shutdown` (this shell; tmux session is killed).

There is **no persistent state file** and **no auto-restore**. A fresh
terminal starts with no `$CLUSTER_DIR` and stays clean until you explicitly
`cluster-join` (which attaches you to the existing tmux session). The
trade-off vs the previous auto-restore design: you run one extra command
after a reboot to re-attach, but `cmd-t` is never surprising.

### History logging

A `precmd` hook (`_cluster_log_command`) fires after every command in any
shell where `$CLUSTER_DIR` is set, appending:

```
[14:32:07 shell:48211] git rebase -i HEAD~3
```

…to `$CLUSTER_DIR/history.log`. The shell PID lets you separate concurrent
tabs after the fact. If `$CLUSTER_DIR` is unset or its directory no longer
exists, the hook is a no-op — safe to leave installed permanently.

---

## Prompt & terminal integration

The prompt is two lines:

```
[2026-05-25-1430-auth-bug] kimball@laptop ~/code/app
❯
```

Line 1: cluster (blue, omitted when no cluster is active), user@host (green),
path (yellow). Line 2: clean `❯` for typing. Powered by `PROMPT_SUBST` and a
`_cluster_prompt_segment` helper — adjust colors in `cluster.zsh` if you want.

### iTerm2 (`-CC` mode)

When `$TERM_PROGRAM == iTerm.app`, attaches use `tmux -CC`, which makes tmux
windows appear as native iTerm tabs. `nn` from outside tmux opens a new iTerm
window via `osascript` and attaches there.

### Apple Terminal

Falls back to plain `tmux attach`. `nn` from outside tmux uses AppleScript to
open a new Terminal window and run `tmux attach-session -t <name>`.

### Other terminals

Plain `tmux attach`. `nn` from outside tmux prints the exact command you'd
need to paste — no AppleScript automation.

---

## AI integration

Because `$CLUSTER_DIR` is set in every shell spawned inside a cluster's
tmux session, any AI tool you launch from that shell (Claude Code, OpenCode,
etc.) inherits it. That's the only wiring needed — discovery is free.

Two pieces give AI tools a clean protocol for the notes file:

- **`cluster-note "<text>"`** and **`cluster-notes`** — the writer/reader pair
  documented above. The writer owns format (timestamp + blank-line separation),
  so notes you take by hand at the shell and notes an agent writes for you
  share the same shape.
- **`$CLUSTER_DIR/AGENTS.md`** — seeded by `cluster-init` into every new
  cluster. Contains the trigger phrases, capture protocol, and recall
  protocol the agent follows. Editable per-cluster, so different threads of
  work can have different conventions, and the file can hold free-form
  per-cluster context the agent picks up when triggered.

To wire the global side, add this to `~/.claude/CLAUDE.md` (or your
OpenCode-readable equivalent):

```markdown
## Cluster integration (cluster.zsh)

If `$CLUSTER_DIR` is set in this session, and the user mentions cluster
notes, cluster context, or asks what we've been working on in this cluster,
read `$CLUSTER_DIR/AGENTS.md` first and follow its instructions. The
cluster's instruction file is authoritative; this global rule only points
to it.
```

Then in any AI session inside a cluster, "capture this to cluster notes" or
"what's in the cluster notes?" works without further setup. Multiple
clusters in the same repo do the right thing automatically — each shell
carries its own `$CLUSTER_DIR`.

---

## Troubleshooting

**`cluster-join` prompts to resurrect a session**
When the saved tmux session is gone (after `cluster-shutdown`, a reboot
before continuum saved, or a crash), `cluster-join` asks `Resurrect it now?
[y/N]` instead of silently recreating it. Answer `y` to recreate and attach;
anything else aborts. Notes and history on disk are untouched either way.

**The prompt isn't showing the cluster name in a new terminal**
That's expected. New shells (`cmd-t`) start with no `$CLUSTER_DIR` — there's
no persistent state. Run `cluster-join` to pick from the interactive list.
If `cluster-join` set `$CLUSTER_DIR` but the prompt is still blank, confirm
`setopt PROMPT_SUBST` is in effect — another `.zshrc` line may be overwriting
`PROMPT` after `cluster.zsh` is sourced.

**`nn` opens a new window outside the cluster**
You're outside tmux *and* outside iTerm2/Apple Terminal. `nn` only knows how
to automate iTerm2 and Terminal.app; for other terminals it prints the tmux
command to run manually.

**History log isn't growing**
The hook only logs if `$CLUSTER_DIR` is set **and** its directory exists. If
you deleted a cluster dir without unsetting `CLUSTER_DIR`, logging silently
stops for that shell. Run `cluster-shutdown` or `unset CLUSTER_DIR`.

**`cluster-shutdown` closed all my tabs**
That's the documented behavior when you run it from inside the session being
killed — tmux tears down the session and all attached clients exit. Run it
from a shell outside the cluster's tmux session if you want to kill silently.

**I want a different editor than nano**
Edit the two `nano` invocations in `cluster.zsh` (one in `cluster-init`, one
in `notes`). Anything that opens a file works.

---

## Layout

```
.
├── cluster.zsh        # the script (source this from ~/.zshrc)
├── CONCEPT.md         # the "why" — what a cluster is and what it's for
├── concept.svg        # diagram embedded in CONCEPT.md
├── INSTALL.md         # setup instructions
└── README.md          # this file
```
