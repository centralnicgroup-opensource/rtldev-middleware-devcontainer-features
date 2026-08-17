#!/usr/bin/env zsh
# shellcheck shell=bash
#
# devbase — the on-attach toolchain banner, generalised from the two hand-rolled
# copies (php-sdk's PHP/Node one and mcp-dis's Node/MCP one) plus the third
# reinvention inside whmcs-src's post-create.sh (get_php_versions, get_os_info,
# get_system_info). It answers "which PHP/Node/Go am I actually on?" at a glance.
#
# Per-repository content comes from .devcontainer/env-info.conf in the workspace;
# with no such file every language group auto-detects, so a repository that wants
# the default banner configures nothing. See docs/devcontainer-feature.md.
#
# Pure output: no installs, no network, no writes, no secrets. Safe to run by
# hand as `devbase-env-info`.
#
# Deliberately NOT `set -e`: probing for a tool that is absent is the normal case
# here, not an error. The caller runs under `set -euo pipefail`, so this script
# must exit 0 however many probes come up empty.
#
# Supported shells are zsh (the container default) and bash. `pipefail` is kept
# even though nothing inspects a pipeline's status, because it makes a shell that
# cannot run this script correctly — dash, which also lacks the $'...' quoting
# used for the colours — fail loudly on line 1 rather than printing rows full of
# literal escape sequences.
set -uo pipefail

readonly LABEL_WIDTH=18
readonly MISSING="(not installed)"      # tool absent
readonly NO_VERSION="(version unknown)" # tool present, version unreadable
readonly UNKNOWN="(unknown)"            # a fact that is not an installable thing

# --- workspace ---------------------------------------------------------------
# Lifecycle commands run with the workspace folder as cwd, so PWD is normally
# right; the git fallback covers running this by hand from a subdirectory.
WORKSPACE="${DEVBASE_WORKSPACE:-}"
if [ -z "${WORKSPACE}" ]; then
    WORKSPACE="$(git rev-parse --show-toplevel 2>/dev/null)" || WORKSPACE="${PWD}"
fi
cd "${WORKSPACE}" 2>/dev/null || true

# --- configuration -----------------------------------------------------------
# Defaults first, then the repository's file overrides them. "auto" means "show
# the group when its runtime is actually present", which is what makes the
# no-config case correct for a PHP repo and a Go repo alike.
TITLE=""
SHOW_PHP="auto"
SHOW_NODE="auto"
SHOW_GO="auto"
SHOW_PYTHON="auto"
SHOW_JAVA="auto"
PHP_EXTENSIONS=""
PHP_NOTE=""
NODE_DEPS=""
COMPOSER_DEPS=""
EXTRA_ROWS=""

CONF="${WORKSPACE}/.devcontainer/env-info.conf"
if [ -f "${CONF}" ]; then
    # shellcheck source=/dev/null
    . "${CONF}" 2>/dev/null || true
fi

# A repository that sets no title gets its directory name, which is the
# repository name in every layout the team uses.
if [ -z "${TITLE}" ]; then
    TITLE="${WORKSPACE##*/} - development environment"
fi

# --- colours -----------------------------------------------------------------
# Colourise only for an interactive terminal: honour NO_COLOR (any value, per
# no-color.org), a dumb TERM, and redirection to a file or pipe.
if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-dumb}" = "dumb" ] || [ ! -t 1 ]; then
    C_RESET='' C_BOX='' C_GROUP='' C_LABEL='' C_VALUE='' C_NOTE='' C_WARN='' C_MISS=''
else
    C_RESET=$'\033[0m'
    C_BOX=$'\033[1;36m'   # bright cyan   - banner frame
    C_GROUP=$'\033[1;36m' # bright cyan   - group headings
    C_LABEL=$'\033[0;37m' # light gray    - row labels
    C_VALUE=$'\033[1;32m' # bright green  - resolved versions
    C_NOTE=$'\033[0;90m'  # dark gray     - contextual notes
    C_WARN=$'\033[1;33m'  # bright yellow - constraint mismatch
    C_MISS=$'\033[0;33m'  # yellow        - absent tool
fi

have() { command -v "${1}" >/dev/null 2>&1; }

# words <string> — the string's whitespace-separated words, one per line.
#
# Needed because zsh does not word-split an unquoted parameter expansion, so
# `for x in ${LIST}` iterates once over the whole string there while splitting
# correctly under bash. zsh *does* split an unquoted command substitution, so
# routing the list through one makes the loop behave identically in both shells.
words() { printf '%s\n' "${1}" | tr -s ' \t' '\n'; }

# probe <command...> — first line of output, trimmed; empty when absent or failing.
probe() {
    have "${1}" || return 0
    local out nl='
'
    out="$("$@" 2>/dev/null)" || out=""
    out="${out%%"${nl}"*}"
    # Some tools colourise unconditionally even writing to a pipe, and even with
    # NO_COLOR set (`mvn --version` is one), which leaves escape fragments in the
    # rendered value — "3.8.7[m" rather than "3.8.7". Only pay for the sed when
    # there is actually an escape to strip.
    case "${out}" in
        *$'\033'*) out="$(printf '%s' "${out}" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')" ;;
    esac
    while [ "${out# }" != "${out}" ]; do out="${out# }"; done
    while [ "${out% }" != "${out}" ]; do out="${out% }"; done
    printf '%s\n' "${out}"
}

# field <n> <string> — whitespace-separated field n for n in 1..3, else the rest.
# Uses `read` rather than awk so a row costs no extra process.
field() {
    local n="${1}"
    shift
    local f1 f2 f3 rest
    read -r f1 f2 f3 rest <<FIELD_EOF
${*}
FIELD_EOF
    case "${n}" in
        1) printf '%s\n' "${f1}" ;;
        2) printf '%s\n' "${f2}" ;;
        3) printf '%s\n' "${f3}" ;;
        *) printf '%s\n' "${rest}" ;;
    esac
}

# ver_ge <a> <b> — true when dotted-numeric version a >= b.
ver_ge() {
    [ "$(printf '%s\n%s\n' "${1}" "${2}" | sort -V | head -1)" = "${2}" ]
}

# json <file> <jq-filter> [args...] — a value out of a JSON file, or empty.
json() {
    local file="${1}"
    local filter="${2}"
    shift 2
    have jq || return 0
    [ -f "${file}" ] || return 0
    jq -r "${filter}" "$@" "${file}" 2>/dev/null | head -1 || true
}

# show <auto|true|false> <binary> — should this group be rendered?
show() {
    case "${1}" in
        true) return 0 ;;
        false) return 1 ;;
        *) have "${2}" ;;
    esac
}

# --- rendering ---------------------------------------------------------------
# The frame is sized from the title, so editing the title cannot misalign the box.
banner() {
    local bar
    bar="$(printf '%*s' "$((${#TITLE} + 4))" '')"
    bar="${bar// /-}"
    printf '%s+%s+%s\n' "${C_BOX}" "${bar}" "${C_RESET}"
    printf '%s|%s  %s  %s|%s\n' "${C_BOX}" "${C_RESET}" "${TITLE}" "${C_BOX}" "${C_RESET}"
    printf '%s+%s+%s\n' "${C_BOX}" "${bar}" "${C_RESET}"
}

group() { printf '\n%s\n' "${C_GROUP}${1}${C_RESET}"; }

# row <label> <value> [note] [note-colour]
# An empty value renders as "(not installed)" rather than a blank column, so a
# vanished binary reads as absent instead of as a working tool.
row() {
    local label="${1}" value="${2:-}" note="${3:-}" note_color="${4:-${C_NOTE}}" rendered
    if [ -z "${value}" ]; then
        rendered="${C_MISS}${MISSING}${C_RESET}"
    else
        rendered="${C_VALUE}${value}${C_RESET}"
    fi
    [ -n "${note}" ] && rendered="${rendered} ${note_color}${note}${C_RESET}"
    printf '  %s%-*s%s %s\n' "${C_LABEL}" "${LABEL_WIDTH}" "${label}" "${C_RESET}" "${rendered}"
}

# info <label> <value> — like row(), for a fact that is not an installable thing
# (the OS name), where "(not installed)" would be nonsense.
info() {
    local label="${1}" value="${2:-}" rendered
    if [ -z "${value}" ]; then
        rendered="${C_NOTE}${UNKNOWN}${C_RESET}"
    else
        rendered="${C_VALUE}${value}${C_RESET}"
    fi
    printf '  %s%-*s%s %s\n' "${C_LABEL}" "${LABEL_WIDTH}" "${label}" "${C_RESET}" "${rendered}"
}

# tool_row <label> <binary> <version> [note] [note-colour]
# Presence and version are separate facts, so a binary that is installed but whose
# version cannot be read reports "(version unknown)" rather than "(not installed)".
# Conflating the two sends you looking for a missing tool that is right there.
tool_row() {
    local label="${1}" bin="${2}" version="${3:-}" note="${4:-}" color="${5:-${C_NOTE}}"
    if have "${bin}"; then
        row "${label}" "${version:-${NO_VERSION}}" "${note}" "${color}"
    else
        row "${label}" "" "${note}" "${color}"
    fi
}

# engine_row <label> <binary> <installed> <constraint>
# Renders a package.json engines constraint as a note, highlighted when the
# installed version is demonstrably below it. Only a ">=X.Y.Z" floor is
# verdict-able; any other range form is reported verbatim rather than judged.
engine_row() {
    local label="${1}" bin="${2}" installed="${3}" constraint="${4}" note="" color="${C_NOTE}" floor
    if [ -n "${constraint}" ]; then
        note="(package.json requires ${constraint})"
        floor="${constraint#>=}"
        if [ "${floor}" != "${constraint}" ] && [ -n "${installed}" ] &&
            ! ver_ge "${installed}" "${floor}"; then
            note="(below package.json requirement ${constraint})"
            color="${C_WARN}"
        fi
    fi
    tool_row "${label}" "${bin}" "${installed}" "${note}" "${color}"
}

# --- groups ------------------------------------------------------------------
show_container() {
    group "Container"

    local pretty arch
    # shellcheck disable=SC1091
    [ -r /etc/os-release ] && . /etc/os-release 2>/dev/null
    pretty="${PRETTY_NAME:-${NAME:-}}"
    arch="$(uname -m 2>/dev/null || true)"
    [ -n "${pretty}" ] && [ -n "${arch}" ] && pretty="${pretty} (${arch})"
    info "OS" "${pretty:-${arch}}"

    tool_row "Git" git "$(field 3 "$(probe git --version)")"
    tool_row "GitHub CLI (gh)" gh "$(field 3 "$(probe gh --version)")"
    tool_row "Claude Code" claude "$(probe claude --version)"
    # `rtk --version` prints "rtk <version>". Worth a row of its own: the PreToolUse hook
    # that calls it comes from the bind-mounted ~/.claude, so "hook configured but binary
    # missing" is a real state, and this row is where you see it.
    tool_row "RTK" rtk "$(field 2 "$(probe rtk --version)")"
}

show_php_group() {
    show "${SHOW_PHP}" php || return 0
    group "PHP runtime"

    tool_row "PHP" php "$(probe php -r 'echo PHP_VERSION;')" "${PHP_NOTE}"
    # `-d /` points Composer away from the project: its own version does not
    # depend on the working directory, but scanning one makes it fork dozens of
    # extra git processes. --no-plugins keeps plugin code out of the probe too.
    tool_row "Composer" composer \
        "$(field 3 "$(probe composer --version --no-ansi --no-plugins -d /)")"

    local ext version
    for ext in $(words "${PHP_EXTENSIONS}"); do
        # An extension ships no binary of its own — the version comes from the
        # runtime, and an empty result means "not loaded".
        version="$(probe php -r "echo phpversion('${ext}') ?: '';")"
        row "ext-${ext}" "${version}"
    done
}

show_node_group() {
    show "${SHOW_NODE}" node || return 0
    group "Node toolchain"

    local node_version
    node_version="$(probe node --version)"
    node_version="${node_version#v}"
    engine_row "Node.js" node "${node_version}" "$(json package.json '.engines.node // empty')"
    engine_row "npm" npm "$(probe npm --version)" "$(json package.json '.engines.npm // empty')"

    local pinned
    pinned="$(json package.json '.packageManager // empty')"
    tool_row "pnpm" pnpm "$(probe pnpm --version)" "${pinned:+(package.json pins ${pinned})}"
}

show_go_group() {
    show "${SHOW_GO}" go || return 0
    group "Go toolchain"
    tool_row "Go" go "$(field 3 "$(probe go version)")"
    [ -f go.mod ] && info "go.mod requires" "$(grep -m1 '^go ' go.mod 2>/dev/null | cut -d' ' -f2)"
}

show_python_group() {
    show "${SHOW_PYTHON}" python3 || return 0
    group "Python toolchain"
    tool_row "Python" python3 "$(field 2 "$(probe python3 --version)")"
    tool_row "pip" pip3 "$(field 2 "$(probe pip3 --version)")"
}

show_java_group() {
    show "${SHOW_JAVA}" java || return 0
    group "Java toolchain"
    # `java -version` writes to stderr on older JDKs, hence the redirect. It also
    # quotes the version — `openjdk version "21.0.10"` — so the quotes come off.
    local java_version
    java_version="$(field 3 "$(java -version 2>&1 | head -1)")"
    tool_row "Java" java "${java_version//\"/}"
    tool_row "Maven" mvn "$(field 3 "$(probe mvn --version)")"
}

show_project_deps() {
    [ -n "${NODE_DEPS}${COMPOSER_DEPS}" ] || return 0
    group "Project dependencies"

    local dep installed declared
    # Installed versions are read from node_modules / vendor rather than from the
    # manifest, so an empty row means "install has not run" instead of silently
    # reporting what was merely requested.
    for dep in $(words "${NODE_DEPS}"); do
        installed="$(json "node_modules/${dep}/package.json" \
            --arg n "${dep}" 'if .name == $n then .version else empty end')"
        declared="$(json package.json --arg n "${dep}" \
            '(.dependencies[$n] // .devDependencies[$n]) // empty')"
        row "${dep}" "${installed}" "${declared:+(requires ${declared})}"
    done
    for dep in $(words "${COMPOSER_DEPS}"); do
        installed="$(json vendor/composer/installed.json --arg n "${dep}" \
            '((.packages // .)[] | select(.name == $n) | .version) // empty')"
        declared="$(json composer.json --arg n "${dep}" \
            '(.require[$n] // .["require-dev"][$n]) // empty')"
        row "${dep}" "${installed}" "${declared:+(requires ${declared})}"
    done
}

# EXTRA_ROWS carries whatever a repository needs that no group above covers —
# whmcs-src's Apache and MariaDB versions, for instance. One entry per line,
# "Label|command to run|field index"; field index defaults to the whole line.
show_extra_rows() {
    [ -n "${EXTRA_ROWS}" ] || return 0
    group "Services"

    local label cmd idx value
    printf '%s\n' "${EXTRA_ROWS}" | while IFS='|' read -r label cmd idx; do
        [ -n "${label}" ] && [ -n "${cmd}" ] || continue
        # The command arrives as one string and has to reach probe() as separate
        # arguments. `set --` on a command substitution splits under both shells,
        # where expanding ${cmd} directly would not under zsh. Already inside the
        # pipeline's subshell, so clobbering the positional parameters is contained.
        # shellcheck disable=SC2046
        set -- $(words "${cmd}")
        value="$(probe "$@")"
        if [ -n "${idx}" ]; then
            value="$(field "${idx}" "${value}")"
        fi
        tool_row "${label}" "${1}" "${value}"
    done
}

main() {
    banner
    show_container
    show_php_group
    show_node_group
    show_go_group
    show_python_group
    show_java_group
    show_project_deps
    show_extra_rows
    printf '\n'
}

main "$@"
exit 0
