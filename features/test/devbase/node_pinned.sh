#!/usr/bin/env bash
#
# devbase Feature — a consumer that pins a Node version other than devbase's.
#
# devbase declares node:2 at "lts" in `dependsOn`, which makes it the owner of the Node
# version rather than a repository that pins its own. This scenario pins 22 and asserts
# that devbase's lts wins anyway — not because overriding a pin is desirable, but because
# it is what the CLI does and someone will eventually hit it:
#
#   two instances of one feature with different options are not deduplicated. Both
#   install, the dependency-expanded one runs second, and its `default -> lts/*` alias
#   replaces the pin. Identical options *are* deduplicated, which is why the team
#   convention of pinning lts everywhere costs nothing — see the node_project scenario.
#
# So this file exists to make the loss of the pin visible and deliberate. A repository that
# genuinely needs a different major cannot get it from here; that is a change to devbase's
# `dependsOn`, not something to work around per repository.

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

# Asserted as a negative on purpose. Anchoring on the current lts major would churn this
# test every time lts moves, while "not the pinned 22" is stable and still fails for the
# change that matters: drop node from devbase's dependsOn and this goes green on v22.
check "devbase's lts wins over a repository's own Node pin" bash -lc '
    set -e
    node -v
    ! node -v | grep -q "^v22\."'

# claude-code installs its own Node only when it cannot find one, and that fallback is
# Node 18 from nodesource — EOL. With node in dependsOn it can never run, and this is what
# would catch it starting to: the apt source exists if and only if that installer ran.
check "claude-code added no Node of its own" bash -c \
    '! test -e /etc/apt/sources.list.d/nodesource.list'

# devbase's npm-dependent steps are the reason the dependency exists, so assert they
# completed rather than reporting a missing toolchain.
check "pnpm is present" bash -lc 'command -v pnpm'

reportResults
