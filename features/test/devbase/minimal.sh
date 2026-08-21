#!/usr/bin/env bash
#
# devbase Feature — every option turned off.
#
# The point of this scenario is that the opt-outs are real: a repository that
# disables a step must not get it anyway. It also proves install.sh survives with
# no apt phase, which is the path a minimal or non-Debian-derived base image
# takes.

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

# The library and entrypoints are unconditional — they are what the Feature *is*.
check "shared library still installed" test -f /usr/local/share/devbase/log.sh
check "entrypoints still installed" test -x /usr/local/bin/devbase-post-create.sh

# The opt-outs must be recorded, so the lifecycle scripts skip those steps.
check "global packages opt-out recorded" \
    grep -q 'DEVBASE_GLOBAL_PACKAGES=""' /usr/local/share/devbase/config.env
check "autosuggestions opt-out recorded" \
    grep -q 'DEVBASE_ZSH_AUTOSUGGESTIONS="false"' /usr/local/share/devbase/config.env
check "banner opt-out recorded" \
    grep -q 'DEVBASE_ENV_INFO_BANNER="false"' /usr/local/share/devbase/config.env
check "project dependencies opt-out recorded" \
    grep -q 'DEVBASE_INSTALL_PROJECT_DEPENDENCIES="false"' /usr/local/share/devbase/config.env

# RTK is the one option whose opt-out is worth asserting on the filesystem rather than on
# the recorded config: a default-on network download that ignores its flag would otherwise
# only show up as a slow build.
check "rtk not installed" bash -c '! test -e /usr/local/bin/rtk'
check "rtk opt-out recorded" \
    grep -q 'DEVBASE_INSTALL_RTK="false"' /usr/local/share/devbase/config.env

# The locale is deliberately not an option — containerEnv is static JSON with no option
# substitution, so a flag could not switch it off and would only be a lie (the same trap
# that keeps `mounts` unused). This scenario is where being unconditional is visible: every
# option is off and the charmap is still UTF-8. A consumer who wants something else sets
# LANG in their own containerEnv, which the CLI emits after the feature layer and therefore
# wins.
check "locale is UTF-8 with every option off" \
    bash -c '[ "$(locale charmap)" = "UTF-8" ]'

# An empty timezone means "leave the image alone", so nothing was written. No
# `|| true` here: with it, this check could never fail, and it duly reported
# SUCCESS while install.sh was writing Europe/Berlin anyway.
check "timezone left untouched" bash -c \
    '! grep -q "Europe/Berlin" /etc/timezone'

# post-create must be a no-op rather than a failure when everything is off.
check "post-create succeeds with every step disabled" \
    bash -c 'cd /tmp && zsh /usr/local/bin/devbase-post-create.sh'

# The other half of the global-packages coverage: post-create has just run with an empty
# list, and nothing may have been installed. This is the scenario that can prove it —
# pnpm is present here regardless, because the node dependency is not declinable, so the
# empty option value is the only thing standing between this container and a global
# install. The direct call names the behaviour; the missing binary is the effect.
check "an empty global package list installs nothing" bash -c '
    set -e
    . /usr/local/share/devbase/setup.sh
    [ -z "$(devbase_setup_global_packages "")" ]
    ! test -e "${HOME}/.local/share/pnpm/cz"'

# The signing opt-out is asserted through post-create rather than by calling the function,
# because what a consumer switches off is the option, not the step. A repository that signs
# must come out of a disabled run with its own configuration untouched — including the
# broken-looking key path, which is the developer's to fix if they chose to opt out.
check "ssh signing opt-out recorded" \
    grep -q 'DEVBASE_SSH_COMMIT_SIGNING="false"' /usr/local/share/devbase/config.env
check "ssh signing is not repaired when the option is off" bash -c '
    set -e
    rm -rf /tmp/signoffws && mkdir -p /tmp/signoffws && cd /tmp/signoffws && git init -q .
    git config --local commit.gpgsign true
    git config --local gpg.format ssh
    git config --local user.signingkey /nonexistent/.ssh/probe_key
    ssh-keygen -q -t ed25519 -N "" -C probe_key -f /tmp/signoffws/probe_key
    eval "$(ssh-agent -s)" >/dev/null
    ssh-add /tmp/signoffws/probe_key 2>/dev/null
    zsh /usr/local/bin/devbase-post-create.sh >/dev/null 2>&1
    [ "$(git config --local --get user.signingkey)" = "/nonexistent/.ssh/probe_key" ]
    ssh-agent -k >/dev/null'

# Every option here is empty or false, which makes this the scenario that proves the
# escaping of the recorded values does not mangle an empty string into something
# unparseable — post-create sources this file before it does anything else.
check "config.env parses as shell with every option empty or off" \
    sh -n /usr/local/share/devbase/config.env

# autoloadEnvScript was the one option with no effect assertion in either direction: only
# its recorded value was ever checked. With it off, a workspace that *does* have an env.sh
# must still be left alone.
check "autoload opt-out recorded" \
    grep -q 'DEVBASE_AUTOLOAD_ENV_SCRIPT="false"' /usr/local/share/devbase/config.env
check "post-attach does not autoload env.sh when disabled" bash -c '
    set -e
    rm -rf /tmp/attachws && mkdir -p /tmp/attachws && cd /tmp/attachws
    printf "export DEVBASE_ATTACH_PROBE=1\n" > env.sh
    rm -f "${HOME}/.zshenv"
    zsh /usr/local/bin/devbase-post-attach.sh >/dev/null 2>&1
    ! test -e "${HOME}/.zshenv"'

reportResults
