#!/usr/bin/env bash
#
# devbase Feature — build-time install.
#
# Runs as root while the image is being built, which is *before* the workspace
# is mounted. So everything here is image-level only: packages, the timezone,
# the shared shell library, the user's zsh/commitizen config, and the option
# values recorded for later. Anything that needs to read the repository (its
# manifests, its env-info.conf) belongs in devbase-post-create.sh, which runs
# on first create with the workspace in place.
#
# Bash, not zsh: the base image is not guaranteed to have zsh before
# common-utils has run, and a Feature's install.sh is executed with bash.

set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR="/usr/local/share/devbase"

# Option values arrive as upper-cased environment variables named after the
# option ids in devcontainer-feature.json. Defaults are repeated here so the
# script is also runnable standalone (which is how the tests drive it).
COMMON_PACKAGES="${COMMONPACKAGES:-true}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
INSTALL_PNPM="${INSTALLPNPM:-true}"
GLOBAL_PACKAGES="${GLOBALPACKAGES:-commitizen@latest,cz-conventional-changelog@latest}"
ZSH_AUTOSUGGESTIONS="${ZSHAUTOSUGGESTIONS:-true}"
HISTORY_PERSISTENCE="${HISTORYPERSISTENCE:-true}"
GH_CREDENTIAL_HELPER="${GHCREDENTIALHELPER:-true}"
ENV_INFO_BANNER="${ENVINFOBANNER:-true}"
INSTALL_PROJECT_DEPENDENCIES="${INSTALLPROJECTDEPENDENCIES:-true}"
AUTOLOAD_ENV_SCRIPT="${AUTOLOADENVSCRIPT:-true}"
INSTALL_RTK="${INSTALLRTK:-true}"
RTK_VERSION="${RTKVERSION:-0.45.0}"

# _REMOTE_USER / _REMOTE_USER_HOME are injected by the devcontainer CLI. The
# fallbacks keep the script usable outside that context; "automatic" is the
# CLI's sentinel for "work it out", which here means the first non-root user.
USERNAME="${_REMOTE_USER:-automatic}"
if [ "${USERNAME}" = "automatic" ] || [ -z "${USERNAME}" ]; then
    for candidate in vscode node codespace; do
        if id -u "${candidate}" >/dev/null 2>&1; then
            USERNAME="${candidate}"
            break
        fi
    done
fi
if [ "${USERNAME}" = "automatic" ]; then
    USERNAME="root"
fi
USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "${USERNAME}" | cut -d: -f6)}"
USER_HOME="${USER_HOME:-/home/${USERNAME}}"

echo "devbase: installing for user '${USERNAME}' (home: ${USER_HOME})"

# --- common packages ---------------------------------------------------------
# Deliberately no language runtime: those come from the devcontainers language
# features, which this Feature declares installsAfter so their binaries exist by
# the time post-create runs.
if [ "${COMMON_PACKAGES}" = "true" ]; then
    echo "devbase: installing common packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    # hadolint ignore=DL3008
    apt-get -y install --no-install-recommends \
        wget \
        jq \
        git \
        zip \
        unzip \
        curl \
        zsh \
        shellcheck
    apt-get -y autoremove
    apt-get -y clean
    rm -rf /var/lib/apt/lists/*
fi

# --- timezone ----------------------------------------------------------------
if [ -n "${TIMEZONE}" ] && [ -e "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    echo "devbase: setting timezone to ${TIMEZONE}"
    ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    echo "${TIMEZONE}" >/etc/timezone
elif [ -n "${TIMEZONE}" ]; then
    echo "devbase: unknown timezone '${TIMEZONE}', leaving the image default in place" >&2
fi

# --- RTK ---------------------------------------------------------------------
# RTK (github.com/rtk-ai/rtk) is a token-optimizing CLI proxy for Claude Code: a
# PreToolUse hook rewrites shell commands and filters their output.
#
# It belongs in this Feature rather than in each repository's Dockerfile (RSRMID-2933)
# because of an asymmetry: the hook lives in ~/.claude/settings.json, which every frame
# bind-mounts from the host, so the *configuration* is shared across host and container
# while the *binary* is not. A container without rtk therefore fires a hook that exits
# 127 on every Bash call — no savings, plus an error each time. Installing it centrally
# means the binary follows the hook everywhere instead of being re-pasted per repository.
#
# Only the binary is installed. `rtk init -g` is deliberately NOT run: it would rewrite
# the bind-mounted ~/.claude/settings.json, which is shared with the host and already
# carries the hook.
install_rtk() {
    local version="${1}"
    local asset expected actual url tmp

    # Upstream publishes musl for x86_64 but only gnu for aarch64, so the two arches do
    # not share a naming pattern and cannot be templated from uname alone.
    case "$(uname -m)" in
        x86_64 | amd64) asset="rtk-x86_64-unknown-linux-musl.tar.gz" ;;
        aarch64 | arm64) asset="rtk-aarch64-unknown-linux-gnu.tar.gz" ;;
        *)
            # No published build: skipping is right, because there is nothing to fail on.
            echo "devbase: no RTK build for $(uname -m) — skipping" >&2
            return 0
            ;;
    esac

    if ! command -v curl >/dev/null 2>&1; then
        echo "devbase: ERROR: RTK needs curl (set commonPackages, or installRtk: false)" >&2
        return 1
    fi

    url="https://github.com/rtk-ai/rtk/releases/download/v${version}"
    tmp="$(mktemp -d)"

    # Everything below fails the build rather than warning. RTK is opted into explicitly,
    # and the failure mode of continuing without it is a hook that errors on every Bash
    # call — worse to debug than a build that stops and says why. A checksum mismatch in
    # particular must never be shrugged off. The escape hatch is `installRtk: false`.
    if ! curl -fsSL -o "${tmp}/${asset}" "${url}/${asset}"; then
        echo "devbase: ERROR: could not download ${url}/${asset}" >&2
        rm -rf "${tmp}"
        return 1
    fi
    if ! curl -fsSL -o "${tmp}/checksums.txt" "${url}/checksums.txt"; then
        echo "devbase: ERROR: could not download ${url}/checksums.txt" >&2
        rm -rf "${tmp}"
        return 1
    fi

    # Verifying against the release's own checksums.txt is what keeps a curl-fetched
    # third-party binary from being an unchecked supply-chain surface.
    expected="$(awk -v a="${asset}" '$2 == a { print $1 }' "${tmp}/checksums.txt")"
    if [ -z "${expected}" ]; then
        echo "devbase: ERROR: ${asset} is not listed in the release checksums" >&2
        rm -rf "${tmp}"
        return 1
    fi
    actual="$(sha256sum "${tmp}/${asset}" | cut -d' ' -f1)"
    if [ "${expected}" != "${actual}" ]; then
        echo "devbase: ERROR: checksum mismatch for ${asset}" >&2
        echo "  expected: ${expected}" >&2
        echo "  actual:   ${actual}" >&2
        rm -rf "${tmp}"
        return 1
    fi

    # The tarball contains a bare `rtk` at its root.
    tar -xzf "${tmp}/${asset}" -C /usr/local/bin rtk
    chmod 0755 /usr/local/bin/rtk
    rm -rf "${tmp}"
    echo "devbase: RTK ${version} installed ($(/usr/local/bin/rtk --version 2>/dev/null || echo 'version check failed'))"
}

if [ "${INSTALL_RTK}" = "true" ]; then
    echo "devbase: installing RTK ${RTK_VERSION}"
    install_rtk "${RTK_VERSION}"
fi

# --- shared library and entrypoints -----------------------------------------
echo "devbase: installing shared library to ${SHARE_DIR}"
mkdir -p "${SHARE_DIR}"
cp -R "${FEATURE_DIR}/lib/." "${SHARE_DIR}/"
chmod 0644 "${SHARE_DIR}"/*.sh

install -m 0755 "${FEATURE_DIR}/bin/devbase-post-create.sh" /usr/local/bin/devbase-post-create.sh
install -m 0755 "${FEATURE_DIR}/bin/devbase-post-attach.sh" /usr/local/bin/devbase-post-attach.sh
install -m 0755 "${FEATURE_DIR}/lib/env-info.sh" /usr/local/bin/devbase-env-info

# The option values are needed at post-create time, when the option environment
# variables are long gone. Recording them as a sourceable file is what makes the
# lifecycle scripts a pure function of the Feature's configuration.
cat >"${SHARE_DIR}/config.env" <<EOF
# Generated by the devbase Feature at image build time. Do not edit — change the
# Feature's options in devcontainer.json and rebuild instead.
DEVBASE_USER="${USERNAME}"
DEVBASE_USER_HOME="${USER_HOME}"
DEVBASE_INSTALL_PNPM="${INSTALL_PNPM}"
DEVBASE_GLOBAL_PACKAGES="${GLOBAL_PACKAGES}"
DEVBASE_ZSH_AUTOSUGGESTIONS="${ZSH_AUTOSUGGESTIONS}"
DEVBASE_HISTORY_PERSISTENCE="${HISTORY_PERSISTENCE}"
DEVBASE_GH_CREDENTIAL_HELPER="${GH_CREDENTIAL_HELPER}"
DEVBASE_ENV_INFO_BANNER="${ENV_INFO_BANNER}"
DEVBASE_INSTALL_PROJECT_DEPENDENCIES="${INSTALL_PROJECT_DEPENDENCIES}"
DEVBASE_AUTOLOAD_ENV_SCRIPT="${AUTOLOAD_ENV_SCRIPT}"
DEVBASE_INSTALL_RTK="${INSTALL_RTK}"
DEVBASE_RTK_VERSION="${RTK_VERSION}"
EOF
chmod 0644 "${SHARE_DIR}/config.env"

# --- user shell configuration ------------------------------------------------
# .zshrc and .czrc are owned by this Feature, which is the whole point: a repo
# that needs its own additions writes ~/.zshrc.local (sourced at the end) rather
# than forking the file, so the shared prompt cannot drift per repository.
echo "devbase: installing zsh and commitizen configuration"
install -m 0644 -o "${USERNAME}" -g "${USERNAME}" "${FEATURE_DIR}/config/.zshrc" "${USER_HOME}/.zshrc"
install -m 0644 -o "${USERNAME}" -g "${USERNAME}" "${FEATURE_DIR}/config/.czrc" "${USER_HOME}/.czrc"

ZSH_CUSTOM_DIR="${USER_HOME}/.oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM_DIR}/plugins"
chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/.oh-my-zsh" 2>/dev/null || true

if [ "${USERNAME}" != "root" ] && command -v zsh >/dev/null 2>&1; then
    usermod --shell "$(command -v zsh)" "${USERNAME}"
fi

echo "devbase: install complete"
