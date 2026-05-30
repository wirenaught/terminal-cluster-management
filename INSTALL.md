# cluster.zsh — installation guide

This guide installs the cluster system from scratch on a new machine. Follow
the steps in order. Each step is self-contained and verifiable before moving
to the next.

---

## Prerequisites

- macOS with zsh (default on macOS Catalina and later)
- [iTerm2](https://iterm2.com) installed (recommended; Terminal.app also works)
- [Homebrew](https://brew.sh) installed
- This repo cloned locally; commands below assume your working directory is the repo root

---

## Step 1 — Install tmux

```zsh
brew install tmux
```

Verify:
```zsh
tmux -V
# tmux 3.6a (or later)
```

---

## Step 2 — Install tpm (tmux plugin manager)

```zsh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

---

## Step 3 — Write ~/.tmux.conf

Create or overwrite `~/.tmux.conf` with the following:

```
# ~/.tmux.conf

# ── terminal and color support ────────────────────────────────────────────────
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Propagate CLUSTER_DIR from an attaching client into the session env, so
# panes split inside the session inherit the active cluster.
set -ga update-environment "CLUSTER_DIR"

# ── prefix key ────────────────────────────────────────────────────────────────
# Remap prefix from Ctrl-b to Ctrl-a (easier to reach)
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix

# ── general behavior ──────────────────────────────────────────────────────────
set -g mouse on                   # mouse resize/click panes and windows
set -g set-clipboard on           # OSC 52: mouse-drag selection → system clipboard
                                  # (requires iTerm prefs → General → Selection
                                  # → "Applications in terminal may access clipboard")
set -g history-limit 50000        # scrollback buffer
set -g display-time 4000          # status message display duration (ms)
set -g focus-events on            # pass focus events to apps (vim, etc.)
set -sg escape-time 0             # no delay for escape key (important for vim)
set -g base-index 1               # windows start at 1 not 0
set -g pane-base-index 1          # panes start at 1 not 0
set -g renumber-windows on        # renumber windows when one is closed

# ── key bindings ──────────────────────────────────────────────────────────────
bind c new-window -c "#{pane_current_path}"       # new window in same dir
bind '"' split-window -c "#{pane_current_path}"   # split horizontal, same dir
bind % split-window -h -c "#{pane_current_path}"  # split vertical, same dir
bind R source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"

# ── clipboard ─────────────────────────────────────────────────────────────────
# Mouse drag-release: pipe selection straight to pbcopy. Works in any terminal
# (iTerm, Terminal.app, etc.) — does not rely on OSC 52. -no-clear keeps the
# highlight visible after release (press q to dismiss copy-mode).
# Bound in both copy-mode tables so it fires whether mode-keys is emacs (default)
# or vi.
bind-key -T copy-mode    MouseDragEnd1Pane send-keys -X copy-pipe-no-clear "pbcopy"
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-no-clear "pbcopy"

# ── window title (shown in iTerm2 window/tab title bar) ──────────────────────
set -g set-titles on
set -g set-titles-string "#{session_name} • #{window_name}"

# ── status bar ────────────────────────────────────────────────────────────────
set -g status on
set -g status-interval 5
set -g status-position bottom
set -g status-style "bg=#1e1e2e,fg=#cdd6f4"

# Left: session name (cluster name)
set -g status-left-length 40
set -g status-left "#[bg=#89b4fa,fg=#1e1e2e,bold] #S #[bg=#1e1e2e,fg=#89b4fa] "

# Right: last save time (HH:MM) + date and time
set -g status-right-length 80
set -g status-right "#[fg=#a6e3a1]saved:#{?#{@continuum-save-last-timestamp},#(date -r #{@continuum-save-last-timestamp} +%%H:%%M 2>/dev/null || echo --:--),--:--} #[fg=#6c7086] %Y-%m-%d #[fg=#cdd6f4]%H:%M "

# Window tabs
set -g window-status-format "#[fg=#6c7086] #I:#W "
set -g window-status-current-format "#[bg=#313244,fg=#cdd6f4,bold] #I:#W "

# Pane borders
set -g pane-border-style "fg=#313244"
set -g pane-active-border-style "fg=#89b4fa"

# ── plugins ───────────────────────────────────────────────────────────────────
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# resurrect: also restore pane contents
set -g @resurrect-capture-pane-contents 'on'

# continuum: auto-save every 1 min, auto-restore on tmux start
set -g @continuum-restore 'on'
set -g @continuum-save-interval '1'

# ── initialize tpm (must be last line) ───────────────────────────────────────
run '~/.tmux/plugins/tpm/tpm'
```

---

## Step 4 — Install tmux plugins

Start a tmux server, source the config, and install the plugins:

```zsh
tmux new-session -d -s install
tmux source-file ~/.tmux.conf
~/.tmux/plugins/tpm/bin/install_plugins
tmux kill-session -t install
```

Verify:
```zsh
ls ~/.tmux/plugins/
# tmux-continuum  tmux-resurrect  tpm
```

### Clipboard: terminal-specific notes

The tmux.conf above uses **two** mechanisms to push mouse-drag selections to
the system clipboard:

- **`copy-pipe-no-clear "pbcopy"` binding** — works everywhere `pbcopy` is on
  PATH (any local macOS terminal). This is the primary path.
- **`set -g set-clipboard on`** — emits OSC 52 escape sequences so a tmux
  session running on a remote host (via SSH) can also reach your local
  clipboard, provided the local terminal honors OSC 52.

**iTerm2** honors OSC 52 only if you opt in:
**iTerm2 → Settings → General → Selection →
✓ "Applications in terminal may access clipboard"**
Without this, the `pbcopy` binding still works for local sessions; the
checkbox only matters for SSH'd-in remote-tmux scenarios.

**Terminal.app** does not support OSC 52 at all (Apple has never implemented
it). For local sessions, the `pbcopy` binding handles it. For SSH'd-in remote
tmux, the remote selection won't reach your Mac's clipboard — switch to
iTerm2 (with the checkbox on) if you need that.

**Bypassing tmux selection.** To select across pane borders (or anywhere
tmux's mouse capture gets in the way), hold a modifier while dragging:
- **iTerm2:** hold **⌥ (Option)** — drags become native iTerm selections.
- **Terminal.app:** hold **Fn** — drags become native Terminal selections.

In both cases use Edit → Copy or ⌘C to copy the native selection.

---

## Step 5 — Create the cluster config directory

```zsh
mkdir -p ~/.config/cluster
mkdir -p ~/.clusters
```

---

## Step 6 — Install cluster.zsh

Copy `cluster.zsh` from this repo into your cluster config directory:

```zsh
cp ./cluster.zsh ~/.config/cluster/cluster.zsh
```

This assumes you've cloned the repo and your working directory is the repo
root. If you've placed `cluster.zsh` somewhere else, adjust the source path
accordingly.

Verify:
```zsh
ls -l ~/.config/cluster/cluster.zsh
# -rw-r--r--  1 <user>  staff  ...  cluster.zsh
```

---

## Step 7 — Wire into ~/.zshrc

Add these two lines at the end of `~/.zshrc`:

```zsh
# cluster — terminal session grouping
[[ -f ~/.config/cluster/cluster.zsh ]] && source ~/.config/cluster/cluster.zsh
```

---

## Step 8 — Reload your shell

```zsh
source ~/.zshrc
```

Verify the prompt changed to the two-line format:
```
kimball.jensen@host ~
❯
```

---

## Step 9 — Verify everything works

```zsh
cluster-list
# No clusters yet   ← expected on a fresh install

cluster-status
# No active cluster   ← expected

tmux -V
# tmux 3.6a

ls ~/.tmux/plugins/
# tmux-continuum  tmux-resurrect  tpm
```

---

## Step 10 — First cluster

This command opens `notes.txt` in **nano** inside the tmux session — nano will occupy the active tmux window. That is expected. The file is pre-filled with header lines (your cluster name and start time). To exit: press **Ctrl-X**. If you typed anything, nano will prompt to save — press **Y**, then **Enter**. If you didn't change anything, nano exits silently.

```zsh
cluster-init my-first-cluster
```

This will:
- Create `~/.clusters/<timestamp>-my-first-cluster/`
- Start a tmux session with that name
- In iTerm2: attach via `-CC` — the session appears as a native window with a
  status bar at the bottom
- Open `notes.txt` in nano — jot anything, then `Ctrl-X` to save and exit
- Your prompt will update to show the cluster name

The status bar at the bottom of the tmux window shows:
```
 <session-name>    1:nano            saved:--:--   2026-05-25  HH:MM
```

---

## File layout after installation

```
~/.tmux.conf                          # tmux configuration
~/.tmux/plugins/
│   ├── tpm/                          # tmux plugin manager
│   ├── tmux-resurrect/               # session save/restore
│   └── tmux-continuum/               # automatic saves every 1 min
~/.config/cluster/
│   └── cluster.zsh                   # all cluster functions
~/.clusters/                          # one directory per cluster session
│   └── <timestamp>-<name>/
│       ├── notes.txt                 # shared scratchpad
│       ├── join.sh                   # sets $CLUSTER_DIR when sourced
│       └── history.log               # cross-terminal command log
~/.local/share/tmux/resurrect/        # tmux-resurrect save files
```

---

## Troubleshooting

**Prompt did not change after `source ~/.zshrc`**
Check that `cluster.zsh` is being sourced:
```zsh
grep cluster ~/.zshrc
```
Should show the source line from Step 7.

**`cluster-init` hangs or shows "open terminal failed"**
This happens when run from a non-interactive subshell. Run it from a real
iTerm2 or Terminal.app window.

**Status bar not visible**
The tmux status bar only appears inside an attached tmux session. Run
`cluster-init` or `cluster-join` to enter one.

**`Ctrl-a R` gives `bck-i-search:` or does nothing**
You are not inside a tmux session. `Ctrl-a` is intercepted by zsh outside
tmux. Enter a cluster session first with `cluster-join`.

**tmux-continuum not saving**
Check the last save timestamp:
```zsh
tmux show-options -gv @continuum-save-last-timestamp
```
If empty, reload tmux config from inside a session with `Ctrl-a R`.

**After reboot, no cluster active in new shells**
That's by design — new shells don't auto-restore. To resume:
```zsh
cluster-list          # see what's on disk
cluster-join          # pick one and attach
```
If `cluster-join` reports the tmux session isn't running, continuum didn't
save it before the reboot. Resurrect with `tmux new-session -d -s <name>`
then `cluster-join`, or `cluster-init` a fresh cluster.
