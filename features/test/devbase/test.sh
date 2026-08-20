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
check "defaults recorded" \
    grep -q 'DEVBASE_ZSH_AUTOSUGGESTIONS="true"' /usr/local/share/devbase/config.env
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
# Asserted against the recorded value rather than a literal. The pinned version used to
# be repeated here twice on top of the manifest and install.sh, so a bump meant four
# edits and only one of them changed what shipped. scripts/validate-features.sh now keeps
# the manifest and install.sh in step; what matters here is that the binary on PATH is
# the version the Feature was actually configured to install.
check "rtk version recorded" bash -c '
    . /usr/local/share/devbase/config.env
    [ -n "${DEVBASE_RTK_VERSION}" ]'
check "rtk reports the version the Feature recorded" bash -c '
    . /usr/local/share/devbase/config.env
    rtk --version | grep -qF "${DEVBASE_RTK_VERSION}"'
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

# --- config.env must be sourceable -------------------------------------------
# post-create sources it on its third line under `set -euo pipefail`, so a file that does
# not parse aborts post-create before a single step runs — the one failure this Feature
# cannot absorb, since a container that refuses to come up is not fixable from a terminal.
# Option values are escaped on the way in for exactly this reason.
check "config.env parses as shell" sh -n /usr/local/share/devbase/config.env

# --- dependsOn -----------------------------------------------------------------
# Neither of these is listed by this test's feature set, so their presence is entirely
# the manifest's `dependsOn` doing its job. Asserting the binaries rather than the
# manifest is the point: `installsAfter` would parse identically and install neither,
# and the resulting container looks fine until the credential helper needs `gh`.
check "dependsOn installed the gh CLI" command -v gh
# -l so a PATH addition made in the login profile is picked up the way a real shell
# would pick it up.
check "dependsOn installed the claude CLI" bash -lc 'command -v claude'

# --- setup.sh steps, asserted as effects -------------------------------------
# These steps are what the Feature is for, and until now only the *recording* of their
# option values was covered: nothing proved the step itself did anything. Each is called
# directly rather than through post-create so the assertion names the behaviour that
# broke rather than "post-create failed somewhere".

# devbase_setup_global_packages was the last step whose coverage stopped at the recorded
# option value: nothing proved a single package ever reached the container. That is the
# shape both defects this suite has shipped had — a green check for a step that did nothing.
#
# Asserted against the recorded list rather than a literal, for the same reason the RTK
# version is: `globalPackages` is what a consumer changes, so the check has to follow the
# option instead of needing an edit alongside it. `pnpm ls -g` is queried state, not the
# step's own log output.
check "every recorded global package is installed globally" bash -c '
    set -e
    . /usr/local/share/devbase/config.env
    . /usr/local/share/devbase/setup.sh
    devbase_setup_global_packages "${DEVBASE_GLOBAL_PACKAGES}" >/tmp/global.log 2>&1
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    installed="$(pnpm ls -g --depth 0 --json)"
    for entry in $(printf "%s" "${DEVBASE_GLOBAL_PACKAGES}" | tr "," " "); do
        # Strip the trailing @version; a bare @scope/name has nothing to strip.
        name="${entry%@*}"
        [ -n "${name}" ] || name="${entry}"
        printf "%s" "${installed}" | jq -e --arg n "${name}" \
            ".[0].dependencies | has(\$n)" >/dev/null
    done'

# Reaching the store is only half of it: the binaries have to land in the PNPM_HOME the
# shipped .zshrc puts on PATH, which is the whole purpose of the global-bin-dir write. The
# two paths are hardcoded in separate files, so this is also the check that catches them
# drifting apart — a drift that installs everything successfully and still leaves `cz`
# unfindable in every terminal.
check "global binaries land in the PNPM_HOME the shell config puts on PATH" bash -c '
    set -e
    grep -qF "export PNPM_HOME=\"\$HOME/.local/share/pnpm\"" "${HOME}/.zshrc"
    test -x "${HOME}/.local/share/pnpm/cz"'

# The report-and-skip rule, on the one prerequisite this step has. Unreachable in a real
# build for the same reason the pnpm branch further down is — the node dependency always
# brings pnpm — so emptying PATH is what makes it testable, and is honest about what it
# proves: the function needs only shell builtins to reach this branch.
check "global packages without pnpm are reported, not fatal" bash -c '
    set -e
    . /usr/local/share/devbase/setup.sh
    PATH= devbase_setup_global_packages "commitizen@latest" 2>&1 | grep -q "pnpm not available"'

# The --replace-all/--add pair has to leave exactly gh's helper in the local config. The
# function already verifies its own write, because a foreign-owned .git makes that write
# fail silently and a swallowed failure here surfaces much later as a password prompt.
check "gh credential helper is written to the workspace git config" bash -c '
    set -e
    rm -rf /tmp/ghws && mkdir -p /tmp/ghws && cd /tmp/ghws && git init -q .
    . /usr/local/share/devbase/setup.sh
    devbase_setup_gh_credential_helper >/dev/null
    git config --local --get-all credential.helper | grep -qxF "!gh auth git-credential"'

# Outside a working tree it must skip: some frames run post-create before anything is
# cloned, and that is a normal state rather than a fault.
check "gh credential helper skips outside a git tree" bash -c '
    set -e
    rm -rf /tmp/nogitws && mkdir -p /tmp/nogitws && cd /tmp/nogitws
    . /usr/local/share/devbase/setup.sh
    devbase_setup_gh_credential_helper | grep -q "Not a git working tree"'

# The history symlink is the whole of historyPersistence, and it depends on a host mount
# the consuming frame provides. Every branch matters, and they are not interchangeable: a
# missing mount is a supported configuration and must stay a detail, an empty one is a
# broken mount source that must not stay silent, and a mount with no history file yet is
# a first run that has to be bootstrapped rather than skipped forever.
check "shell history is linked when the host mount exists" bash -c '
    set -e
    sudo mkdir -p /WSL_USER && sudo touch /WSL_USER/.zsh_history
    sudo chown -R "$(id -un)" /WSL_USER
    rm -f "${HOME}/.zsh_history"
    export CI=false GITHUB_ACTIONS=false
    . /usr/local/share/devbase/setup.sh
    devbase_setup_history_persistence >/dev/null
    test -L "${HOME}/.zsh_history"
    [ "$(readlink "${HOME}/.zsh_history")" = "/WSL_USER/.zsh_history" ]'

check "shell history stays container-local without the host mount" bash -c '
    set -e
    sudo rm -rf /WSL_USER
    rm -f "${HOME}/.zsh_history"
    export CI=false GITHUB_ACTIONS=false
    . /usr/local/share/devbase/setup.sh
    devbase_setup_history_persistence | grep -q "history stays container-local"
    ! test -e "${HOME}/.zsh_history"'

check "shell history is skipped in CI" bash -c '
    set -e
    export CI=true
    . /usr/local/share/devbase/setup.sh
    devbase_setup_history_persistence | grep -q "Skipping history persistence in CI"'

# The mount is there and the host simply has no history file yet — every first run on a
# new machine. Skipping here is self-perpetuating: nothing else ever creates the file, so
# the link is never made and history never begins to persist.
check "shell history bootstraps when the host has no history file" bash -c '
    set -e
    sudo rm -rf /WSL_USER && sudo mkdir -p /WSL_USER
    sudo touch /WSL_USER/.profile
    sudo chown -R "$(id -un)" /WSL_USER
    rm -f "${HOME}/.zsh_history"
    export CI=false GITHUB_ACTIONS=false
    . /usr/local/share/devbase/setup.sh
    devbase_setup_history_persistence >/dev/null
    test -f /WSL_USER/.zsh_history
    test -L "${HOME}/.zsh_history"
    [ "$(readlink "${HOME}/.zsh_history")" = "/WSL_USER/.zsh_history" ]'

# Docker creates a missing bind source as an empty directory, so an empty /WSL_USER means
# the frame resolved its source path to nothing — not that the host is new. Bootstrapping
# into it would write a file nothing reads and report SUCCESS for persistence that cannot
# work, which is precisely the failure this suite exists to prevent.
check "an empty host mount is reported instead of bootstrapped" bash -c '
    set -e
    sudo rm -rf /WSL_USER && sudo mkdir -p /WSL_USER
    sudo chown -R "$(id -un)" /WSL_USER
    rm -f "${HOME}/.zsh_history"
    export CI=false GITHUB_ACTIONS=false
    . /usr/local/share/devbase/setup.sh
    devbase_setup_history_persistence 2>&1 | grep -q "is empty"
    ! test -e /WSL_USER/.zsh_history
    ! test -e "${HOME}/.zsh_history"'

# devbase_setup_project_dependencies is the step every consuming repository depends on,
# and it had no coverage whatsoever: every scenario ran post-create from /tmp, where no
# manifest exists, so neither the composer nor the Node branch was ever entered.
#
# This base image has no composer, which makes it the right place to assert the rule that
# a manifest whose tool is absent is reported and skipped, never fatal.
check "a composer.json without composer is reported, not fatal" bash -c '
    set -e
    rm -rf /tmp/phpws && mkdir -p /tmp/phpws && cd /tmp/phpws
    printf "{}\n" > composer.json
    . /usr/local/share/devbase/setup.sh
    devbase_setup_project_dependencies 2>&1 | grep -q "composer is missing"'

# The pnpm half has to simulate the missing tool. devbase depends on the Node feature,
# which ships `pnpmVersion: latest`, so pnpm is present in every container this suite
# builds and no option makes it absent — which is why `installPnpm` was removed outright.
# Emptying PATH is enough and is honest about what it proves: the function needs only
# shell builtins to reach this branch, so nothing else about it is being stubbed out.
check "a package.json without pnpm is reported, not fatal" bash -c '
    set -e
    rm -rf /tmp/nodews && mkdir -p /tmp/nodews && cd /tmp/nodews
    printf "{}\n" > package.json
    . /usr/local/share/devbase/setup.sh
    PATH= devbase_setup_project_dependencies 2>&1 | grep -q "pnpm is missing"'

check "a workspace with no manifest is a detail, not a fault" bash -c '
    set -e
    rm -rf /tmp/barews && mkdir -p /tmp/barews && cd /tmp/barews
    . /usr/local/share/devbase/setup.sh
    devbase_setup_project_dependencies | grep -q "nothing to install"'

check "seeds .env from .env.example" bash -c '
    set -e
    rm -rf /tmp/envws && mkdir -p /tmp/envws && cd /tmp/envws
    printf "TOKEN=example\n" > .env.example
    export CI=false GITHUB_ACTIONS=false
    . /usr/local/share/devbase/setup.sh
    devbase_setup_env_file >/dev/null
    grep -q "TOKEN=example" .env'

# Overwriting a developer's .env would destroy local credentials, so this one matters
# more than the creation case.
check "an existing .env is never overwritten" bash -c '
    set -e
    cd /tmp/envws && printf "TOKEN=mine\n" > .env
    export CI=false GITHUB_ACTIONS=false
    . /usr/local/share/devbase/setup.sh
    devbase_setup_env_file >/dev/null
    grep -q "TOKEN=mine" .env'

# --- post-attach --------------------------------------------------------------
# post-attach had no coverage at all, which left autoloadEnvScript as the only option with
# no effect asserted in either direction. Kept last in this file on purpose: the ~/.zshenv
# it writes is sourced by every zsh started afterwards, the banner checks above included.
check "post-attach adds the workspace env.sh to ~/.zshenv exactly once" bash -c '
    set -e
    rm -rf /tmp/attachws && mkdir -p /tmp/attachws && cd /tmp/attachws
    printf "export DEVBASE_ATTACH_PROBE=1\n" > env.sh
    rm -f "${HOME}/.zshenv"
    zsh /usr/local/bin/devbase-post-attach.sh >/dev/null 2>&1
    grep -qF "/tmp/attachws/env.sh" "${HOME}/.zshenv"
    # It runs on *every* attach, so the marker has to stop a second line being appended.
    zsh /usr/local/bin/devbase-post-attach.sh >/dev/null 2>&1
    [ "$(grep -cF "/tmp/attachws/env.sh" "${HOME}/.zshenv")" -eq 1 ]
    rm -f "${HOME}/.zshenv"'

check "post-attach leaves ~/.zshenv alone when the workspace has no env.sh" bash -c '
    set -e
    rm -rf /tmp/noenvws && mkdir -p /tmp/noenvws && cd /tmp/noenvws
    rm -f "${HOME}/.zshenv"
    zsh /usr/local/bin/devbase-post-attach.sh >/dev/null 2>&1
    ! test -e "${HOME}/.zshenv"'

reportResults
