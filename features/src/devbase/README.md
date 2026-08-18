
# RTLDEV Middleware dev base (devbase)

Shared devcontainer behaviour for RTLDEV middleware repositories: zsh with the team prompt, commitizen, pnpm, the gh credential helper, persistent shell history and an on-attach toolchain banner. Language toolchains stay in the consuming repository's own feature list — this Feature deliberately installs no runtime.

## Example Usage

```json
"features": {
    "ghcr.io/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/devbase:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| commonPackages | Install the small package set every repository ends up needing anyway (wget, jq, git, zip, unzip, curl, shellcheck). Set false when the base image already provides them or the image must stay minimal. | boolean | true |
| timezone | Container timezone, written to /etc/localtime and /etc/timezone. Set to an empty string to leave the image's timezone untouched. | string | Europe/Berlin |
| installPnpm | Install pnpm globally on first create. Requires a Node toolchain in the container — list the Node feature too, or the step reports it as missing and moves on. | boolean | true |
| globalPackages | Comma-separated packages to install globally with pnpm on first create. Empty string installs nothing. | string | commitizen@latest,cz-conventional-changelog@latest |
| zshAutosuggestions | Install the zsh-autosuggestions plugin. Suggestions are driven by $HISTFILE, so they survive container rebuilds when historyPersistence is on. | boolean | true |
| historyPersistence | Symlink ~/.zsh_history to /WSL_USER/.zsh_history so shell history survives rebuilds. Needs the host home bind-mounted at /WSL_USER by the frame; skipped silently when that mount is absent, and always skipped in CI. | boolean | true |
| ghCredentialHelper | Point the workspace's git credential helper at `gh auth git-credential`, replacing the system-level VS Code helper. | boolean | true |
| envInfoBanner | Print the toolchain banner on every attach, configured by .devcontainer/env-info.conf in the workspace. Also installs `devbase-env-info` for running it by hand. | boolean | true |
| installProjectDependencies | On first create, install dependencies for whatever manifests exist in the workspace: composer.json via composer, package.json via pnpm, and seed .env from .env.example. Set false for repositories whose setup is non-standard enough to own the whole step. | boolean | true |
| autoloadEnvScript | When the workspace root has an env.sh, source it from ~/.zshenv so every new terminal inherits the workspace variables without a manual `source env.sh`. | boolean | true |
| installRtk | Install RTK (github.com/rtk-ai/rtk), the token-optimizing CLI proxy for Claude Code. Only the binary is installed — the PreToolUse hook that invokes it lives in the bind-mounted ~/.claude/settings.json, which this Feature never touches. Without the binary present, that hook exits 127 on every Bash call, which is why this defaults to on. | boolean | true |
| rtkVersion | RTK release to install, without the leading 'v'. Pinned rather than tracking latest, and the download is checksum-verified against the release's checksums.txt. | string | 0.45.0 |

## Customizations

### VS Code Extensions

- `github.vscode-github-actions`
- `github.vscode-pull-request-github`
- `ms-vscode-remote.remote-containers`
- `ms-azuretools.vscode-containers`
- `anthropic.claude-code`
- `anthropic.claude-vscode`
- `timonwong.shellcheck`
- `foxundermoon.shell-format`
- `redhat.vscode-yaml`



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/blob/main/features/src/devbase/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
