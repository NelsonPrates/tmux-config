#!/usr/bin/env bash
# Install this tmux configuration on top of Oh my tmux! (gpakosz/.tmux).
#
#   - clones Oh my tmux! into ~/.tmux and links ~/.tmux.conf, if not present
#   - links ~/.tmux.conf.local        -> <repo>/tmux.conf.local
#   - links ~/.local/bin/tmux-sysstat -> <repo>/bin/tmux-sysstat
#   - backs up any existing regular file as <file>.bak-<timestamp>
#   - reloads tmux if a server is running
#
# Safe to run more than once.

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
OH_MY_TMUX_URL=https://github.com/gpakosz/.tmux.git
OH_MY_TMUX_DIR=$HOME/.tmux
STAMP=$(date +%Y%m%d%H%M%S)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# link <target> <link-path>: replace link-path with a symlink, backing up files
link() {
  local target=$1 path=$2
  mkdir -p "$(dirname "$path")"
  if [[ -L $path && $(readlink -f "$path") == "$(readlink -f "$target")" ]]; then
    info "already linked: $path"
    return
  fi
  if [[ -e $path || -L $path ]]; then
    mv "$path" "$path.bak-$STAMP"
    info "backed up: $path -> $path.bak-$STAMP"
  fi
  ln -s "$target" "$path"
  info "linked: $path -> $target"
}

command -v tmux >/dev/null || { echo "error: tmux is not installed" >&2; exit 1; }
command -v flock >/dev/null || { echo "error: flock (util-linux) is not installed" >&2; exit 1; }
((BASH_VERSINFO[0] >= 5)) || { echo "error: bash >= 5.0 is required" >&2; exit 1; }

if [[ ! -f $OH_MY_TMUX_DIR/.tmux.conf ]]; then
  info "cloning Oh my tmux! into $OH_MY_TMUX_DIR"
  git clone --single-branch "$OH_MY_TMUX_URL" "$OH_MY_TMUX_DIR"
fi
link "$OH_MY_TMUX_DIR/.tmux.conf" "$HOME/.tmux.conf"
link "$REPO_DIR/tmux.conf.local" "$HOME/.tmux.conf.local"
link "$REPO_DIR/bin/tmux-sysstat" "$HOME/.local/bin/tmux-sysstat"

if tmux info >/dev/null 2>&1; then
  info "reloading tmux"
  tmux source-file "$HOME/.tmux.conf"
fi

info "done"
