#!/usr/bin/env bash
#
# Runs actionlint over .github/workflows/.
#
# This is a local check rather than only a CI job because of a failure mode CI
# structurally cannot catch. An invalid workflow file never starts, so the actionlint job
# that would have reported the problem is itself one of the jobs that does not run — and
# GitHub surfaces the result as a run named after the file path, with no PR check
# attached, which is easy to read as unrelated noise. This repository pushed five commits
# with a completely dead Lint workflow (`join(needs.*.result, " ")`: a GitHub expression
# accepts only single-quoted strings) before it was spotted. `pnpm lint` catches that
# class of error before the push.
#
# CI runs this same script, so both use the identical pinned actionlint rather than CI
# using a floating third-party action and the working tree using whatever is on PATH.

set -euo pipefail

# Pinned deliberately: a floating version turns an upstream release into an unexplained
# red build here, which is the same reason the Prettier job stopped using `npx prettier@3`.
ACTIONLINT_VERSION="1.7.12"

CACHE_DIR="${PWD}/.cache/actionlint/${ACTIONLINT_VERSION}"

# resolve_actionlint — echo a usable actionlint path, downloading it if need be.
#
# A copy already on PATH wins, so a container or host that provides actionlint costs no
# download. Otherwise the pinned release is fetched once into the gitignored .cache/.
resolve_actionlint() {
    if command -v actionlint >/dev/null 2>&1; then
        command -v actionlint
        return 0
    fi
    if [ -x "${CACHE_DIR}/actionlint" ]; then
        printf '%s\n' "${CACHE_DIR}/actionlint"
        return 0
    fi

    local asset expected actual url tmp
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64 | Linux-amd64) asset="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" ;;
        Linux-aarch64 | Linux-arm64) asset="actionlint_${ACTIONLINT_VERSION}_linux_arm64.tar.gz" ;;
        Darwin-x86_64) asset="actionlint_${ACTIONLINT_VERSION}_darwin_amd64.tar.gz" ;;
        Darwin-arm64) asset="actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz" ;;
        *)
            echo "No pinned actionlint build for $(uname -s)-$(uname -m)." >&2
            echo "Install actionlint manually and re-run: https://github.com/rhysd/actionlint" >&2
            return 1
            ;;
    esac

    url="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}"
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN

    echo "Fetching actionlint ${ACTIONLINT_VERSION}..." >&2
    curl -fsSL -o "${tmp}/${asset}" "${url}/${asset}" || {
        echo "Could not download ${url}/${asset}" >&2
        return 1
    }
    curl -fsSL -o "${tmp}/checksums.txt" \
        "${url}/actionlint_${ACTIONLINT_VERSION}_checksums.txt" || {
        echo "Could not download the release checksums" >&2
        return 1
    }

    # Verified against the release's own checksums.txt, the same way the devbase Feature
    # treats the rtk download: an unverified curl-to-shell binary is a supply-chain hole
    # whether it runs in a container or on a laptop.
    expected="$(awk -v a="${asset}" '$2 == a { print $1 }' "${tmp}/checksums.txt")"
    if [ -z "${expected}" ]; then
        echo "${asset} is not listed in the release checksums" >&2
        return 1
    fi
    actual="$(sha256sum "${tmp}/${asset}" | cut -d' ' -f1)"
    if [ "${expected}" != "${actual}" ]; then
        echo "Checksum mismatch for ${asset}" >&2
        echo "  expected: ${expected}" >&2
        echo "  actual:   ${actual}" >&2
        return 1
    fi

    mkdir -p "${CACHE_DIR}"
    tar -xzf "${tmp}/${asset}" -C "${CACHE_DIR}" actionlint
    chmod 0755 "${CACHE_DIR}/actionlint"
    printf '%s\n' "${CACHE_DIR}/actionlint"
}

# Fatal rather than skipped when actionlint cannot be resolved. A lint step that passes
# because its tool is absent reports a success it never verified, which is precisely what
# this repository's standards forbid.
actionlint_bin="$(resolve_actionlint)"

"${actionlint_bin}" .github/workflows/*.yml
echo "Workflows OK."
