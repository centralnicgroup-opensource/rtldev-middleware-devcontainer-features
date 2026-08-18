#!/usr/bin/env zsh
# shellcheck shell=bash
#
# devbase Feature — postCreateCommand.
#
# Runs once, as the remote user, on first container create, with the workspace
# mounted and the cwd set to the workspace folder. Everything that needs to read
# the repository lives here rather than in install.sh.
#
# Ordering: a Feature's lifecycle hooks run before the consuming
# devcontainer.json's own hooks, so a repository's postCreateCommand can rely on
# pnpm, the global packages and its dependencies already being in place. Put
# repository-specific setup there — never fork this file.

set -euo pipefail

readonly SCRIPT_NAME="devbase-post-create"
readonly SHARE_DIR="/usr/local/share/devbase"

# shellcheck source=../lib/log.sh
. "${SHARE_DIR}/log.sh"
# shellcheck source=../lib/setup.sh
. "${SHARE_DIR}/setup.sh"
# Option values as recorded at image build time.
# shellcheck source=/dev/null
. "${SHARE_DIR}/config.env"

main() {
    echo "=== ${SCRIPT_NAME} ==="
    echo "User:        $(whoami)"
    echo "Workspace:   $(pwd)"
    echo "Environment: ${GITHUB_ACTIONS:-${CI:-development}}"

    # Return to the starting directory whatever happens, so a step that cd's
    # cannot leave a later one somewhere unexpected. Early expansion intended.
    local original_dir
    original_dir="$(pwd)"
    # shellcheck disable=SC2064
    trap "cd '${original_dir}'" EXIT

    # Ungated and first: it diagnoses the runtime every step below is built on, and a
    # repository that has opted out of the pnpm step still wants to know its Node is dead.
    devbase_warn_on_fallback_node

    if [ "${DEVBASE_INSTALL_PNPM:-true}" = "true" ]; then
        devbase_setup_npm_floor
        devbase_setup_pnpm
    fi

    # Before the global packages: sourcing .zshrc there triggers the plugin's
    # widget setup, so the plugin needs to exist first.
    if [ "${DEVBASE_ZSH_AUTOSUGGESTIONS:-true}" = "true" ]; then
        devbase_setup_zsh_autosuggestions
    fi

    devbase_setup_global_packages "${DEVBASE_GLOBAL_PACKAGES:-}"

    if [ "${DEVBASE_GH_CREDENTIAL_HELPER:-true}" = "true" ]; then
        devbase_setup_gh_credential_helper
    fi

    if [ "${DEVBASE_INSTALL_PROJECT_DEPENDENCIES:-true}" = "true" ]; then
        devbase_setup_project_dependencies
        devbase_setup_env_file
    fi

    if [ "${DEVBASE_HISTORY_PERSISTENCE:-true}" = "true" ]; then
        devbase_setup_history_persistence
    fi

    log_info "${SCRIPT_NAME} finished"
}

main "$@"
