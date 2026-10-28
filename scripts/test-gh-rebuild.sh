#!/usr/bin/env bash
#
# Proves the gh login survives a real container rebuild (RSRMID-3096).
#
# Run by `pnpm features:test:rebuild` and the "rebuild" job in test-features.yml. It needs a
# Docker daemon and builds two containers.
#
# It lives outside features/test/ because `devcontainer features test` builds one container
# per scenario and never rebuilds, and "the volume is reattached to the *next* container" is
# a property that only exists across two builds. The suite can prove the mount is there, is
# writable and that gh is redirected to it; it cannot prove the login is still there after
# the container has been thrown away, which is the whole point of the volume.
#
# The flow, in order, because each step depends on the one before:
#
#   1. Build a scratch workspace consuming the working-tree Feature, and bring it up.
#   2. First create: gh is logged out, and attach must say so.
#   3. Seed a login into the volume (a hosts.yml, not `gh auth login --with-token`, which
#      validates the token against the API and so needs a real credential and a network).
#   4. Rebuild with --remove-existing-container.
#   5. The container is a different one, the volume is the same, the login is still there,
#      and attach no longer warns.
#
# Cleanup removes exactly the two container ids and the one volume name read back from
# `docker inspect`. It never globs over `devbase-gh-*`: on a developer's machine that would
# delete their real logins.
#
# `set -e` is right here, unlike in setup.sh: this is a test, and a step that failed makes
# every later one meaningless.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_DIR="/var/lib/devbase/gh"
SENTINEL="devbase-rebuild-sentinel"

WS="$(mktemp -d)"
LOG="${WS}/cli.log"
# The CLI's build output is long, so it goes to a file and is only shown, tailed, when
# something fails.
declare -a CONTAINERS=()
VOLUME=""

cleanup() {
    local c
    for c in "${CONTAINERS[@]}"; do
        docker rm -f "${c}" >/dev/null 2>&1 || true
    done
    if [ -n "${VOLUME}" ]; then
        docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
    fi
    rm -rf "${WS}"
}
trap cleanup EXIT

pass() { printf 'PASS: %s\n' "$1"; }

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    if [ -s "${LOG}" ]; then
        printf -- '--- last 40 lines of the devcontainer CLI log ---\n' >&2
        tail -40 "${LOG}" >&2
    fi
    exit 1
}

dc() { (cd "${ROOT}" && pnpm exec devcontainer "$@"); }

# up [extra args] — bring the scratch workspace up and print the container id. The CLI
# writes its result as one JSON line on stdout and its progress on stderr; only the first
# is parsed, and the second is kept for a failure.
up() {
    local result
    result="$(dc up --workspace-folder "${WS}" "$@" 2>>"${LOG}")" || fail "devcontainer up failed"
    printf '%s\n' "${result}" | tail -1 | jq -er 'select(.outcome == "success") | .containerId' ||
        fail "devcontainer up did not report success"
}

in_container() { dc exec --workspace-folder "${WS}" "$@"; }

# Logged out on purpose and outside CI: the warning is skipped in CI by design, and a token
# in the environment would count as a login.
attach() {
    in_container env -u CI -u GITHUB_ACTIONS -u GH_TOKEN -u GITHUB_TOKEN \
        zsh /usr/local/bin/devbase-post-attach.sh 2>&1 || true
}

gh_token() {
    in_container env -u GH_TOKEN -u GITHUB_TOKEN gh auth token 2>/dev/null || true
}

volume_of() {
    docker inspect -f "{{range .Mounts}}{{if eq .Destination \"${GH_DIR}\"}}{{.Name}}{{end}}{{end}}" "$1"
}

# --- the scratch workspace ---------------------------------------------------------------
# A real git repository, so the credential helper is configured as it would be in a
# consumer. The Feature is copied under .devcontainer/ because the CLI refuses a local
# Feature path that resolves outside it. The three options switched off only keep the build
# short; ghCredentialHelper stays on, which is what arms the attach warning.
git init -q "${WS}"
mkdir -p "${WS}/.devcontainer"
cp -R "${ROOT}/features/src/devbase" "${WS}/.devcontainer/devbase"
cat >"${WS}/.devcontainer/devcontainer.json" <<'JSON'
{
  "image": "mcr.microsoft.com/devcontainers/base:2-ubuntu-24.04",
  "features": {
    "./devbase": {
      "installRtk": false,
      "globalPackages": "",
      "installProjectDependencies": false
    }
  }
}
JSON

echo "Bringing the container up (build output in ${LOG})"
FIRST="$(up)"
CONTAINERS+=("${FIRST}")
[ -n "${FIRST}" ] || fail "no container id from the first devcontainer up"
pass "first container is up (${FIRST:0:12})"

# --- first create ------------------------------------------------------------------------
if attach | grep -qF "gh auth login"; then
    pass "first create: a logged-out gh is warned about on attach"
else
    fail "first create: attach did not tell the user to run gh auth login"
fi

# --- seed a login ------------------------------------------------------------------------
in_container sh -c "printf 'github.com:\n    oauth_token: ${SENTINEL}\n    user: devbase-test\n    git_protocol: https\n' >\"\${GH_CONFIG_DIR}/hosts.yml\"" ||
    fail "could not write hosts.yml into GH_CONFIG_DIR (is the volume writable by the remote user?)"
if [ "$(gh_token)" = "${SENTINEL}" ]; then
    pass "a seeded hosts.yml is read by gh auth token"
else
    fail "gh auth token did not return the seeded token — the test's hosts.yml format is not accepted, so the rebuild step would prove nothing"
fi

# --- record the volume -------------------------------------------------------------------
VOLUME="$(volume_of "${FIRST}")"
[ -n "${VOLUME}" ] || fail "the container has no mount at ${GH_DIR} — the manifest's volume was not applied"
pass "the gh config directory is a volume (${VOLUME})"

# --- rebuild -----------------------------------------------------------------------------
echo "Rebuilding the container"
SECOND="$(up --remove-existing-container)"
CONTAINERS+=("${SECOND}")
[ -n "${SECOND}" ] || fail "no container id from the rebuild"
if [ "${SECOND}" != "${FIRST}" ]; then
    pass "the rebuild produced a different container"
else
    fail "the rebuild reused the first container, so nothing was tested"
fi

if [ "$(volume_of "${SECOND}")" = "${VOLUME}" ]; then
    pass "the same volume is attached after the rebuild (devcontainerId is stable)"
else
    fail "the rebuilt container has a different volume — the login cannot survive"
fi

# --- after the rebuild -------------------------------------------------------------------
if [ "$(gh_token)" = "${SENTINEL}" ]; then
    pass "the gh login survived the rebuild"
else
    fail "gh auth token no longer returns the seeded token after the rebuild"
fi

if attach | grep -qF "gh auth login"; then
    fail "attach still warns about gh login after the rebuild"
else
    pass "attach is quiet about gh login after the rebuild"
fi

echo "All gh rebuild checks passed."
