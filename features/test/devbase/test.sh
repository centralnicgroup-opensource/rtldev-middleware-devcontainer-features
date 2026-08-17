#!/usr/bin/env bash
#
# devbase Feature — default-options test.
#
# Run with:  devcontainer features test --features devbase --base-image \
#              mcr.microsoft.com/devcontainers/base:2-ubuntu-24.04 .
#
# `set -e` is deliberate: dev-container-features-test-lib's `check` reports a
# failure and the script should stop at the first broken assertion.

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

# --- what install.sh must have put in place -----------------------------------
check "shared library installed" test -f /usr/local/share/devbase/log.sh
check "setup library installed" test -f /usr/local/share/devbase/setup.sh
check "env-info library installed" test -f /usr/local/share/devbase/env-info.sh
check "recorded options installed" test -f /usr/local/share/devbase/config.env

check "post-create entrypoint executable" test -x /usr/local/bin/devbase-post-create.sh
check "post-attach entrypoint executable" test -x /usr/local/bin/devbase-post-attach.sh
check "env-info entrypoint executable" test -x /usr/local/bin/devbase-env-info

# --- common packages (default: true) ------------------------------------------
check "zsh present" zsh --version
check "jq present" jq --version
check "shellcheck present" shellcheck --version
check "curl present" curl --version

# --- user configuration -------------------------------------------------------
check "zshrc installed" test -f "${HOME}/.zshrc"
check "czrc installed" test -f "${HOME}/.czrc"
check "czrc names the conventional-changelog adapter" \
    grep -q "cz-conventional-changelog" "${HOME}/.czrc"
check "zshrc sources the local override" grep -q ".zshrc.local" "${HOME}/.zshrc"
check "login shell is zsh" bash -c 'getent passwd "$(id -un)" | grep -q zsh'

# --- recorded option values ---------------------------------------------------
check "defaults recorded" grep -q 'DEVBASE_INSTALL_PNPM="true"' /usr/local/share/devbase/config.env
check "global packages recorded" \
    grep -q 'DEVBASE_GLOBAL_PACKAGES="commitizen@latest,cz-conventional-changelog@latest"' \
    /usr/local/share/devbase/config.env

# --- timezone (default: Europe/Berlin) ----------------------------------------
check "timezone applied" grep -q "Europe/Berlin" /etc/timezone

# --- RTK (default: installed) -------------------------------------------------
# The binary has to be on PATH for the PreToolUse hook in the bind-mounted
# ~/.claude/settings.json to work; without it that hook exits 127 on every Bash call.
check "rtk installed" test -x /usr/local/bin/rtk
check "rtk runs" rtk --version
check "rtk reports the pinned version" bash -c 'rtk --version | grep -q "0.45.0"'
check "rtk version recorded" \
    grep -q 'DEVBASE_RTK_VERSION="0.45.0"' /usr/local/share/devbase/config.env
# rtk init -g must never have run: it would rewrite the bind-mounted ~/.claude, which is
# shared with the host and already carries the hook.
check "claude settings untouched" bash -c '! test -e "${HOME}/.claude/settings.json"'

# --- the library is loadable and its helpers exist ----------------------------
check "log helpers load" bash -c '. /usr/local/share/devbase/log.sh; \
    command_exists git && log_success "loaded" >/dev/null'
check "setup helpers load" bash -c '. /usr/local/share/devbase/setup.sh; \
    declare -f devbase_setup_pnpm >/dev/null'

# execute_with_indent's exit status is what every caller branches on, so a
# regression there reports SUCCESS for a step that did nothing. It once read $?
# after an `if` with no else branch, which is always 0.
check "execute_with_indent succeeds on a passing command" bash -c \
    '. /usr/local/share/devbase/log.sh; execute_with_indent "true" "ok" >/dev/null'
check "execute_with_indent propagates a failure" bash -c \
    '. /usr/local/share/devbase/log.sh; \
     execute_with_indent "exit 3" "fails" >/dev/null 2>&1; [ "$?" -eq 3 ]'
check "execute_with_indent reports the real exit code" bash -c \
    '. /usr/local/share/devbase/log.sh; \
     execute_with_indent "exit 3" "fails" 2>&1 | grep -q "exit code 3"'

# --- the banner runs, exits 0, and needs no configuration --------------------
# The no-config case is the one every repository hits first, so it is the case
# most worth asserting: auto-detection must produce a banner, not an error.
check "banner runs without a config file" bash -c 'cd /tmp && devbase-env-info'
check "banner prints the container group" bash -c 'cd /tmp && devbase-env-info | grep -q "Container"'
check "banner reports the OS" bash -c 'cd /tmp && devbase-env-info | grep -qi "ubuntu"'

reportResults
