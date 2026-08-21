## The container locale

This Feature sets `LANG=C.UTF-8` for the whole container, via `containerEnv` in its
manifest. The devcontainer CLI turns that into an `ENV` in the built image, so it reaches
every process — not just interactive shells.

It is here rather than in each repository's `Dockerfile` because the problem is not
repository-specific. Our base images ship no `LANG` at all, which leaves the C library in
the `C` locale with an **ASCII** charmap, and every tool that reads a source file inherits
it. Any file with an em-dash in a comment — which is most of ours — then decodes wrong, in
whichever tool notices first. A per-repository `containerEnv` fixes one repository at a
time; this fixes the ones that have not hit it yet.

`C.UTF-8` rather than `en_US.UTF-8` on purpose:

- it is built into glibc, so no `locales` package and no `locale-gen` at build time, and
  it works on a minimal base image
- its collation is codepoint order, the same as `C` — so `sort`, `[a-z]` ranges and
  anything else a shell script relies on behave exactly as they did before. Only the
  charmap changes.

**No option switches it off**, deliberately. `containerEnv` is static JSON with no option
substitution — the same property that keeps `mounts` unused here — so a flag could not
actually control it and would only be a lie. Override it in your own `devcontainer.json`
instead; the CLI emits the consumer's `containerEnv` after the feature layer, so yours
wins:

```jsonc
"containerEnv": { "LANG": "en_GB.UTF-8" }
```

Do check the locale exists in your image before naming a generated one. `setlocale` falls
back to `C` in silence when it does not, which looks exactly like the bug this fixes.

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
