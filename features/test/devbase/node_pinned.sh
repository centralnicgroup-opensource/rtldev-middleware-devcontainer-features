#!/usr/bin/env bash
#
# devbase Feature — a consumer that pins a specific Node version.
#
# Two things this guards, both consequences of devbase depending on claude-code:
#
#   1. claude-code installs its own Node when it cannot find one, and that fallback is
#      Node 18 from nodesource — EOL. Its `installsAfter: node` is what suppresses the
#      fallback, so a repository that lists node must end up with *its* Node and no
#      nodesource apt source alongside.
#   2. devbase must not disturb the pin. node was tried in devbase's `dependsOn` at "lts"
#      and had to be reverted: the CLI installs both instances rather than deduplicating
#      them, devbase's ran second, and its `default -> lts/*` overwrote a pinned 22 with
#      24. Anything that puts node back into `dependsOn` fails here first.

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

# Anchored on "v22." so a 22.x patch bump does not churn the test, but a slide onto lts
# or onto claude-code's EOL 18 fallback fails it.
check "the consumer's Node pin is left alone" bash -lc 'node -v | grep -q "^v22\."'

# The version check above would catch the nodesource fallback only by luck — it installs
# to /usr/bin while the node feature's nvm build shadows it on PATH. Assert the apt source
# directly, which is present if and only if that installer ran.
check "claude-code added no second Node from nodesource" bash -c \
    '! test -e /etc/apt/sources.list.d/nodesource.list'

# The negative half of the EOL-fallback warning; the default test asserts it fires. A
# warning that cannot stay quiet would nag every correctly-configured repository into
# ignoring it, which costs more than not having it.
check "no EOL warning when the repository lists its own Node" bash -c '
    set -e
    . /usr/local/share/devbase/setup.sh
    test -z "$(devbase_warn_on_fallback_node 2>&1)"'

# devbase's npm-dependent steps are the reason the Node ordering matters at all, so assert
# they completed rather than reporting a missing toolchain.
check "pnpm installed against the pinned Node" bash -lc 'command -v pnpm'

reportResults
