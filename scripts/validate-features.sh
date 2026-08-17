#!/usr/bin/env bash
#
# Validates every Feature's metadata before it can reach the registry.
#
# Run by `pnpm features:validate` and by the "Feature metadata" job in lint.yml. It
# lives in a file rather than inline in the workflow so both run the same checks: the
# workflow copy had grown a directory/id check that the package.json script never had,
# so `pnpm lint` passed on a mismatch CI would reject.
#
# Three things are checked:
#
#   1. The keys the publisher requires are present.
#   2. The directory name equals the id, because the directory name is what appears in
#      the published coordinate — a mismatch publishes under a name nobody references.
#   3. install.sh's fallback for each option equals the manifest's default. This is the
#      one invariant nothing else can catch: install.sh repeats every default so it
#      stays runnable standalone (which is how features/test drives it), but only the
#      manifest default has any effect in a real build. A divergence is therefore
#      invisible in CI and in production, and only shows up as a test that passes
#      against a default the Feature does not actually ship.
#
# No `set -e`: every Feature and every option is checked before exiting, so one
# mismatch does not hide the next.

set -uo pipefail

# Deliberately not named `status`: that identifier is read-only in zsh, and shell in
# this repository gets run under both shells often enough not to plant the landmine.
failed=0

# fail <file> <message> — record a failure, annotated so GitHub Actions files it against
# the offending line.
fail() {
    printf '::error file=%s::%s\n' "${1}" "${2}" >&2
    failed=1
}

shopt -s nullglob
manifests=(features/src/*/devcontainer-feature.json)
if [ "${#manifests[@]}" -eq 0 ]; then
    echo "No features found under features/src/ — nothing to validate." >&2
    exit 1
fi

for manifest in "${manifests[@]}"; do
    echo "Checking ${manifest}"
    feature_dir="$(dirname "${manifest}")"

    jq -e '.id and .version and .name and .description' "${manifest}" >/dev/null ||
        fail "${manifest}" "missing one of id/version/name/description"

    dir="$(basename "${feature_dir}")"
    id="$(jq -r '.id // empty' "${manifest}")"
    if [ "${dir}" != "${id}" ]; then
        fail "${manifest}" "id '${id}' does not match directory '${dir}'"
    fi

    install_script="${feature_dir}/install.sh"
    if [ ! -f "${install_script}" ]; then
        fail "${feature_dir}" "no install.sh"
        continue
    fi

    # Option ids reach install.sh as upper-cased environment variables, so the option
    # `commonPackages` is read as ${COMMONPACKAGES:-true} and its fallback is what has
    # to match the manifest.
    #
    # Process substitution rather than a pipe: a pipe would run the loop in a subshell
    # and every `fail` inside it would be discarded, so the check would always pass.
    while IFS=$'\t' read -r option default; do
        [ -n "${option}" ] || continue
        var="$(printf '%s' "${option}" | tr '[:lower:]' '[:upper:]')"

        # Matches both ${VAR:-default} and ${VAR-default}. The second form is what an
        # option whose *empty* value is a meaningful choice has to use — timezone and
        # globalPackages both rely on it — so a check that only understood `:-` would
        # report those two as missing.
        expansion="$(grep -o "\${${var}:\{0,1\}-[^}]*}" "${install_script}" | head -1)"
        if [ -z "${expansion}" ]; then
            fail "${install_script}" \
                "option '${option}' is declared in ${manifest} but never read as \${${var}}"
            continue
        fi

        prefix="\${${var}"
        fallback="${expansion#"${prefix}"}" # ":-true}" or "-Europe/Berlin}"
        fallback="${fallback#:}"
        fallback="${fallback#-}"
        fallback="${fallback%\}}"

        if [ "${fallback}" != "${default}" ]; then
            fail "${install_script}" \
                "option '${option}': ${manifest} defaults to '${default}' but install.sh falls back to '${fallback}'"
        fi
    done < <(jq -r '.options // {} | to_entries[] | "\(.key)\t\(.value.default)"' "${manifest}")
done

if [ "${failed}" -ne 0 ]; then
    echo "Feature metadata validation failed." >&2
    exit 1
fi
echo "Feature metadata OK."
