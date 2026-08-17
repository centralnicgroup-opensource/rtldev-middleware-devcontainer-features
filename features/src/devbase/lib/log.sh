#!/usr/bin/env bash
# shellcheck shell=bash
#
# devbase — logging and command-execution helpers, sourced by the lifecycle
# scripts. This file is the deduplicated form of the log_*/execute_with_indent
# block that had been copy-pasted (and drifted) into every repository's own
# post-create.sh.
#
# Sourced, never executed: it defines functions and sets colour variables, and
# deliberately sets no shell options — the caller owns those.

# Colours, suppressed for a non-terminal or NO_COLOR (any value, per no-color.org)
# so a CI log does not fill up with escape sequences.
if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-dumb}" = "dumb" ] || [ ! -t 1 ]; then
    COLOR_RESET=''
    COLOR_INFO=''
    COLOR_SUCCESS=''
    COLOR_ERROR=''
    COLOR_DETAIL=''
else
    COLOR_RESET=$'\033[0m'
    COLOR_INFO=$'\033[1;36m'    # bright cyan  - section headings
    COLOR_SUCCESS=$'\033[1;32m' # bright green - completed step
    COLOR_ERROR=$'\033[1;31m'   # bright red   - failed step
    COLOR_DETAIL=$'\033[0;37m'  # light gray   - sub-step detail
fi

log_info() {
    echo ""
    echo "${COLOR_INFO}=> [INFO] $*${COLOR_RESET}"
}

log_error() {
    echo "${COLOR_ERROR}=> [ERROR]${COLOR_RESET} $*" >&2
}

log_success() {
    echo "${COLOR_SUCCESS}=> [SUCCESS]${COLOR_RESET} $*"
}

log_detail() {
    echo "${COLOR_DETAIL}   $*${COLOR_RESET}"
}

# command_exists <name> — true when name is callable.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# execute_with_indent <command-string> <description> [strip-formatting]
#
# Runs the command, captures stdout+stderr, and reproduces it indented under the
# description so a long install log stays readable. Returns the command's own
# exit code, so a caller under `set -e` still stops where it should.
#
# strip-formatting=true removes ANSI sequences from the captured output, for
# tools that colourise unconditionally even when writing to a pipe.
execute_with_indent() {
    local cmd="$1"
    local description="$2"
    local strip_formatting="${3:-false}"
    local output
    local exit_code=0

    log_detail "Executing: ${description}"

    # Capture the status on the assignment itself. Reading $? after an `if`
    # whose condition was false would read the `if` statement's own status —
    # 0, because it has no else branch — and report a failure as a success.
    output=$(eval "${cmd}" 2>&1) || exit_code=$?

    if [ "${exit_code}" -eq 0 ]; then
        [ -n "${output}" ] && _devbase_indent "${output}" "${strip_formatting}"
        return 0
    fi

    log_error "Command failed with exit code ${exit_code}"
    [ -n "${output}" ] && _devbase_indent "${output}" "${strip_formatting}" >&2
    return "${exit_code}"
}

# _devbase_indent <text> <strip-formatting> — internal helper for the above.
_devbase_indent() {
    local text="$1"
    local strip="$2"
    if [ "${strip}" = "true" ]; then
        printf '%s\n' "${text}" |
            sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b\[[0-9]*[A-Za-z]//g' -e 's/^/     /'
    else
        printf '%s\n' "${text}" | sed 's/^/     /'
    fi
}
