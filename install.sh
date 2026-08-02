#!/usr/bin/env bash
# crew installer.
#
# Cursor's documented install paths do not all work, so crew needs two steps:
#
#   skills   loaded via --plugin-dir, wired up by a shell function
#   agents   symlinked into each repo's .cursor/agents/, because plugin-bundled
#            agents silently ignore `model` and `readonly`
#
# Usage:
#   ./install.sh            link the plugin and report what is left to do
#   ./install.sh shell      append the cursor() function to your shell rc
#   ./install.sh agents [d] symlink crew's agents into repo d (default: cwd)
#   ./install.sh doctor     check every part of the install

set -euo pipefail

# Resolve this script's directory, following symlinks.
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  [[ $src != /* ]] && src="$dir/$src"
done
CREW="$(cd -P "$(dirname "$src")" && pwd)"

LOCAL_PLUGINS="$HOME/.cursor/plugins/local"
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
warn() { printf '  \033[33mtodo\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mfail\033[0m  %s\n' "$1"; }

shell_rc() {
  case "${SHELL##*/}" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) [ -f "$HOME/.bashrc" ] && printf '%s\n' "$HOME/.bashrc" || printf '%s\n' "$HOME/.bash_profile" ;;
    *)    printf '%s\n' "$HOME/.profile" ;;
  esac
}

read -r -d '' SHELL_FN <<'EOF' || true
# >>> crew >>>
# Load every plugin linked into ~/.cursor/plugins/local/. Cursor does not read
# that directory itself, so each entry becomes a --plugin-dir flag.
# Must be a function: a same-named alias would shadow it. unalias first, because
# zsh expands aliases while parsing a function definition.
unalias cursor 2>/dev/null || true
cursor() {
  local -a plugin_flags
  local d
  for d in "$HOME"/.cursor/plugins/local/*/; do
    [ -d "$d" ] || continue
    plugin_flags+=(--plugin-dir "$(cd -P "$d" && pwd)")
  done
  command cursor-agent "${plugin_flags[@]}" "$@"
}
# <<< crew <<<
EOF

link_plugin() {
  mkdir -p "$LOCAL_PLUGINS"
  ln -sfn "$CREW" "$LOCAL_PLUGINS/crew"
  ok "plugin linked: $LOCAL_PLUGINS/crew -> $CREW"
}

install_shell() {
  local rc; rc="$(shell_rc)"
  if grep -q '# >>> crew >>>' "$rc" 2>/dev/null; then
    ok "shell function already in $rc"
  elif grep -qE '^\s*(function\s+)?cursor\s*\(\)' "$rc" 2>/dev/null; then
    # Hand-written or older version. Appending would define it twice.
    warn "$rc already defines cursor() without the crew marker — left alone"
    warn "replace it by hand if you want the managed version, or delete it and rerun"
  else
    printf '\n%s\n' "$SHELL_FN" >> "$rc"
    ok "shell function appended to $rc"
    warn "run: source $rc"
  fi
}

install_agents() {
  local target="${1:-$PWD}"
  target="$(cd "$target" && pwd)"
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    bad "$target is not a git repository"; return 1; }

  mkdir -p "$target/.cursor/agents"
  local f n
  for f in "$CREW"/agents/*.md; do
    n="$(basename "$f")"
    ln -sfn "$f" "$target/.cursor/agents/$n"
  done
  ok "agents linked into $target/.cursor/agents/"

  # Local-only ignore. Absolute symlinks would break for anyone else who cloned
  # this repo, so never touch its tracked .gitignore.
  # --absolute-git-dir, not --git-dir: the latter returns a path relative to the
  # target, which resolves against *this* script's cwd and writes to the wrong repo.
  local ex; ex="$(git -C "$target" rev-parse --absolute-git-dir)/info/exclude"
  mkdir -p "$(dirname "$ex")"
  if grep -qF '.cursor/agents/crew-' "$ex" 2>/dev/null; then
    ok "already ignored in $ex"
  else
    printf '.cursor/agents/crew-*.md\n' >> "$ex"
    ok "ignored locally in $ex"
  fi
}

doctor() {
  local rc; rc="$(shell_rc)"
  echo "crew doctor"
  echo
  echo "Global (skills):"
  [ -L "$LOCAL_PLUGINS/crew" ] && ok "plugin linked" || warn "plugin not linked — run: ./install.sh"
  if grep -q '# >>> crew >>>' "$rc" 2>/dev/null; then
    ok "shell function in $rc"
  elif grep -qE '^\s*(function\s+)?cursor\s*\(\)' "$rc" 2>/dev/null; then
    ok "$rc defines cursor() (hand-written, not crew-managed)"
  else
    warn "shell function missing — run: ./install.sh shell"
  fi
  command -v cursor-agent >/dev/null && ok "cursor-agent on PATH" || bad "cursor-agent not found"
  echo
  echo "This repo (agents):"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local missing=0 f n
    for f in "$CREW"/agents/*.md; do
      n="$(basename "$f")"
      [ -e "$PWD/.cursor/agents/$n" ] || missing=1
    done
    [ "$missing" -eq 0 ] && ok "all agents linked here" || warn "agents not linked — run: $CREW/install.sh agents"
  else
    warn "not a git repository, so no agents to link"
  fi
  echo
  echo "Models pinned in agent frontmatter:"
  for f in "$CREW"/agents/*.md; do
    printf '    %-20s %s\n' "$(basename "$f" .md)" "$(awk -F': *' '/^model:/{print $2}' "$f")"
  done
  if command -v cursor-agent >/dev/null; then
    local avail; avail="$(cursor-agent --list-models 2>/dev/null | awk '{print $1}')"
    local m
    for f in "$CREW"/agents/*.md; do
      m="$(awk -F': *' '/^model:/{print $2}' "$f")"
      printf '%s\n' "$avail" | grep -qx "$m" || bad "model not available on your account: $m"
    done
  fi
}

case "${1:-}" in
  ""|install)
    echo "crew install"; echo
    link_plugin
    echo
    echo "Two steps left:"
    echo "  1. ./install.sh shell           # so 'cursor' loads the plugin"
    echo "  2. ./install.sh agents <repo>   # per repo you run crew in"
    echo
    echo "Agents must be per-repo: plugin-bundled agents silently ignore 'model'"
    echo "and 'readonly', and ~/.cursor/agents/ does not load despite the docs."
    ;;
  shell)  install_shell ;;
  agents) install_agents "${2:-$PWD}" ;;
  doctor) doctor ;;
  *) echo "usage: ./install.sh [install|shell|agents [dir]|doctor]" >&2; exit 2 ;;
esac
