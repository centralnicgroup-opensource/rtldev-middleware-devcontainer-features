
# RTLDEV Middleware dev base (devbase)

Shared devcontainer behaviour for RTLDEV middleware repositories: zsh with the team prompt, commitizen, pnpm, the gh credential helper, persistent shell history and an on-attach toolchain banner. Pulls in Node LTS (which also provides pnpm), the GitHub CLI and Claude Code as dependencies; other language toolchains stay in the consuming repository's own feature list.

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
| globalPackages | Comma-separated packages to install globally with pnpm on first create. Empty string installs nothing. | string | commitizen@latest,cz-conventional-changelog@latest |
| zshAutosuggestions | Install the zsh-autosuggestions plugin. Suggestions are driven by $HISTFILE, so they survive container rebuilds when historyPersistence is on. | boolean | true |
| historyPersistence | Symlink ~/.zsh_history to /WSL_USER/.zsh_history so shell history survives rebuilds. Needs the host home bind-mounted at /WSL_USER by the frame; skipped silently when that mount is absent, and always skipped in CI. | boolean | true |
| ghCredentialHelper | Point the workspace's git credential helper at `gh auth git-credential`, replacing the system-level VS Code helper. | boolean | true |
| sshCommitSigning | Repair SSH commit signing when the frame brings a host ~/.gitconfig whose user.signingkey names a key file the container does not have. Reads the forwarded ssh-agent and writes an inline `key::` signing key to the workspace's local git config. Never enables signing that was not already configured, and never writes to ~/.ssh or the host's gitconfig. | boolean | true |
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

## Overriding the VS Code settings

This Feature also contributes `customizations.vscode.settings` (shellcheck, the zsh
terminal profile, `npm.packageManager`, `files.exclude`); the full set is in
[devcontainer-feature.json](https://github.com/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/blob/main/features/src/devbase/devcontainer-feature.json). Your own `devcontainer.json` wins wherever the
two name the same key — but for object-valued settings that is a **replacement, not a
deep merge**. VS Code does not merge object values across settings scopes.

`files.exclude` is the one to watch, because the Feature ships an entry in it:

```jsonc
"files.exclude": { "**/node_modules": true }
```

If you declare your own `files.exclude`, restate the entries you want to keep:

```jsonc
"customizations": {
  "vscode": {
    "settings": {
      "files.exclude": {
        "**/node_modules": true, // restate, or you lose it
        "**/vendor": true
      }
    }
  }
}
```

Omitting `**/node_modules` from that object un-hides the directory just as surely as
setting it to `false` — which is the supported way to opt out on purpose:

```jsonc
"files.exclude": { "**/node_modules": false }
```

## SSH commit signing

If your frame bind-mounts the host `~/.gitconfig` — as the reference frame in this
repository does — it brings `commit.gpgsign=true`, `gpg.format=ssh` and a
`user.signingkey` naming a path under the **host's** `~/.ssh`. That path does not exist in
the container, so every commit fails with:

```
error: Couldn't load public key /home/you/.ssh/your_key: No such file or directory?
fatal: failed to write commit object
```

`sshCommitSigning` repairs this at create time using the ssh-agent VS Code forwards: it
writes an inline `key::<public key>` `user.signingkey` into the **workspace's** git config,
so the private half never enters the container and no file is written to `~/.ssh` — which
frames routinely mount from the host. The inline form resolves identically on the host, so
a bind-mounted `.git/config` stays correct on both sides.

It only ever repairs signing you already configured. It will not switch signing on, will
not touch a key file that exists, and will not overwrite an inline key. Without a forwarded
agent — CI, a plain `docker run` — it reports and skips rather than clearing your
configuration.

With more than one key in the agent it picks the one whose comment names your configured
key, and otherwise skips rather than guessing: an authentication key signs a commit
perfectly well and GitHub still rejects the signature, which is a confusing failure to
inherit from a container. Set `user.signingkey` to a `key::ssh-ed25519 AAAA...` literal
yourself if you want a specific key chosen.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/centralnicgroup-opensource/rtldev-middleware-devcontainer-features/blob/main/features/src/devbase/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
