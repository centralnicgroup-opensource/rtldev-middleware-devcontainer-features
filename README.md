# rtldev-middleware-devcontainer-features

[![Test features](https://github.com/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/actions/workflows/test-features.yml/badge.svg)](https://github.com/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/actions/workflows/test-features.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Shared [devcontainer Features](https://containers.dev/implementors/features/) for RTLDEV
middleware repositories, published to `ghcr.io` and consumed by version rather than
copied.

| Feature                            | What it provides                                                                                                                         |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| [`devbase`](features/src/devbase/) | zsh with the team prompt, commitizen, pnpm, the `gh` credential helper, persistent shell history, dependency installation, attach banner |

## Quick start

Add one entry to your repository's `.devcontainer/devcontainer.json`:

```jsonc
"features": {
  "ghcr.io/devcontainers/features/node:2": { "version": "lts" },
  "ghcr.io/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/devbase:1": {}
}
```

You do not need to list `github-cli` or `claude-code`: `devbase` declares both in
`dependsOn`, so they are installed — and installed _before_ it — whether or not your
feature list mentions them. Listing them anyway is harmless but redundant. Language
runtimes are the opposite: `devbase` installs none, so `node` above is yours to keep.

Rebuild the container. That is the whole integration for a repository whose defaults
are fine.

Starting a repository from scratch? Copy a devcontainer frame from
[rtldev-middleware-template](https://github.com/centralnicgroup-opensource/rtldev-middleware-template/tree/main/examples/devcontainer)
instead — the frames come with this entry already in place.

**Contents**

- [The `devbase` Feature](#the-devbase-feature)
- [Why a Feature and not copied files](#why-a-feature-and-not-copied-files)
- [Options](#options)
- [Configuring the attach banner](#configuring-the-attach-banner)
- [Migrating a repository that already has a devcontainer](#migrating-a-repository-that-already-has-a-devcontainer)
- [Developing a Feature](#developing-a-feature)
- [Publishing](#publishing)
- [Keeping consumers up to date](#keeping-consumers-up-to-date)
- [Troubleshooting](#troubleshooting)

## The `devbase` Feature

`devbase` is the shared _behaviour_ half of our devcontainer setup. It installs **no
language runtime** — those stay in each repository's own feature list, and `devbase`
declares `installsAfter` for all of them so its setup steps run once the runtimes
exist.

Two non-runtime features it does _not_ leave to the consumer, declared in `dependsOn`
rather than `installsAfter`: **`github-cli`**, because the `gh` credential helper below
is useless without `gh`, and **`claude-code`**, because it is on every one of our
machines anyway. `installsAfter` is only a hint — it orders a feature that is already in
the list and does nothing when it is absent — so it could never have carried these two.

> **Keep listing the Node feature.** `claude-code`'s installer checks for `node` and, if it
> finds none, installs **Node 18 from nodesource** — a release that went EOL in April 2025.
> Its `installsAfter: node` means an explicit Node feature installs first and suppresses
> that fallback entirely, so a repository that lists `node` gets exactly the version it
> asked for. A repository that lists none silently gets the EOL 18, plus a `node` line in
> the attach banner and an `installPnpm` that succeeds where it used to report a missing
> toolchain. `devbase` still installs no runtime _itself_, but "no runtime unless you asked
> for one" is no longer true of the image it produces.
>
> Putting `node` in `devbase`'s own `dependsOn` looks like the fix and is not: the CLI
> installs both instances rather than deduplicating them when the options differ, and
> `devbase`'s runs **second**, so its `lts` overwrites a consumer's pin — a repository on
> Node 22 measurably ended up on 24. The `node_pinned` scenario guards against that
> returning. Instead, post-create detects the fallback and says so:
>
> ```
> => [ERROR] Node v18.20.8 came from claude-code's fallback, and 18.x is EOL
>    Add "ghcr.io/devcontainers/features/node:2": { "version": "lts" } to devcontainer.json
> ```
>
> It reports and moves on — installing a runtime is the one thing this Feature must not
> do, and the fix is one line in your `devcontainer.json`.

What it does, on first create and on every attach:

- **zsh** with the team prompt (git status segment, history search, autosuggestions)
- **commitizen** plus `cz-conventional-changelog`, and the matching `.czrc`
- **pnpm**, installed globally, with `PNPM_HOME` on `PATH`
- **`gh` credential helper** wired into the workspace's git config
- **Persistent shell history** across container rebuilds
- **Dependency installation** — `composer.json` via composer, `package.json` via pnpm,
  `.env` seeded from `.env.example`
- **An attach banner** reporting the container, language and dependency versions
- The shared **VS Code extension set** and the zsh terminal profile

## Why a Feature and not copied files

Because the container _frames_ differ across our repositories and the _behaviour_ does
not.

php-sdk and mcp-dis build a single container from a `Dockerfile`; whmcs-src runs its
dev container as one service in a four-service compose stack. No shared
`devcontainer.json` or `Dockerfile` spans those. What _was_ shared, before this
Feature existed, was the behaviour — and it had been copy-pasted into each repository
and then drifted: the `log_*`/`execute_with_indent`/`setup_pnpm` block existed in
three near-identical copies, `.zshrc` differed by 29 lines between two repositories
for no reason anyone chose, and the attach banner had been reinvented three times.

A Feature installs into a container built either way, is versioned, is pinned by digest
in each consumer's `devcontainer-lock.json`, and is picked up by Dependabot's
`devcontainers` ecosystem. Copied files are none of those things.

## Options

All optional; the defaults are what php-sdk and mcp-dis want.

| Option                       | Default                                              | What it does                                                                                                                                                                 |
| ---------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `commonPackages`             | `true`                                               | Installs `wget jq git zip unzip curl zsh shellcheck`. Turn off for a base image that already has them.                                                                       |
| `timezone`                   | `Europe/Berlin`                                      | Written to `/etc/localtime` and `/etc/timezone`. Empty string leaves the image alone.                                                                                        |
| `installPnpm`                | `true`                                               | Installs pnpm globally on first create. Needs a Node toolchain in the container.                                                                                             |
| `globalPackages`             | `commitizen@latest,cz-conventional-changelog@latest` | Comma-separated global pnpm installs. Empty installs nothing.                                                                                                                |
| `zshAutosuggestions`         | `true`                                               | Installs the zsh-autosuggestions plugin.                                                                                                                                     |
| `historyPersistence`         | `true`                                               | Symlinks `~/.zsh_history` to `/WSL_USER/.zsh_history`, creating the host file if it does not exist yet. Needs the host home mounted at `/WSL_USER`; skipped silently if not. |
| `ghCredentialHelper`         | `true`                                               | Points the workspace git credential helper at `gh auth git-credential`.                                                                                                      |
| `envInfoBanner`              | `true`                                               | Prints the toolchain banner on attach; also installs `devbase-env-info`.                                                                                                     |
| `installProjectDependencies` | `true`                                               | Installs from `composer.json` / `package.json` and seeds `.env` from `.env.example`.                                                                                         |
| `autoloadEnvScript`          | `true`                                               | Sources a workspace `env.sh` from `~/.zshenv` so new terminals inherit it.                                                                                                   |
| `installRtk`                 | `true`                                               | Installs RTK, the token-optimizing CLI proxy for Claude Code. Binary only — the hook stays in the mounted `~/.claude`.                                                       |
| `rtkVersion`                 | `0.45.0`                                             | RTK release to install, without the leading `v`. Checksum-verified against the release's `checksums.txt`.                                                                    |

A stack elaborate enough to own its own setup turns the generic part off:

```jsonc
"ghcr.io/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/devbase:1": {
  "installProjectDependencies": false,
  "timezone": "Europe/London"
}
```

Two things worth knowing about consuming it:

- **Pin the major (`:1`), not a patch.** A new `1.x` is picked up on the next rebuild,
  and the digest recorded in `devcontainer-lock.json` keeps the build reproducible in
  between.
- **Lifecycle order.** The Feature's `postCreateCommand` and `postAttachCommand` run
  _before_ the ones in your `devcontainer.json`, so your own hooks can rely on pnpm,
  the global packages and your dependencies already being installed. Put
  repository-specific setup there — never fork the Feature's scripts.

### RTK

[RTK](https://github.com/rtk-ai/rtk) is a token-optimizing CLI proxy for Claude Code: a
`PreToolUse` hook rewrites shell commands and filters their output, cutting a large share
of the tokens tool results otherwise consume.

It is installed here, rather than in each repository's `Dockerfile`, because of an
asymmetry (RSRMID-2933). The hook lives in `~/.claude/settings.json`, which every frame
bind-mounts from the host — so the _configuration_ is shared between host and container
while the _binary_ is not. A container without `rtk` fires a hook that exits `127` on
every Bash call: no savings, plus an error each time. Installing it centrally means the
binary follows the hook into every repository instead of being re-pasted into each one.

#### Binary here, hook in the repository

RTK needs two halves, and they are centralised in different places:

| Half                                | Lives in                                                     | Why there                                                                          |
| ----------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| the `rtk` binary                    | this Feature                                                 | it must exist inside the container, which is what the Feature builds               |
| the `PreToolUse` hook that calls it | the consuming repository's committed `.claude/settings.json` | it is configuration: reviewable, versioned, and identical for everyone on the team |

The hook is **not** written by this Feature, and that is deliberate. The only per-user
settings file in the container is `~/.claude/settings.json`, which every frame bind-mounts
from the host — writing it would edit the developer's own workstation configuration from
inside a container, and `rtk init -g` is never run for the same reason.

Leaving the hook to each developer's personal `~/.claude` was the other option, and it is
what the original arrangement did. It means RTK is active for whoever configured it by hand
and inert for everyone else, which is the team-wide-versus-personal problem restated rather
than solved. So the hook belongs in the repository, and
[rtldev-middleware-template](https://github.com/centralnicgroup-opensource/rtldev-middleware-template)
ships it in `.claude/settings.json`:

```json
{
  "type": "command",
  "command": "command -v rtk >/dev/null 2>&1 && exec rtk hook claude || exit 0",
  "statusMessage": "Optimizing command output (RTK)"
}
```

**The guard is the load-bearing part.** That one committed file is read on the host, in CI
and inside the container, but only the container is guaranteed to have `rtk`. Unguarded, it
would exit `127` on every Bash call made outside the container — the same defect as a
container with the hook but no binary, pointing the other way. Guarded, it activates
precisely where the Feature has installed the binary and is a silent no-op everywhere else.

> **Remove the personal copy.** If you already have `rtk hook claude` in your own
> `~/.claude/settings.json`, delete it once a repository carries the hook. Hooks from user
> and project settings both fire, and this one returns an `updatedInput` that rewrites the
> command — two hooks rewriting the same tool call is not a defined outcome.

#### Other deliberate choices

- **Only the binary.** `rtk init -g` is never run — it would rewrite the bind-mounted
  `~/.claude/settings.json`, which is shared with the host.
- **Pinned and checksum-verified.** The version is an option, and the download is checked
  against the release's own `checksums.txt`, so a curl-fetched third-party binary is not
  an unverified supply-chain surface.
- **Fails the build rather than warning.** RTK is opted into; continuing without it leaves
  a hook erroring on every Bash call, which is harder to diagnose than a build that stops
  and says why. Use `"installRtk": false` to opt out — per repository, or per developer via
  a local config.

Upstream publishes a `musl` build for `x86_64` but only a `gnu` build for `aarch64`, so
the two architectures do not share a naming pattern; `install.sh` maps `uname -m` to the
right asset and skips with a warning on an architecture with no published build.

The banner shows the installed version, which is where "hook configured but binary
missing" becomes visible.

## Configuring the attach banner

With no configuration the banner titles itself from the repository directory name and
shows each language group whose runtime is present. To override, add
`.devcontainer/env-info.conf` to the consuming repository:

```sh
TITLE="PHP-SDK - development environment"
SHOW_PHP=auto          # auto | true | false, likewise SHOW_NODE/GO/PYTHON/JAVA
PHP_EXTENSIONS="curl intl xdebug"
PHP_NOTE="(language-feature ceiling: 8.3)"
NODE_DEPS="@modelcontextprotocol/sdk express zod"
COMPOSER_DEPS=""
EXTRA_ROWS="Apache|apache2 -v|3
MariaDB|mariadb --version|"
```

The file is sourced as shell, so quote values containing spaces. `EXTRA_ROWS` takes one
`Label|command|field-index` per line, where the field index picks a whitespace-separated
field (1–3) and defaults to the whole first line of output.

Run `devbase-env-info` to see the result without reattaching.

Dependency versions are read from `node_modules/` and `vendor/`, never from the
manifest, so an empty row means "install has not run" rather than "unknown" — the
distinction that makes the banner worth reading.

## Migrating a repository that already has a devcontainer

Roughly 30 minutes per repository. Work on a branch and rebuild before you delete
anything.

1. **Add the Feature** to `devcontainer.json`'s `features` block.

2. **Delete what it replaces.** For a repository on the php-sdk/mcp-dis pattern, that
   is the whole shared `supporting_files/` tree:

   ```text
   .devcontainer/supporting_files/scripts/post-create.sh
   .devcontainer/supporting_files/scripts/post-attach.sh
   .devcontainer/supporting_files/scripts/env-info.sh
   .devcontainer/supporting_files/configuration/home/.zshrc
   .devcontainer/supporting_files/configuration/home/.czrc
   ```

   Keep anything genuinely repository-specific — php-sdk's `phpunit-wrapper.sh` and its
   `php/*.ini` files, for instance.

3. **Strip the Dockerfile** down to the base image plus whatever this repository
   actually needs. The `apt-get` block, timezone lines, `usermod --shell`, and the
   `COPY` of the zsh/commitizen config are all the Feature's job now.

4. **Repoint the lifecycle commands.** Delete `postCreateCommand` and
   `postAttachCommand` if they only ran the shared scripts. If the repository has its
   own setup, keep a `postCreateCommand` for _just_ that part.

5. **Generalise the workspace paths** (single-container frames only):

   ```jsonc
   "workspaceMount": "source=${localWorkspaceFolder},target=/usr/share/${localWorkspaceFolderBasename},type=bind,consistency=cached",
   "workspaceFolder": "/usr/share/${localWorkspaceFolderBasename}"
   ```

   Compose frames keep the literal path, because compose resolves its volumes
   independently and the two must agree.

6. **Move the banner content** from the deleted `env-info.sh` into
   `.devcontainer/env-info.conf`.

7. **Trim the extension list.** The Feature contributes the shared six; delete those
   from the repository's list and keep only the language-specific ones.

8. **Rebuild, then check:** the prompt renders, `devbase-env-info` reports the right
   versions, `cz --version` works, `git push` authenticates through `gh`, and shell
   history survived the rebuild.

9. **Keep a `~/.zshrc.local`** if you had personal shell additions in the old `.zshrc` —
   the Feature's copy is overwritten on rebuild by design, and `.zshrc.local` is sourced
   at the end and never touched.

## Developing a Feature

This repository's own devcontainer consumes `devbase` **from the registry**, exactly as a
consumer does — so this environment is a standing check that the published artifact
works. The working tree is exercised by the test suite instead:

```sh
pnpm features:test                        # default options + every scenario, real builds
pnpm features:test -- --filter minimal    # one scenario, while iterating
pnpm features:lint                        # shellcheck + metadata validation
pnpm lint:workflows                       # actionlint over .github/workflows
pnpm lint                                 # all of the above plus prettier
```

`pnpm lint` runs the same checks CI does, from the same scripts, so a green run locally
means a green run in CI. `lint:workflows` is the one that cannot be left to CI alone: an
invalid workflow file never starts, so the actionlint job that would report it is one of
the jobs that does not run. It downloads a pinned, checksum-verified actionlint into
`.cache/` on first use unless one is already on `PATH`.

`pnpm features:test` builds real containers straight from `features/src/`, so it is the
iteration loop — no publish, no copy, nothing to keep in sync. It needs a Docker daemon,
which is why the devcontainer includes docker-in-docker.

### Running the working-tree Feature in your own container

Occasionally you want your _own_ environment built from the branch. There is a second
config for that — `.devcontainer/local/devcontainer.json`, offered by VS Code's config
picker as "working tree":

```sh
pnpm devbase:local     # copy features/src/devbase -> .devcontainer/local/devbase
                       # then rebuild, choosing the "working tree" config
pnpm devbase:local:clean
```

Re-run `pnpm devbase:local` after each edit; forgetting is the one hazard of a copy, and
the reason this is the exception rather than the default.

The copy is not laziness — the devcontainer CLI leaves no better option, and all three
alternatives were measured:

| Reference                          | Result                                                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `"../features/src/devbase"`        | Refused: _"Local file path parse error. Resolved path must be a child of the `.devcontainer/` folder."_ |
| symlink at `.devcontainer/devbase` | Passes the path check, then fails the fetch step — the CLI needs a real directory                       |
| real copy inside `.devcontainer/`  | Works                                                                                                   |

Copying it in from `initializeCommand` does not help either: features are resolved
_before_ `initializeCommand` runs. The alternate config lives at `.devcontainer/local/`
precisely so its `"./devbase"` resolves inside `.devcontainer/` and is accepted.

### First publish

Until `devbase:1` has been published once there is nothing for the default config to pull.
Run the **Publish features (manual)** workflow once, or use `pnpm devbase:local`, before
building the default container on a fresh repository.

Layout:

Layout:

```text
features/
├── src/devbase/
│   ├── devcontainer-feature.json   # id, version, options, extensions, lifecycle hooks
│   ├── install.sh                  # build-time, as root, no workspace yet
│   ├── bin/
│   │   ├── devbase-post-create.sh  # first create, as the user, workspace mounted
│   │   └── devbase-post-attach.sh  # every attach
│   ├── lib/
│   │   ├── log.sh                  # logging + execute_with_indent
│   │   ├── setup.sh                # the shared setup steps
│   │   └── env-info.sh             # the banner (also installed as devbase-env-info)
│   └── config/{.zshrc,.czrc}       # user shell configuration
└── test/devbase/
    ├── test.sh                     # default options
    ├── scenarios.json              # non-default option combinations
    ├── minimal.sh                  # every option off
    └── node_project.sh             # alongside the Node feature
```

**The build-time / create-time split is the thing to get right.** `install.sh` runs as
root while the image builds, _before the workspace is mounted_ — so it can only do
image-level work. Anything that reads the repository (its manifests, its
`env-info.conf`) must go in `devbase-post-create.sh`.

Two conventions the shell code follows throughout, both learned from real breakage:

- **A missing prerequisite is reported and skipped, never fatal.** A container that
  comes up without pnpm is fixable from a terminal; one that refuses to come up is not.
- **zsh does not word-split unquoted parameter expansions.** `for x in ${LIST}` iterates
  once over the whole string under zsh while splitting correctly under bash. Route lists
  through the `words()` helper, which uses a command substitution — zsh splits those.

Run the tests:

```sh
pnpm features:test              # default options + every scenario
pnpm features:test -- --filter minimal   # one scenario, while iterating
pnpm features:lint              # shellcheck + metadata validation
pnpm lint                       # the above plus prettier and actionlint
```

Assert on **effects**, not on log lines, and check a new assertion against a deliberately
broken implementation before trusting it. A check that cannot fail is worse than no check:
it reports SUCCESS and sends the next person looking somewhere else.

## Publishing

Releases are **semantic-release**, driven by commit type — nobody edits `version` in
`devcontainer-feature.json` by hand. On a push to `main`,
[`release.yml`](.github/workflows/release.yml) works out the next version from the
commits, writes it into the Feature metadata, commits and tags it, and publishes to
`ghcr.io` in the same run.

| Commit                                  | Result for a consumer pinned to `:1`                  |
| --------------------------------------- | ----------------------------------------------------- |
| `fix(devbase): …`                       | patch — picked up on their next rebuild               |
| `feat(devbase): …`                      | minor — picked up on their next rebuild               |
| `feat(devbase): …` + `BREAKING CHANGE:` | major — **not** picked up until they change their pin |
| `ci` / `docs` / `chore` / `test` / …    | nothing published                                     |

Release and publish are deliberately one job: semantic-release commits the version bump
using `GITHUB_TOKEN`, and pushes made with that token do not trigger workflows — so a
separate publish workflow listening on `push` would never fire for exactly the commit
that matters.

Publishing is idempotent (a version already in the registry is skipped, not overwritten),
which is why the publish step needs no guard, and why
[`publish-features.yml`](.github/workflows/publish-features.yml) exists as a manual
escape hatch for the first publish and for re-publishing.

**The first publish needs the package made public** — `ghcr.io` packages default to
private, and a private Feature fails every consumer's build with a `401`. Set it under
this repository's _Packages_ → the `devbase` package → _Package settings_ → _Change
visibility_.

## Keeping consumers up to date

Add the `devcontainers` ecosystem to each consuming repository's
`.github/dependabot.yml`:

```yaml
- package-ecosystem: "devcontainers"
  directory: "/"
  schedule:
    interval: "weekly"
    day: "monday"
```

Dependabot then raises the digest bump as a PR when a new `1.x` is published. That is
the propagation story the copied-files approach never had.

## Troubleshooting

**`401 Unauthorized` pulling the Feature.** The `ghcr.io` package is still private —
see [Publishing](#publishing).

**The banner does not appear on attach.** It runs from `postAttachCommand`; check the
_Dev Containers_ output panel. Run `devbase-env-info` by hand to separate "the banner is
broken" from "the hook did not fire". A syntax error in `.devcontainer/env-info.conf` is
the usual cause, and the banner deliberately exits 0 regardless so it can never block an
attach.

**The prompt is plain, with no git segment.** `.zshrc` is only fully active for an
interactive, non-CI shell, and the theme needs Oh My Zsh in the image (the
`mcr.microsoft.com/devcontainers/base` images have it). A base image without it still
gets a working shell, just unthemed.

**Shell history did not survive a rebuild.** `historyPersistence` needs the host home
bind-mounted at `/WSL_USER`; check the frame's `mounts` (or the compose service's
volumes). The step is skipped silently when the mount is absent, because that is a
legitimate configuration. A host with no `~/.zsh_history` yet is _not_ that case — the
file is created and linked, so persistence starts on the first create rather than waiting
for a file nothing would ever write.

**`/WSL_USER is empty` in post-create.** The mount exists but its source path resolved to
nothing, and Docker created the missing source as an empty directory. On Windows hosts the
usual cause is the `${localEnv:HOME}${localEnv:USERPROFILE}` idiom used to name the host
home: it relies on exactly one of the two being set, and concatenates them into a
nonexistent path when both are. Fix the `source=` in the frame's `mounts` — the Feature
reports this rather than seeding a history file into a directory the host never sees.

**`pnpm: command not found` in post-create.** No Node toolchain in the container. Add
`ghcr.io/devcontainers/features/node:2` — `installsAfter` then guarantees it is installed
before the Feature's post-create runs.

**A change to the Feature had no effect.** Either `version` was not bumped (a duplicate
version is skipped at publish), or the consumer has not rebuilt. Rebuild without cache to
be sure: _Dev Containers: Rebuild Container Without Cache_.

**Personal shell customisations disappeared.** Expected — the Feature owns `~/.zshrc` and
overwrites it on rebuild, which is what stops the prompt drifting per repository. Put them
in `~/.zshrc.local`.

## Related repositories

- [rtldev-middleware-template](https://github.com/centralnicgroup-opensource/rtldev-middleware-template)
  — the template repository new projects are created from; it ships the devcontainer
  _frames_ that consume this Feature.
- [rtldev-middleware-shareable-workflows](https://github.com/centralnicgroup-opensource/rtldev-middleware-shareable-workflows)
  — the reusable GitHub Actions workflows those repositories delegate CI to.

## Maintainers

- **Kai Schwarz** — [KaiSchwarz-cnic](https://github.com/kaischwarz-cnic)
- **Asif Nawaz** — [AsifNawaz-cnic](https://github.com/AsifNawaz-cnic)

## License

MIT — see [LICENSE](LICENSE).
