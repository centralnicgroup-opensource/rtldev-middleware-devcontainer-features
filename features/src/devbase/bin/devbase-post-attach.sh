#!/usr/bin/env zsh
# shellcheck shell=bash
#
# devbase Feature — postAttachCommand.
#
# Runs on every VS Code attach, as the remote user, with cwd set to the workspace
# folder. Three jobs:
#
#   1. If the workspace root has an env.sh, add a one-time source line to
#      ~/.zshenv so every new integrated terminal inherits the workspace
#      variables without a manual `source env.sh`.
#   2. Print the toolchain banner, so the active versions are visible on attach.
#   3. Warn when gh holds no login (ghCredentialHelper on), since git over HTTPS then
#      fails until `gh auth login` is run.
#
# Unlike the per-repository post-attach.sh scripts this replaces, the workspace
# path is discovered rather than hardcoded — that hardcoded line was the only
# reason those files could not be shared.

set -euo pipefail

readonly SHARE_DIR="/usr/local/share/devbase"
readonly MARKER="# workspace-env (auto-loaded by the devbase devcontainer Feature)"

# shellcheck source=/dev/null
[ -f "${SHARE_DIR}/config.env" ] && . "${SHARE_DIR}/config.env"

WORKSPACE="${DEVBASE_WORKSPACE:-}"
if [ -z "${WORKSPACE}" ]; then
    WORKSPACE="$(git rev-parse --show-toplevel 2>/dev/null)" || WORKSPACE="${PWD}"
fi

if [ "${DEVBASE_AUTOLOAD_ENV_SCRIPT:-true}" = "true" ] && [ -f "${WORKSPACE}/env.sh" ]; then
    if ! grep -qF "${MARKER}" "${HOME}/.zshenv" 2>/dev/null; then
        {
            printf '\n%s\n' "${MARKER}"
            printf '. "%s/env.sh"\n' "${WORKSPACE}"
        } >>"${HOME}/.zshenv"
    fi
fi

# Invoked through zsh rather than executed, and tested with -f rather than -x:
# the workspace is a bind mount from the host, so the executable bit can be
# absent, and a lost +x must not silently disable the banner.
#
# `|| true` on top of the banner's own `exit 0`: under `set -e`, a banner that
# somehow failed must never break the attach.
if [ "${DEVBASE_ENV_INFO_BANNER:-true}" = "true" ] && [ -f "${SHARE_DIR}/env-info.sh" ]; then
    DEVBASE_WORKSPACE="${WORKSPACE}" zsh "${SHARE_DIR}/env-info.sh" || true
fi

# Last, so the warning is the final thing on screen rather than scrolled off by the banner,
# and independent of envInfoBanner: switching the banner off must not silence it. Gated on
# the credential helper, because that is what makes a logged-out gh break git. setup.sh only
# defines functions (and sources log.sh), so sourcing it here runs nothing. `|| true` and
# the -f guards: a missing library or a failing check must never break an attach.
if [ "${DEVBASE_GH_CREDENTIAL_HELPER:-true}" = "true" ] &&
    [ -f "${SHARE_DIR}/log.sh" ] && [ -f "${SHARE_DIR}/setup.sh" ]; then
    # shellcheck source=../lib/log.sh
    . "${SHARE_DIR}/log.sh"
    # shellcheck source=../lib/setup.sh
    . "${SHARE_DIR}/setup.sh"
    devbase_check_gh_login || true
fi
