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
