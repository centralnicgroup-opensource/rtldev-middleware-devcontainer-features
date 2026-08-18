# Project Instructions

> **This file is read in full on every task**, so it holds only rules needed on nearly
> every task — one imperative line each. Long-form rationale belongs in
> [README.md](README.md), which is also the consumer-facing documentation.

## Project Overview

This repository ships **devcontainer Features** for RTLDEV middleware repositories,
published as OCI artifacts to `ghcr.io`. There is currently one Feature, `devbase`,
which carries the shared devcontainer _behaviour_: zsh with the team prompt,
commitizen, pnpm, the `gh` credential helper, persistent shell history, dependency
installation and the on-attach toolchain banner.

- **Language:** shell (bash for build-time, zsh for the lifecycle hooks) plus JSON metadata
- **Published coordinate:** `ghcr.io/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/devbase:1`
- **Default branch:** `main`

There is **no application code here.** Every change is to shell, container metadata, or
documentation, and the blast radius is every consuming repository's development
environment.

## Architecture

- **`features/src/<id>/`** is one Feature. The directory name **must** equal the `id` in
  its `devcontainer-feature.json` — the id is what appears in the published coordinate,
  and a mismatch publishes under a name nobody references. CI checks this.
- **The build-time / create-time split is the load-bearing distinction:**
  - `install.sh` runs **as root, at image build time, before the workspace is mounted.**
    Image-level work only: packages, timezone, installing the shared library, writing the
    user's shell config.
  - `bin/devbase-post-create.sh` runs **once, as the remote user, with the workspace
    mounted.** Everything that reads the repository goes here.
  - `bin/devbase-post-attach.sh` runs **on every attach.**
  - Putting workspace-dependent work in `install.sh` fails in a way that looks like a
    missing file rather than a lifecycle mistake, so check this first when a step
    mysteriously does nothing.
- **`version` in `devcontainer-feature.json` is owned by semantic-release**, not by you.
  The release workflow derives it from commit types, writes it into the file and
  publishes in the same run. Never hand-edit it. Two properties of the replace plugin make
  that rule load-bearing rather than stylistic: it asserts `hasChanged: true`, so a
  manifest already carrying the version being released fails the release in `prepare`
  (which is how `1.0.0` blocked its own first release), and its `from` regex requires a
  closing quote straight after the patch number, so a prerelease suffix like
  `0.0.0-development` matches nothing and fails the same way. The pre-first-release seed is
  therefore bare **`0.0.0`** — below any real version, and it only ever appears before the
  first release, because every release commits the real one back.
- **Option values do not survive into the lifecycle scripts.** They arrive at
  `install.sh` as upper-cased environment variables and are recorded in
  `/usr/local/share/devbase/config.env`, which the lifecycle scripts source. A new option
  needs a line there or it silently has no effect at create time. `install.sh` also repeats
  the manifest default so it stays runnable standalone; only the manifest one affects a
  real build, so `pnpm features:validate` fails when the two disagree. Values written to
  `config.env` are escaped — it is sourced, so an option value is shell input.
- **A Feature's manifest is an allow-list, and anything outside it is dropped silently.**
  The CLI takes only `onCreate`/`updateContent`/`postCreate`/`postStart`/
  `postAttachCommand`, `init`, `privileged`, `capAdd`, `securityOpt`, `entrypoint`,
  `mounts` and `customizations` from each Feature. `name`,
  `workspaceMount`/`workspaceFolder`, `remoteUser`, `containerUser`, `remoteEnv`,
  `forwardPorts`, `shutdownAction`, `updateRemoteUserUID` and `initializeCommand` are read
  from the consuming repository's `devcontainer.json` only — put one here and it is not an
  error, it just vanishes. `remoteUser` **is** inherited, which is the confusing part, but
  from the base image's `devcontainer.metadata` label, authored from that image's own
  devcontainer.json; no Feature can set it, `common-utils` included — it creates the user,
  it does not declare `remoteUser`.
- **`mounts` is allowed but deliberately unused here.** It is static JSON with no option
  substitution, so `historyPersistence: false` could not switch off a `/WSL_USER` mount
  declared by this Feature — the opt-out would become a lie, the trap that cost
  `installPnpm` its existence once the node dependency brought its own pnpm. It would also be un-declinable for
  every consumer, and would bake the `${localEnv:HOME}${localEnv:USERPROFILE}` host-shape
  trick into the published artifact. The Feature looks for `/WSL_USER` and skips when it is
  absent instead — that absence is exactly what the report-and-skip rule exists for.
- **`installsAfter` orders, `dependsOn` installs.** `installsAfter` is only a hint: it
  sequences a feature the consumer already listed and does nothing when they did not, so
  it suits the language runtimes — devbase must not install those, only run after them. A
  new language runtime that post-create depends on goes there. `dependsOn` actually pulls
  the feature in, and carries `github-cli` (the credential helper is useless without
  `gh`) and `claude-code`. Adding to `dependsOn` puts software in every consumer's image
  with no option to decline, so it is a `feat(devbase)` and needs a test asserting the
  binary — never list the same feature in both. Check what a dependency drags in before
  adding one: `claude-code` installs its own Node when it finds none, and that fallback is
  **EOL 18 from nodesource** — which is why `node` is a dependency too, and why removing it
  would silently put every repository that does not list its own on a dead runtime.
- **`node` is in `dependsOn` at `lts`, and that makes devbase the owner of the Node
  version.** It rests on one CLI behaviour: two instances of a feature with _identical_
  options deduplicate, differing ones do not — both install and the dependency-expanded
  one runs second. Every repository pinning `lts` is therefore a no-op collapse
  (`node_project`), while a repository pinning anything else silently loses its pin
  (`node_pinned` asserts this so it stays visible). A repository that genuinely needs
  another major is a change here, not a local workaround — and changing devbase's pin
  changes the runtime under every consumer at once, so it is a `feat` at minimum.
- **The node feature ships `pnpmVersion: latest`, so pnpm exists in every container** and
  `installPnpm` was **removed** rather than left as a flag that decided nothing — normally a
  major, taken as part of a `feat` only because nothing consumes this Feature yet. Do not
  reintroduce it: `devbase_setup_pnpm` still runs, unconditionally, and is a no-op in any
  normal build. The `pnpm is missing` branch it guards is unreachable in a real build and is
  asserted in `test.sh` with an emptied `PATH`.
- **RTK is here rather than in each repository's Dockerfile** (RSRMID-2933) because the
  hook that calls it lives in the bind-mounted `~/.claude/settings.json` — shared with the
  host — while the binary is not, so a container without it fires a hook that exits 127 on
  every Bash call. Two invariants: **never run `rtk init -g`** (it would rewrite the
  host-shared `~/.claude`), and **keep the download checksum-verified** against the
  release's `checksums.txt`. Bumping `rtkVersion`'s default is a `feat(devbase)`.

## Coding Standards

- **ShellCheck at `--severity=warning`, and warnings are errors.** A defect here breaks
  every consuming repository's container.
- **A missing prerequisite is reported and skipped, never fatal.** A container that comes
  up without pnpm is fixable from a terminal; one that refuses to come up is not. Use
  `log_error` and `return 0`, not a non-zero exit.
- **zsh does not word-split unquoted parameter expansions.** `for x in ${LIST}` iterates
  once over the whole string under zsh while splitting correctly under bash. Route lists
  through `words()` in `env-info.sh`, which uses a command substitution — zsh does split
  those. This has bitten this code twice; assume it will again.
- **Never log success you have not verified.** A `|| true` that swallows a failure and
  still reports SUCCESS sends the next person looking in the wrong place. Check the
  effect, then log.
- **The banner must always exit 0.** It runs on every attach and must never be able to
  block one.
- **Honour `NO_COLOR` and a non-tty** in anything that writes to the terminal.
- Shell indentation is 4 spaces (`.editorconfig`); JSON and YAML are 2.

## Testing

- **`features/test/<id>/test.sh`** covers the default options; `scenarios.json` plus one
  `<scenario>.sh` per entry cover non-default combinations. Both run against a real
  container build — there is no unit-test shortcut, because the root/user and
  build/create splits only exist in a real build.
- **A new option needs a scenario**, or nothing proves the opt-out actually opts out.
- Assert on **effects**, not on log lines: that the symlink exists, that the helper is in
  the git config, that the dependency is installed — not that a message was printed.
  Recording an option value in `config.env` is not coverage of the step it configures.
- **Check a new assertion against a broken implementation before trusting it.** Break the
  thing it guards, confirm the suite goes red and that the failing check is the one that
  names the behaviour, then restore. A check that cannot fail is worse than no check: it
  reports SUCCESS and sends the next person looking somewhere else. Both defects this
  suite has actually shipped were of that shape.

```sh
pnpm features:test                        # default options + every scenario
pnpm features:test -- --filter minimal    # one scenario, while iterating
pnpm features:lint                        # shellcheck + metadata validation
pnpm lint:workflows                       # actionlint over .github/workflows
pnpm lint                                 # all of the above plus prettier
```

`pnpm lint` and CI run the same scripts, so local green means CI green. Do not put a check
inline in a workflow — it drifts from the pnpm script within a commit or two, which is how
the directory/id check ended up in CI only and `.husky/pre-commit` in the script only.

Running the tests needs a Docker daemon; this repository's devcontainer includes
docker-in-docker for exactly that.

## Dogfooding

This repository's own `.devcontainer/devcontainer.json` consumes `devbase` **from the
registry**, like any consumer, so this environment is a standing check that the published
artifact works.

- **The working tree is tested by `pnpm features:test`**, which builds real containers from
  `features/src/`. That is the iteration loop — not a rebuild of this container.
- **A local Feature path cannot point at `features/src/`.** The CLI refuses a path that
  resolves outside `.devcontainer/`, and fails the fetch on a symlink. The alternate config
  `.devcontainer/local/devcontainer.json` plus `pnpm devbase:local` (a gitignored copy) is
  the supported way to run the working-tree Feature in this container; the copy must be
  refreshed after every edit.
- `.devcontainer/env-info.conf` is also the reference example of that file: a change to the
  config format breaks here first.
- **This config deliberately has no `devcontainer-lock.json`.** Every feature here is
  pinned to a major tag, so each rebuild resolves the newest `1.x` — which is the point of
  a dogfooding check. A digest pin would freeze it on a stale artifact. A _consuming_
  repository wants the opposite and has a lock file for it.
- **Never make this frame rely on a guarantee that has not been released yet.** Because it
  consumes the registry, the frame is only ever as correct as the _published_ Feature. The
  moment `github-cli` was dropped from the feature list here, on the strength of a
  `dependsOn` that existed only in the working tree, every rebuild produced a container
  with no `gh` — and the failure surfaced as a `git push` dying in the credential helper,
  nowhere near the cause. So the working-tree change lands and releases **first**, and the
  frame stops listing the feature **after**. Removing something from this list is a bet
  that the registry already provides it.

## Build, CI & Policies

- **Releases are semantic-release, driven by commit type**, and the release workflow
  publishes in the same run. It has to: semantic-release commits the version bump with
  `GITHUB_TOKEN`, and pushes made with that token do not trigger workflows, so a separate
  publish workflow on `push` would never fire for the one commit that matters.
- **The commit type is the release decision.** `fix(devbase)` is a patch,
  `feat(devbase)` a minor, either plus `BREAKING CHANGE:` a major; `ci`/`docs`/`chore`/
  `test`/`refactor` publish nothing. Consumers pin `:1`, so a patch or minor reaches every
  repository on its next rebuild while a major does not — from the consumer's side, a
  removed or renamed option, or a changed default that alters what they already get, is a
  major.
- **Publishing is idempotent.** A version already in the registry is skipped rather than
  overwritten, which is why the publish step needs no guard.
- **CI is defined here, not delegated** to rtldev-middleware-shareable-workflows: the
  shared lint workflows are language-oriented and this repository ships shell and
  container metadata.
- **An invalid workflow file fails silently-ish, so lint workflows locally.** GitHub cannot
  start a workflow it cannot parse, so the `actionlint` job inside `lint.yml` can never
  report a syntax error in `lint.yml`. The run is named after the file path instead of the
  workflow, attaches no check to the PR, and reads like noise — `Lint` was dead for five
  commits that way. `pnpm lint` catches it before the push. A GitHub expression takes
  **single-quoted** strings only: `join(needs.*.result, ' ')`.
- **A gate over `needs.*.result` must test each result.** `grep -vw success` over the
  joined line passes whenever _any_ job succeeded, which is the opposite of what a gate
  is for.
- **Consumers pin `:1`** and Dependabot's `devcontainers` ecosystem moves the digest, so a
  breaking change inside `1.x` reaches every repository automatically. Treat the major as
  a real contract.

## Git Conventions

- **Commit messages:** Conventional Commits with **mandatory scope** —
  `<type>(<scope>): <summary>`. Never append a `Co-Authored-By:` trailer.
- **Scope** is normally the Feature id: `fix(devbase): …`, `feat(devbase): …`. Use `ci`,
  `docs`, `chore`, `build`, `test`, `refactor` for everything that is not the Feature's
  own behaviour.
- **The commit type is what ships**, so a behaviour change must use `fix` or `feat` —
  filing one under `chore` or `refactor` means it never reaches a consumer.
- **Breaking changes:** `BREAKING CHANGE: <summary>` in the commit body after a blank
  line, plus a migration note in the README.
- **Branch creation:** `git checkout main && git pull --ff-only` before `git checkout -b`.
- **Branch naming:** prefix with the Jira issue ID — `RSRMID-1234/short-description`.
- **Pull requests:** include the Jira issue link; add the PR URL as a comment on the Jira
  issue after opening.
- **Merging:** rebase-merge (`gh pr merge --rebase`).

## Important Paths

| Path                                             | Purpose                                                                                |
| ------------------------------------------------ | -------------------------------------------------------------------------------------- |
| `features/src/devbase/devcontainer-feature.json` | Options, extensions, `installsAfter`, lifecycle hooks; `version` is semantic-release's |
| `.releaserc.json`                                | Release config; its replace plugin writes the Feature version                          |
| `features/src/devbase/install.sh`                | Build-time, as root, no workspace                                                      |
| `features/src/devbase/lib/setup.sh`              | The shared setup steps every consumer gets                                             |
| `features/src/devbase/lib/env-info.sh`           | The attach banner; also installed as `devbase-env-info`                                |
| `/usr/local/share/devbase/config.env`            | Where option values live at create time (written by `install.sh`)                      |
| `.devcontainer/env-info.conf`                    | This repo's banner config, and the reference example of the format                     |
| `scripts/validate-features.sh`                   | Metadata checks, incl. manifest defaults vs. `install.sh` fallbacks                    |
| `scripts/lint-workflows.sh`                      | actionlint, run locally because CI cannot lint a workflow that will not start          |

## Atlassian / JIRA

Work is tracked in **Jira Cloud**, project `RSRMID`, component `DEVCONTAINER` — not
GitHub Issues.

- **Descriptions must be ADF** (Atlassian Document Format, JSON) — never markdown, which
  renders literal `\n`.
- **Log time before Done:** an issue will not stay in **Done** without a worklog —
  automation stamps `missing-time-spent` and reopens it. Sequence: (1) add worklog;
  (2) remove the label; (3) transition to Done. Ask when the amount is not obvious.

## Tool-Output Hygiene

Every tool result is spent context, so prefer the bounded tool over the shell dump. A
`PreToolUse` hook (`.claude/hooks/tool-output-hygiene.sh`) denies the three worst shapes
and names the replacement — if it fires, take the replacement rather than working around
it.

- **Searching:** the **Grep** tool with `head_limit`, plus
  `output_mode: "files_with_matches"` when only locations matter. An unbounded `grep -rn`
  is never acceptable.
- **Reading part of a file:** **Read** with `offset`/`limit`, never
  `sed -n '<from>,<to>p'` or a bare `cat`.
- **Container test output is enormous.** Bound it: `pnpm features:test 2>&1 | tail -40`,
  and use `--filter <scenario>` rather than running the whole suite to check one thing.
- **MCP calls:** batch field updates into a single call, and never re-fetch an issue you
  just mutated — the write response already confirms it.

## Model Routing

Opus decides, Sonnet implements. Definitions live in `.claude/agents/`.

- **Implementation** of an already-settled change goes to the `implementer` subagent
  (Sonnet). Trivial one-line edits stay inline.
- **Review** goes to the `reviewer` subagent (Opus, pinned so review quality never
  silently drops to a cheaper model), or stays in the main thread.
- **Fan-out reads** go to `Explore` or `general-purpose`, so file dumps land in the
  subagent's context instead of this one.

## Do NOT

- Add a language runtime to `devbase` — runtimes come from the devcontainers language
  features, and this Feature installs none directly (a Node does arrive transitively via
  the `claude-code` dependency; that is a known side effect, not licence to add more)
- Hand-edit `version` in `devcontainer-feature.json` — semantic-release owns it
- File a behaviour change under a non-releasing commit type, which silently ships nothing
- Repoint this repository's devcontainer **away from** the published coordinate — the
  registry reference in `.devcontainer/devcontainer.json` is the dogfooding check, and
  `pnpm devbase:local` plus the alternate config is the supported way to run the working
  tree instead
- Make a step fatal when the prerequisite is merely absent
- Log SUCCESS without verifying the effect
- Add `Co-Authored-By:` trailers to commit messages
