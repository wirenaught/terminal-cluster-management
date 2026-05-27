# cluster.zsh

A zsh + tmux workflow for keeping each task you work on isolated in its own
named **cluster**: a directory, a tmux session, a notes file, and a command
history log — all bound together and auto-restored across shell restarts.

If you regularly juggle several pieces of work in parallel and lose track of
which terminal tabs belong to which task, this is for you.

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

The currently active cluster is persisted in `~/.config/cluster/last-cluster`,
so a new shell auto-restores the last one you were on.

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

# Done for the day — just close the terminal. State is saved.
# Next shell auto-restores CLUSTER_DIR.

# Come back to it:
cluster-reopen auth-bug
```

That's it. Read on for the full command set and workflows.

---

## Command reference

| Command | What it does |
|---|---|
| `cluster-init [name]` | Create a new cluster dir, start a named tmux session, open `notes.txt`, attach |
| `cluster-join [dir]` | Join a cluster in the **current shell only** (sets `$CLUSTER_DIR`, no tmux). Defaults to most recent cluster |
| `cluster-activate [name-fragment]` | Like `cluster-join`, but interactive picker when no arg is given. Use before `cluster-reopen` |
| `cluster-reopen [name-fragment]` | Attach to the tmux session for the active or named cluster. Creates a fresh session if continuum hasn't restored one |
| `cluster-shutdown` | Kill the active cluster's tmux session. Notes and history are preserved on disk |
| `cluster-list` | List all clusters under `~/.clusters/`, most recent first |
| `cluster-status` | Show active cluster and whether its tmux session is running |
| `cluster-history` | Print the active cluster's `history.log` |
| `notes` | Open the active cluster's `notes.txt` in nano |
| `cluster-note "<text>"` | Append a timestamped entry to the cluster's `notes.txt` — usable by you or by AI agents (see [AI integration](#ai-integration)) |
| `cluster-notes` | Print the cluster's `notes.txt` to stdout (use `notes` if you want to edit instead) |
| `nn` | New tmux window in the active cluster, already joined. Outside tmux it opens a new terminal window and attaches |

### Naming and selection

`cluster-init` names the cluster `YYYY-MM-DD-HHMM` plus an optional `-slug`,
e.g. `2026-05-25-1430-auth-bug`. The directory basename **is** the tmux session
name — that's what `tmux-resurrect` saves, and what `cluster-reopen` greps for.

Anywhere a command takes `[name-fragment]`, it does a substring match against
the directory basename and picks the most recent hit. Use enough characters to
disambiguate, or use the interactive picker (`cluster-activate` with no arg).

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
cluster-reopen fix-login-redirect
```

### Coming back after a reboot

`tmux-continuum` automatically restarts the tmux server on login and restores
saved sessions, so:

```zsh
# New shell starts. CLUSTER_DIR is auto-restored from the state file.
cluster-status        # confirms which cluster, whether session is running
cluster-reopen        # attaches to it
```

If continuum hasn't run yet (e.g. you logged in but didn't open a terminal for
a while), `cluster-reopen` creates a fresh session with the same name — your
notes and history are still there, just the live tmux state is gone.

### Wrapping up a task for good

```zsh
cluster-shutdown
```

The tmux session is killed; the directory, `notes.txt`, and `history.log` are
preserved. To revive it later for reference:

```zsh
cluster-activate fix-login-redirect    # sets CLUSTER_DIR
cluster-history                        # browse what you ran
notes                                  # browse what you wrote
```

To revive it as a live working session, `cluster-reopen <name>` instead.

### Joining an existing cluster in one extra shell

You opened a new terminal tab outside tmux but want it logged to the active
cluster:

```zsh
cluster-join          # most recent cluster
# or
cluster-join ~/.clusters/2026-05-25-1430-auth-bug
```

This only sets `$CLUSTER_DIR` and starts logging — it doesn't touch tmux.

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

~/.config/cluster/
  last-cluster        # path to the most recently active cluster
```

**`CLUSTER_DIR`** is the single source of truth for "which cluster is this
shell on." It's set by:

- `cluster-init` (new cluster)
- `cluster-join` / `cluster-activate` / `cluster-reopen` (existing cluster)
- The auto-restore block at the top of `cluster.zsh` (new shell startup)
- `source $CLUSTER_DIR/join.sh` (manual or from a fresh tmux window via `nn`)

**`last-cluster`** is rewritten every time `_cluster_activate` runs. It's how
new shells know what to restore. `cluster-shutdown` removes it.

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

Because `$CLUSTER_DIR` is exported in every cluster-joined shell, any AI tool
you launch from that shell (Claude Code, OpenCode, etc.) inherits it. That's
the only wiring needed — discovery is free.

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

**`cluster-reopen` says "tmux session not found"**
Continuum didn't restore the session (either it was never saved, the resurrect
file is missing, or you ran `cluster-reopen` before continuum kicked in). The
command creates a fresh empty session with the same name — your notes and
history are intact. Re-open whatever windows you need with `nn`.

**The prompt isn't showing the cluster name**
Check `echo $CLUSTER_DIR`. If empty, the auto-restore didn't fire (state file
missing, or its target directory is gone). Run `cluster-activate <fragment>`
to pick one. If `CLUSTER_DIR` is set but the prompt is blank, confirm
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
├── INSTALL.md         # setup instructions
└── README.md          # this file
```
