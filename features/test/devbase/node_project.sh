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

# --- the pnpm the workspace asked for -----------------------------------------
# Last in the file on purpose: these checks replace the container's global pnpm and npm,
# so anything that asserts the versions the image shipped has to run above them.
#
# Asserted on `pnpm --version`, never on a log line. The entire point of the step is which
# binary answers on PATH afterwards, and a step that logs the right version while leaving
# the wrong pnpm installed is the exact failure it exists to prevent — the container used
# to run whatever pnpm was newest on build day while CI honoured the declaration.
check "pnpm is aligned to the version packageManager declares" bash -c '
    set -e
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    rm -rf /tmp/declared && mkdir -p /tmp/declared && cd /tmp/declared
    # A real release, and deliberately older than anything the Node feature installs as
    # latest — so a step that quietly does nothing cannot pass this. The integrity suffix
    # rides along because npm must never be handed one.
    printf "{\"name\":\"probe\",\"private\":true,\"packageManager\":\"pnpm@10.18.0+sha512-unverified\"}\n" > package.json
    . /usr/local/share/devbase/setup.sh
    devbase_setup_pnpm > /tmp/declared.log 2>&1
    hash -r
    # Read from / and never from the workspace. Inside it, pnpm sees the same field and
    # fetches and re-execs the declared version itself, so `pnpm --version` there answers
    # 10.18.0 whether or not anything was installed — an assertion that could not fail.
    installed="$(cd / && pnpm --version)"
    test "${installed}" = "10.18.0" || { cat /tmp/declared.log; echo "installed ${installed}"; exit 1; }'

# The other half: a workspace that declares nothing devbase can act on keeps the pnpm it
# already has. Reinstalling `latest` over it would put the container back on whichever
# version happens to be newest today, which is the accident this step removes.
check "a workspace with no usable declaration keeps its pnpm" bash -c '
    set -e
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    . /usr/local/share/devbase/setup.sh
    # Both readings are taken from /, for the reason above — and because pnpm refuses to
    # run at all in a workspace whose packageManager names another tool, which is one of
    # the manifests below.
    before="$(cd / && pnpm --version)"
    rm -rf /tmp/unusable && mkdir -p /tmp/unusable && cd /tmp/unusable
    for manifest in "{\"packageManager\":\"yarn@4.9.2\"}" \
        "{\"packageManager\":\"pnpm@^10.18.0\"}" \
        "{\"devEngines\":{\"packageManager\":{\"name\":\"yarn\",\"version\":\"^4.9.2\"}}}" \
        "{\"name\":\"probe\"}"; do
        printf "%s\n" "${manifest}" > package.json
        devbase_setup_pnpm > /tmp/unusable.log 2>&1
        hash -r
        installed="$(cd / && pnpm --version)"
        test "${installed}" = "${before}" || {
            cat /tmp/unusable.log
            echo "${manifest} moved pnpm from ${before} to ${installed}"
            exit 1
        }
    done'

# The field the toolchain policy actually declares, asserted on the binary rather than on
# the read. Both checks below run with the container sitting on 10.18.0 from the first
# check in this section, so a step that quietly does nothing cannot pass either.
check "pnpm is aligned to the range devEngines.packageManager declares" bash -c '
    set -e
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    rm -rf /tmp/deveng && mkdir -p /tmp/deveng && cd /tmp/deveng
    printf "{\"name\":\"probe\",\"private\":true,\"devEngines\":{\"packageManager\":{\"name\":\"pnpm\",\"version\":\"^11.0.0\",\"onFail\":\"error\"}}}\n" > package.json
    . /usr/local/share/devbase/setup.sh
    devbase_setup_pnpm > /tmp/deveng.log 2>&1
    hash -r
    # From /, never the workspace: pnpm reads this same field and re-execs the version it
    # names, so a reading taken here would report the range as satisfied whether or not
    # anything was installed.
    installed="$(cd / && pnpm --version)"
    test "${installed%%.*}" = "11" || { cat /tmp/deveng.log; echo "installed ${installed}"; exit 1; }'

# The range has to steer the resolution, not merely permit it. `^11.0.0` cannot show that
# on its own — pnpm latest is inside it, so a step that ignored the field and installed
# latest would pass the check above. A 10.34 range cannot be reached by latest, so this is
# the one that separates "read the declaration" from "installed whatever was newest".
check "the resolved pnpm comes from the declared range, not from latest" bash -c '
    set -e
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    rm -rf /tmp/devengold && mkdir -p /tmp/devengold && cd /tmp/devengold
    printf "{\"name\":\"probe\",\"private\":true,\"devEngines\":{\"packageManager\":{\"name\":\"pnpm\",\"version\":\"~10.34.0\"}}}\n" > package.json
    . /usr/local/share/devbase/setup.sh
    devbase_setup_pnpm > /tmp/devengold.log 2>&1
    hash -r
    installed="$(cd / && pnpm --version)"
    case "${installed}" in
        10.34.*) ;;
        *) cat /tmp/devengold.log; echo "installed ${installed}"; exit 1 ;;
    esac
    # And a second create with the same declaration leaves it alone: the version is inside
    # the range, so there is nothing to align and no reason to reach the network again.
    devbase_setup_pnpm > /tmp/devengold2.log 2>&1
    hash -r
    again="$(cd / && pnpm --version)"
    test "${again}" = "${installed}" || {
        cat /tmp/devengold2.log
        echo "second run moved pnpm from ${installed} to ${again}"
        exit 1
    }'

# --- the npm floor ------------------------------------------------------------
# The floor is the Feature's other npm invocation, and it had no test at all until now.
# Both checks need npm off the version the image shipped, so the move is part of the first
# and the second inherits it — which is why the second re-asserts that precondition rather
# than assuming the order.
check "an engines.npm that is not a >= floor leaves npm alone" bash -c '
    set -e
    . /usr/local/share/devbase/setup.sh
    rm -rf /tmp/floor && mkdir -p /tmp/floor && cd /tmp/floor
    npm i --silent -g npm@11 >/dev/null 2>&1
    hash -r
    test "$(npm --version | cut -d. -f1)" = "11"
    # `^12.0.0` is the form that disables this step. It is not a floor devbase can read,
    # so npm has to stay where it is rather than be guessed at.
    printf "{\"engines\":{\"npm\":\"^12.0.0\"}}\n" > package.json
    devbase_setup_npm_floor > /tmp/floor-skip.log 2>&1
    hash -r
    test "$(npm --version | cut -d. -f1)" = "11" || { cat /tmp/floor-skip.log; exit 1; }'

check "npm is raised to the major a >= engines.npm floor names" bash -c '
    set -e
    . /usr/local/share/devbase/setup.sh
    cd /tmp/floor
    test "$(npm --version | cut -d. -f1)" = "11"
    printf "{\"engines\":{\"npm\":\">=12.0.0\"}}\n" > package.json
    devbase_setup_npm_floor > /tmp/floor-raise.log 2>&1
    hash -r
    test "$(npm --version | cut -d. -f1)" = "12" || { cat /tmp/floor-raise.log; exit 1; }'

reportResults
