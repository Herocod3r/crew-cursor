#!/usr/bin/env bash
# crew installer.
#
# Cursor's documented install paths do not all work, so crew needs two steps:
#
#   skills   loaded via --plugin-dir, wired up by a shell function
#   agents   symlinked into each repo's .cursor/agents/, because plugin-bundled
#            agents silently ignore `model` and `readonly`
#
# Once the shell function is in place the per-repo step is automatic: it runs on
# every launch, before the session starts. It has to happen there rather than in
# /crew, because subagents are registered once at startup.
#
# Usage:
#   ./install.sh            link the plugin and report what is left to do
#   ./install.sh shell      append the cursor() function to your shell rc
#   ./install.sh agents [d] symlink crew's agents into repo d (default: cwd)
#   ./install.sh ensure [d] same, but quiet and never fails — for the wrapper
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
  # Link crew's agents into this repo before the session starts. Subagents are
  # registered once at startup, so /crew cannot do this for its own run — a
  # symlink made mid-session stays invisible until the next one. Never allowed
  # to fail the launch.
  if [ -x "$HOME/.cursor/plugins/local/crew/install.sh" ]; then
    "$HOME/.cursor/plugins/local/crew/install.sh" ensure || true
  fi
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

install_user_agents() {
  # Documented as loading for all projects. It does not load in the CLI at all, and
  # in the IDE it loads with a reduced schema like a plugin: `readonly: true` was
  # dropped and the agent wrote a file, where the same file at project level was
  # refused. So this buys discoverability in the IDE and nothing more — it does not
  # replace the per-repo link, which is the only source that honours `model`.
  mkdir -p "$HOME/.cursor/agents"
  local f
  for f in "$CREW"/agents/*.md; do ln -sfn "$f" "$HOME/.cursor/agents/$(basename "$f")"; done
  ok "agents linked into ~/.cursor/agents/ (works in the IDE only, if at all)"
}

link_repo_agents() {
  # Shared by `agents` and `ensure`. Symlink, never copy: a copy keeps working but
  # drifts from the plugin, so the model a run pins silently stops matching the
  # plugin's. Echoes one line per action taken and nothing when already correct.
  local target="$1"
  mkdir -p "$target/.cursor/agents" || return 1
  local f n p
  for f in "$CREW"/agents/*.md; do
    n="$(basename "$f")"; p="$target/.cursor/agents/$n"
    if [ -e "$p" ] && [ ! -h "$p" ]; then
      # A real file, not a link. Replace it, but never silently.
      ln -sfn "$f" "$p" && printf 'replaced a copy with a symlink: %s\n' "$n"
    elif [ ! -h "$p" ] || [ "$(readlink "$p")" != "$f" ]; then
      # Missing, dangling, or pointing at an older plugin location.
      ln -sfn "$f" "$p" && printf 'linked %s\n' "$n"
    fi
  done

  # Local-only ignore. These are absolute symlinks into one machine's plugin dir,
  # so they must never reach anyone else who clones the repo — but the .gitignore
  # is tracked and is not ours to edit. .git/info/exclude is per-clone and private.
  # --absolute-git-dir, not --git-dir: the latter is relative to the target and
  # would resolve against this script's cwd, writing to the wrong repo.
  local ex; ex="$(git -C "$target" rev-parse --absolute-git-dir)/info/exclude"
  mkdir -p "$(dirname "$ex")"
  grep -qF '.cursor/agents/crew-' "$ex" 2>/dev/null ||
    { printf '.cursor/agents/crew-*.md\n' >> "$ex"; printf 'ignored locally in %s\n' "$ex"; }
}

install_agents() {
  local target="${1:-$PWD}"
  target="$(cd "$target" && pwd)"
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    bad "$target is not a git repository"; return 1; }
  local out; out="$(link_repo_agents "$target")"
  [ -n "$out" ] && printf '%s\n' "$out" | while read -r l; do ok "$l"; done
  ok "agents linked into $target/.cursor/agents/"
}

ensure_agents() {
  # Called from the cursor() wrapper on every launch, before the session starts.
  # Agents are registered once at session start, so linking them from inside /crew
  # is invisible for that entire run. Must never fail a launch and must stay quiet
  # once the repo is set up.
  local target="${1:-$PWD}"
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  target="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || return 0
  local out; out="$(link_repo_agents "$target" 2>/dev/null)" || return 0
  [ -n "$out" ] && printf '%s\n' "$out" | while IFS= read -r l; do
    printf 'crew: %s\n' "$l" >&2
  done
  return 0
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
  echo "User-level agents (~/.cursor/agents/):"
  if [ -L "$HOME/.cursor/agents/crew-critic.md" ]; then
    ok "linked"
    if command -v cursor-agent >/dev/null; then
      if cursor-agent --help >/dev/null 2>&1; then
        warn "not loaded by the CLI at all; in the IDE it loads but drops model/readonly"
        warn "either way the per-repo link is what pins the models"
      fi
    fi
  else
    warn "not linked — run: ./install.sh"
  fi
  echo
  echo "This repo (agents):"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local missing=0 f n
    for f in "$CREW"/agents/*.md; do
      n="$(basename "$f")"
      [ -e "$PWD/.cursor/agents/$n" ] || missing=1
    done
    if [ "$missing" -eq 0 ]; then
      ok "all agents linked here"
      [ "$(find "$PWD/.cursor/agents" -maxdepth 1 -name 'crew-*.md' -type f 2>/dev/null | wc -l)" -eq 0 ] ||
        warn "some are copies, not symlinks — they will drift; rerun to replace them"
      git check-ignore -q .cursor/agents/crew-critic.md 2>/dev/null &&
        ok "ignored, so they cannot reach another clone" ||
        warn "not ignored — rerun to add .git/info/exclude"
    else
      warn "agents not linked — launch via the cursor() wrapper, or run: $CREW/install.sh agents"
    fi
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
    install_user_agents
    echo
    echo "One step left:"
    echo "  ./install.sh shell    # so 'cursor' loads the plugin and links agents"
    echo
    echo "That covers every repo. The wrapper links agents before each launch, so"
    echo "there is nothing to run per repo."
    echo
    echo "Agents must be per-repo: plugin-bundled agents silently ignore 'model'"
    echo "and 'readonly', and ~/.cursor/agents/ does not load in the CLI despite"
    echo "the docs. They are symlinked, never copied, and ignored via"
    echo ".git/info/exclude so they never reach anyone else's clone."
    ;;
  shell)  install_shell ;;
  agents) install_agents "${2:-$PWD}" ;;
  ensure) ensure_agents "${2:-$PWD}" ;;
  doctor) doctor ;;
  *) echo "usage: ./install.sh [install|shell|agents [dir]|ensure [dir]|doctor]" >&2; exit 2 ;;
esac
