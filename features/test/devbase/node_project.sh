#!/usr/bin/env bash
#
# devbase Feature — alongside the Node feature.
#
# This is the mcp-dis shape, and the scenario that exercises the parts of the
# Feature that need a runtime present: installsAfter ordering (node must exist by
# the time post-create runs), the pnpm install, and the banner's Node group.

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "node available" node --version
check "npm available" npm --version

# installsAfter puts the Node feature first, which is what makes post-create's
# pnpm step viable at all — without it the ordering is unspecified.
check "post-create installs pnpm" bash -c 'cd /tmp && zsh /usr/local/bin/devbase-post-create.sh'
check "pnpm on PATH afterwards" bash -c \
    'export PNPM_HOME="$HOME/.local/share/pnpm"; export PATH="$PNPM_HOME:$PATH"; pnpm --version'

# The per-scenario timezone override must win over the Feature default.
check "timezone override applied" grep -q "Europe/London" /etc/timezone

# The banner must pick up the Node group by auto-detection, with no config file.
check "banner shows the Node group" bash -c 'cd /tmp && devbase-env-info | grep -q "Node toolchain"'
check "banner reports a Node version" bash -c \
    'cd /tmp && devbase-env-info | grep -A2 "Node toolchain" | grep -qE "[0-9]+\.[0-9]+"'

# --- project dependencies, against a real manifest ----------------------------
# The branch of devbase_setup_project_dependencies that needs a runtime present, and the
# reason this scenario is its right home: post-create above has just installed pnpm, so a
# package.json can actually be installed here rather than only reported as unservable.
# Until now nothing in the suite ever entered this branch — every scenario ran post-create
# from /tmp, which has no manifest.
check "installs Node dependencies from a real package.json" bash -c '
    set -e
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    rm -rf /tmp/proj && mkdir -p /tmp/proj && cd /tmp/proj
    printf "{\"name\":\"probe\",\"version\":\"1.0.0\",\"private\":true}\n" > package.json
    . /usr/local/share/devbase/setup.sh
    devbase_setup_project_dependencies > /tmp/proj.log 2>&1
    grep -q "Node dependencies installed" /tmp/proj.log
    test -d node_modules'

# A stale lockfile must not stop the container coming up: the frozen install fails, the
# refreshed one runs, and the resulting diff is left visible instead. Asserted because the
# recovery is silent by design — without a test, a regression here looks like a working
# install right up until CI rejects the lockfile nobody committed.
check "falls back to a refreshed lockfile when the frozen install fails" bash -c '
    set -e
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    rm -rf /tmp/stale && mkdir -p /tmp/stale && cd /tmp/stale
    printf "{\"name\":\"probe\",\"version\":\"1.0.0\",\"private\":true}\n" > package.json
    # A lockfile declaring a dependency package.json does not have is rejected by
    # --frozen-lockfile, and re-resolving it needs no network since nothing is required.
    printf "lockfileVersion: \"9.0\"\n\nimporters:\n\n  .:\n    dependencies:\n      is-odd:\n        specifier: 3.0.1\n        version: 3.0.1\n" > pnpm-lock.yaml
    . /usr/local/share/devbase/setup.sh
    devbase_setup_project_dependencies > /tmp/stale.log 2>&1
    grep -q "Installed without the frozen lockfile" /tmp/stale.log'

# A workspace-supplied env-info.conf must override the defaults, including the
# title — the mechanism every migrated repository relies on.
check "banner honours env-info.conf" bash -c '
  set -e
  mkdir -p /tmp/ws/.devcontainer && cd /tmp/ws
  git init -q . 2>/dev/null || true
  printf "TITLE=\"CUSTOM-TITLE - development environment\"\nSHOW_NODE=false\n" \
    > .devcontainer/env-info.conf
  devbase-env-info | grep -q "CUSTOM-TITLE"
  ! devbase-env-info | grep -q "Node toolchain"
'

reportResults
