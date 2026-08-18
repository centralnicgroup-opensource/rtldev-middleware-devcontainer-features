#!/usr/bin/env bash
#
# Guard the working-tree Feature copy at .devcontainer/local/devbase.
#
# Wired as `initializeCommand` in .devcontainer/local/devcontainer.json, so it runs on the
# *host* before that container is built. It exists because the copy is the one piece of this
# setup that can silently go out of date: `pnpm devbase:local` has to be re-run after every
# edit to features/src/devbase, and nothing used to notice when it was not.
#
# That went from untidy to costly once devbase started declaring node, github-cli and
# claude-code in `dependsOn` and the config stopped listing them. A four-day-old copy has no
# such dependsOn, so nothing supplied them from either side and the container came up with
# no node, npm, pnpm, gh or claude — while zsh and rtk, which the old copy does install,
# were present. It looked like a broken registry rather than a missing `cp`.
#
# The CLI resolves features before initializeCommand runs, so this cannot pre-empt a stale
# resolution — it aborts the build instead, which is the point: a failed build with a one
# line fix beats a container that comes up missing half its toolchain.
#
# Not part of `pnpm lint`: the copy is gitignored and absent in CI, where this must not fail.

set -euo pipefail

cd "$(dirname "$0")/.."

readonly SRC="features/src/devbase"
readonly COPY=".devcontainer/local/devbase"

die() {
    printf '\n  ERROR: %s\n\n' "$1" >&2
    printf '  Run:  pnpm devbase:local\n\n' >&2
    exit 1
}

[ -d "${SRC}" ] || die "${SRC} is missing — is this the right repository?"

if [ ! -d "${COPY}" ]; then
    die "The working-tree config needs ${COPY}, which does not exist."
fi

# Content comparison rather than mtimes: `cp -r` does not preserve them by default, so a
# fresh copy can look older than its source and a stale one can look newer. diff is also
# what makes the failure message actionable — it names the files that drifted.
if ! diff -r "${SRC}" "${COPY}" >/tmp/devbase-local-drift.txt 2>&1; then
    printf '\n  %s is out of date with %s:\n\n' "${COPY}" "${SRC}" >&2
    sed 's/^/    /' /tmp/devbase-local-drift.txt >&2
    die "Refresh it before rebuilding, or the container is built from stale sources."
fi

echo "devbase working-tree copy matches ${SRC}."
