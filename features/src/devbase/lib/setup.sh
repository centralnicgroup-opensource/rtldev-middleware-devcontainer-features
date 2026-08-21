#!/usr/bin/env bash
# shellcheck shell=bash
#
# devbase — the setup steps shared by every RTLDEV middleware repository,
# extracted from the three hand-maintained post-create.sh copies (php-sdk,
# mcp-dis, whmcs-src) that had drifted apart.
#
# Sourced by devbase-post-create.sh, which owns the shell options and the order.
# Every function is independently callable and safe to skip.
#
# Two conventions the whole file follows:
#   * A missing prerequisite is reported and skipped, never fatal. A container
#     that comes up with no pnpm is fixable from a terminal; one that refuses to
#     come up at all is not.
#   * Nothing here assumes a language. Steps that only make sense for a manifest
#     that exists check for that manifest first.

# shellcheck source=log.sh
. /usr/local/share/devbase/log.sh

# _devbase_in_ci — true inside GitHub Actions and equivalents.
#
# Host-coupled steps (shell-history symlink, .env seeding) are pointless in CI
# and their absence there is not a failure worth logging as one.
#
# GITHUB_ACTIONS is the variable GitHub Actions actually sets. This read
# GITHUB_CLI, which nothing sets — a name inherited from the scripts this file
# replaced. It was harmless only because CI is set alongside it, so the second
# test carried the whole check while the first looked deliberate.
_devbase_in_ci() {
    [ "${GITHUB_ACTIONS:-false}" = "true" ] || [ "${CI:-false}" = "true" ]
}

# ---------------------------------------------------------------------------
# Node toolchain
# ---------------------------------------------------------------------------

# devbase_setup_npm_floor — raise npm to the major version package.json asks for.
#
# The Node feature ships whatever npm the Node release bundles, which regularly
# lags a declared `engines.npm`. Without this the container advertises a
# constraint it does not meet, and `npm` warns on every install.
#
# Generalised from mcp-dis, where the required major was hardcoded to 12: the
# floor is read from the manifest, so there is nothing to keep in sync.
devbase_setup_npm_floor() {
    [ -f "package.json" ] || return 0
    command_exists npm || return 0
    command_exists jq || return 0

    local declared floor current
    declared="$(jq -r '.engines.npm // empty' package.json 2>/dev/null)" || return 0
    [ -n "${declared}" ] || return 0

    # Only a ">=X..." floor is actionable; any other range form is left alone
    # rather than guessed at.
    case "${declared}" in
        '>='*) floor="${declared#>=}" ;;
        *) return 0 ;;
    esac
    floor="${floor%%.*}"
    [ -n "${floor}" ] || return 0

    log_info "Checking npm against package.json engines (${declared})..."
    current="$(npm --version 2>/dev/null)" || current=""
    if [ -z "${current}" ]; then
        log_error "npm not found"
        return 0
    fi

    if [ "${current%%.*}" -lt "${floor}" ]; then
        # No sudo: the Node feature installs into a prefix owned by the remote
        # user, and sudo's secure_path does not contain that npm at all.
        execute_with_indent "npm i --silent -g npm@${floor}" \
            "Upgrading npm ${current} to v${floor}" ||
            log_error "npm upgrade failed — continuing with ${current}"
        log_success "npm is now $(npm --version 2>/dev/null || echo "${current}")"
    else
        log_detail "npm ${current} already satisfies ${declared}"
    fi
}

# devbase_setup_pnpm — install pnpm globally if it is not already there.
#
# Tries without sudo first, then with: php-sdk needed sudo (npm from apt, prefix
# owned by root), mcp-dis needed no sudo (npm from the Node feature's
# user-owned prefix). Trying in that order works for both instead of picking one
# and being wrong in half the repositories.
devbase_setup_pnpm() {
    if command_exists pnpm; then
        log_detail "pnpm already installed"
        return 0
    fi
    if ! command_exists npm; then
        log_error "npm not found — skipping pnpm (add the Node feature to devcontainer.json)"
        return 0
    fi

    log_info "Installing pnpm..."
    if execute_with_indent "npm i --silent -g pnpm" "Installing pnpm globally"; then
        log_success "pnpm installed"
    elif command_exists sudo && execute_with_indent "sudo npm i --silent -g pnpm" \
        "Installing pnpm globally (with sudo)"; then
        log_success "pnpm installed"
    else
        log_error "Failed to install pnpm"
        return 0
    fi
}

# devbase_setup_global_packages <comma-separated-packages>
#
# Installs the team's global CLI tooling with pnpm, into a PNPM_HOME the shell config
# also puts on PATH. The set is whatever the caller passes — the default lives in the
# globalPackages option rather than being enumerated here, so this comment cannot drift
# out of step with it.
devbase_setup_global_packages() {
    local spec="${1:-}"
    [ -n "${spec}" ] || return 0
    command_exists pnpm || {
        log_error "pnpm not available — skipping global packages"
        return 0
    }

    log_info "Installing global packages..."

    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    mkdir -p "${PNPM_HOME}"

    if ! _devbase_in_ci; then
        if [ ! -f "${HOME}/.zshrc" ] || ! grep -q "pnpm" "${HOME}/.zshrc"; then
            execute_with_indent "pnpm setup" "Setting up pnpm for the current user" || true
        fi
        # `set +e` as well as `set +u`, plus `|| true`: once zsh-autosuggestions
        # is installed, sourcing .zshrc non-interactively runs a widget setup
        # that returns non-zero, which under the caller's `set -e` would abort
        # post-create before any dependency was installed. PNPM_HOME and PATH are
        # exported above regardless, so the sourced values are a convenience.
        # shellcheck disable=SC1090,SC1091
        [ -f "${HOME}/.zshrc" ] && { (
            set +u +e
            . "${HOME}/.zshrc"
        ) 2>/dev/null || true; }
    fi

    # Keep pnpm's global bin dir and PNPM_HOME the same directory, or globally
    # installed binaries land somewhere that is not on PATH.
    pnpm config set global-bin-dir "${PNPM_HOME}" 2>/dev/null || true

    local packages
    packages="$(printf '%s' "${spec}" | tr ',' ' ')"
    log_detail "Packages: ${packages}"
    if execute_with_indent "pnpm add -g ${packages}" "Installing global packages"; then
        log_success "Global packages installed"
    else
        log_error "Failed to install global packages"
    fi
}

# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

# devbase_setup_zsh_autosuggestions — history-based inline completions.
#
# Suggestions come from $HISTFILE, so together with the history symlink below
# they persist across rebuilds with no extra state.
devbase_setup_zsh_autosuggestions() {
    log_info "Installing zsh-autosuggestions..."
    local plugin_dir="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    mkdir -p "$(dirname "${plugin_dir}")"

    if [ -d "${plugin_dir}/.git" ]; then
        execute_with_indent "git -C '${plugin_dir}' pull --ff-only" \
            "Updating zsh-autosuggestions" || log_error "Update failed — keeping the installed copy"
        return 0
    fi

    # A leftover partial directory that is not a git repo would make the clone
    # fail forever, so clear it first.
    rm -rf "${plugin_dir}"
    if execute_with_indent \
        "git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions '${plugin_dir}'" \
        "Cloning zsh-autosuggestions"; then
        log_success "zsh-autosuggestions installed"
    else
        log_error "Failed to install zsh-autosuggestions"
    fi
}

# devbase_setup_history_persistence — keep shell history across rebuilds.
#
# Depends on the frame bind-mounting the host home at /WSL_USER. A missing mount
# is a normal configuration, not an error, so it is reported as detail.
devbase_setup_history_persistence() {
    if _devbase_in_ci; then
        log_detail "Skipping history persistence in CI"
        return 0
    fi

    log_info "Linking shell history..."
    local mount="/WSL_USER"
    local source="${mount}/.zsh_history"
    local target="${HOME}/.zsh_history"

    if [ -L "${target}" ]; then
        log_detail "History symlink already in place"
        return 0
    fi

    if [ ! -d "${mount}" ]; then
        log_detail "No ${source} on the host mount — history stays container-local"
        return 0
    fi

    # An empty mount is not a host home: Docker creates a missing bind source as an
    # empty directory, so this is the frame's source path failing to resolve — most
    # often the ${localEnv:HOME}${localEnv:USERPROFILE} concatenation on a host that
    # defines both. Creating a history file inside it would persist nothing and hide
    # the cause, and this is the only place the mistake becomes visible at all.
    if [ -z "$(ls -A "${mount}" 2>/dev/null)" ]; then
        log_error "${mount} is empty — check that mount's source path in devcontainer.json"
        return 0
    fi

    # A host that has never run zsh has no history file, and nothing else will create
    # one: waiting for it to appear is what kept persistence from ever starting.
    if [ ! -f "${source}" ] && ! touch "${source}" 2>/dev/null; then
        log_error "Could not create ${source} — history stays container-local"
        return 0
    fi

    ln -sf "${source}" "${target}"
    if [ -L "${target}" ] && [ -e "${target}" ]; then
        log_success "History linked to ${source}"
    else
        log_error "Could not link ${target} to ${source}"
    fi
}

# ---------------------------------------------------------------------------
# Git / GitHub
# ---------------------------------------------------------------------------

# devbase_setup_gh_credential_helper — authenticate git through the gh CLI.
#
# The --replace-all with an empty value first clears the system-level helper
# VS Code injects; without that, both helpers are consulted and the wrong one
# can win.
devbase_setup_gh_credential_helper() {
    git rev-parse --git-dir >/dev/null 2>&1 || {
        log_detail "Not a git working tree — skipping credential helper"
        return 0
    }
    log_info "Pointing git credentials at the gh CLI..."
    local helper='!gh auth git-credential'
    # `|| true` on the writes so a read-only or foreign-owned .git cannot abort
    # post-create — but then verify, because a swallowed failure that still logs
    # SUCCESS is worse than the failure: it sends you looking somewhere else when
    # a push later asks for a password.
    git config --local --replace-all credential.helper '' 2>/dev/null || true
    git config --local --add credential.helper "${helper}" 2>/dev/null || true

    if git config --local --get-all credential.helper 2>/dev/null | grep -qF "${helper}"; then
        log_success "git will use 'gh auth git-credential'"
    else
        log_error "Could not set the git credential helper — check ownership of .git (git's safe.directory)"
    fi
}

# devbase_setup_ssh_commit_signing — make an already-configured SSH signing key
# usable inside the container.
#
# The failure this exists for: a frame that bind-mounts the host ~/.gitconfig (the one
# in this repository does) brings commit.gpgsign=true, gpg.format=ssh and a
# user.signingkey naming a path under the *host's* ~/.ssh. That path does not exist in
# the container, so every commit dies with "Couldn't load public key ...: No such file
# or directory" — a message that names the key rather than the missing mount, which is
# why it costs an afternoon the first time.
#
# The repair is deliberately not a key file. VS Code forwards the host ssh-agent, so the
# private half is already reachable, and git takes the public half inline as
# `key::<literal>`. Writing a file instead would mean writing into ~/.ssh, which frames
# routinely bind-mount from the host — the same trap that keeps devbase out of ~/.claude.
# The inline form also resolves identically on the host, which matters because the
# .git/config it is written to lives in the bind-mounted workspace and both read it.
devbase_setup_ssh_commit_signing() {
    git rev-parse --git-dir >/dev/null 2>&1 || {
        log_detail "Not a git working tree — skipping commit signing"
        return 0
    }

    # Only ever repairs signing a repository already asked for. Turning it on for
    # someone who never configured it would be devbase deciding a policy that belongs
    # to the developer and their organisation.
    [ "$(git config --get commit.gpgsign 2>/dev/null || true)" = "true" ] || {
        log_detail "Commit signing not enabled — nothing to configure"
        return 0
    }
    [ "$(git config --get gpg.format 2>/dev/null || true)" = "ssh" ] || {
        log_detail "Commit signing is not in ssh format — leaving it alone"
        return 0
    }

    local configured resolved
    configured="$(git config --get user.signingkey 2>/dev/null || true)"
    resolved="${configured}"
    # git expands a leading ~ itself, so the check has to as well or an existing key
    # would look missing and be replaced for no reason. Written as a prefix strip rather
    # than a `~/*` case pattern: a quoted tilde is a shellcheck warning and an unquoted
    # one is a pattern zsh may expand, and neither is worth the risk here.
    if [ "${configured#\~/}" != "${configured}" ]; then
        resolved="${HOME}/${configured#\~/}"
    fi

    # An inline key needs nothing. A key file that exists is the developer's own
    # arrangement already working. Either way, touching it could only make it worse.
    case "${configured}" in
    key::*)
        log_detail "Signing key is already an inline key"
        return 0
        ;;
    esac
    if [ -n "${resolved}" ] && [ -f "${resolved}" ]; then
        log_detail "Signing key ${configured} is present — nothing to repair"
        return 0
    fi

    log_info "Repairing SSH commit signing..."

    if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "${SSH_AUTH_SOCK}" ]; then
        log_error "No ssh-agent forwarded — commits stay unsigned (key: ${configured:-unset})"
        return 0
    fi
    command_exists ssh-add || {
        log_error "ssh-add is missing — cannot read the forwarded agent"
        return 0
    }
    command_exists ssh-keygen || {
        log_error "ssh-keygen is missing — cannot verify the agent can sign"
        return 0
    }

    local agent_keys count key=""
    agent_keys="$(ssh-add -L 2>/dev/null || true)"
    count="$(printf '%s\n' "${agent_keys}" | grep -c '^ssh-' || true)"

    if [ "${count}" -eq 0 ]; then
        log_error "The forwarded agent holds no keys — commits stay unsigned"
        return 0
    elif [ "${count}" -eq 1 ]; then
        key="$(printf '%s\n' "${agent_keys}" | grep '^ssh-' | head -1 || true)"
    elif [ -n "${configured}" ]; then
        # Several keys, and which one GitHub accepts as a *signing* key is not knowable
        # from inside the container — an auth key signs a commit perfectly well and the
        # push is still rejected. The configured filename is the only hint available, so
        # an agent key whose comment names it is the intended one, and no match is a
        # skip rather than a guess.
        local wanted
        wanted="$(basename "${configured}")"
        key="$(printf '%s\n' "${agent_keys}" | grep '^ssh-' | grep -F "${wanted}" | head -1 || true)"
    fi

    if [ -z "${key}" ]; then
        log_error "Cannot tell which of the agent's ${count} keys signs — set user.signingkey to a key:: literal"
        return 0
    fi

    # A real signature, not just a key that looks plausible: the agent can hold a public
    # key whose private half it cannot use, and reporting SUCCESS for that would send the
    # next person looking at GitHub's key settings instead of at the agent.
    local probe
    probe="$(mktemp -d 2>/dev/null || true)"
    if [ -z "${probe}" ] || [ ! -d "${probe}" ]; then
        log_error "Could not create a temporary directory — leaving signing untouched"
        return 0
    fi
    printf '%s\n' "${key}" >"${probe}/key.pub"
    printf 'devbase\n' >"${probe}/probe"
    if ! ssh-keygen -Y sign -n git -f "${probe}/key.pub" "${probe}/probe" >/dev/null 2>&1; then
        rm -rf "${probe}"
        log_error "The forwarded agent cannot sign with that key — signing left unchanged"
        return 0
    fi
    rm -rf "${probe}"

    # --local, never --global: the global file is the host's own ~/.gitconfig on every
    # frame that mounts it, and rewriting a host-shared file from inside a container is
    # the one thing this Feature must not do.
    git config --local user.signingkey "key::${key}" 2>/dev/null || true
    if [ "$(git config --local --get user.signingkey 2>/dev/null || true)" = "key::${key}" ]; then
        log_success "Commit signing will use the forwarded agent"
    else
        log_error "Could not write user.signingkey — check ownership of .git (git's safe.directory)"
    fi
}

# ---------------------------------------------------------------------------
# Project dependencies
# ---------------------------------------------------------------------------

# devbase_setup_project_dependencies — install whatever the workspace declares.
#
# Manifest-presence branching is what lets one shared script serve a PHP repo, a
# Node repo and a repo with both, with no per-language variants to keep in sync.
# A repository with none of these manifests is a legitimate outcome, not a fault.
devbase_setup_project_dependencies() {
    local found=false

    if [ -f "composer.json" ]; then
        found=true
        log_info "Installing PHP dependencies..."
        if ! command_exists composer; then
            log_error "composer.json present but composer is missing (add the PHP feature)"
        # No --no-dev: a devcontainer wants the dev dependencies.
        elif execute_with_indent "composer install --optimize-autoloader --quiet" \
            "composer install"; then
            log_success "Composer dependencies installed"
        else
            log_error "composer install failed"
        fi
    fi

    if [ -f "package.json" ]; then
        found=true
        log_info "Installing Node dependencies..."
        if ! command_exists pnpm; then
            log_error "package.json present but pnpm is missing"
        elif execute_with_indent "pnpm install --frozen-lockfile --silent" "pnpm install"; then
            log_success "Node dependencies installed"
        # A stale lockfile must not stop the container coming up — resolve fresh
        # and let the resulting diff show up in review.
        elif execute_with_indent "pnpm install --no-frozen-lockfile --silent" \
            "pnpm install (lockfile refreshed)"; then
            log_detail "Installed without the frozen lockfile — commit the updated pnpm-lock.yaml"
        else
            log_error "pnpm install failed"
        fi
    fi

    if [ "${found}" = "false" ]; then
        log_detail "No composer.json or package.json in the workspace — nothing to install"
    fi
}

# devbase_setup_env_file — seed a local .env from the tracked example.
devbase_setup_env_file() {
    [ -f ".env.example" ] || return 0
    if _devbase_in_ci; then
        log_detail "Skipping .env seeding in CI"
        return 0
    fi

    log_info "Preparing the local environment file..."
    if [ -f ".env" ]; then
        log_detail ".env already exists, leaving it untouched"
    else
        cp .env.example .env
        log_success "Created .env from .env.example"
    fi
}
