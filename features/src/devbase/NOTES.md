## The pnpm version

The container installs the pnpm your `package.json` declares — either field:

```jsonc
"devEngines": {
  "packageManager": { "name": "pnpm", "version": "^11.0.0", "onFail": "error" }
}
```

```jsonc
"packageManager": "pnpm@11.24.0"
```

These are the same two fields CI reads (`pnpm/action-setup`), read in the same order —
`devEngines.packageManager` first — and that is the whole point. Before this, the Node
dependency's `pnpmVersion: latest` decided it, so a container ran whichever pnpm was newest
on the day its image was built while the pipeline reviewing its lockfile ran the declared
one. Nothing announced the difference; a lockfile written by one and rejected by the other
is how you found out.

What counts as a declaration is narrow on purpose, and differs by field because the fields
differ:

- in `devEngines.packageManager`, a semver range such as `^11.0.0` — its normal shape. It
  is handed to npm, which resolves it to the newest matching release, exactly as
  `action-setup` does. An exact version there works too.
- in `packageManager`, an exact `pnpm@X.Y.Z` only, optionally with the `+sha512-...`
  integrity suffix, which is stripped before npm sees it. A range in **that** field is
  forbidden by specification, so honouring one would be guessing at what the repository
  failed to say.
- **not** an entry naming npm or yarn, in either field. That repository said nothing about
  pnpm, and inventing an answer from it would be the Feature choosing rather than reading.

A range agrees on less than a pin, and that is the trade it makes: your container and your
CI end up **inside the same range** rather than on an identical version, each resolving the
newest match on the day it installs. In exchange, neither has to be bumped when a patch
release lands. A container already inside the range is left alone rather than reinstalled.

Declare nothing and the pnpm already in the container stays put, untouched — `latest` is
installed only for a container that arrived with no pnpm at all. So adopting either field is
opt-in per repository, and a repository that has not yet adopted one sees no change.

**No option switches this off.** One would only give a repository a second place to say
which pnpm it wants, and the container-versus-CI disagreement back again. To choose a
version, declare it; to keep what you have, declare nothing.

npm remains the installation route, deliberately. corepack is not the alternative — Node
stopped bundling it at v25, and our engines policy spans `^24.15.0 || ^26.0.0`, so it is
absent from half of that range. The standalone installer is a pipe-to-shell with nothing to
verify it against. npm is already present, and it is the route the Node feature itself used
to put pnpm there, so this replaces that global in place rather than shadowing it from a
second prefix and leaving `PATH` order to decide the winner.

The step runs before dependency installation, so `pnpm install` uses the version you
declared rather than the one the image happened to ship.

### The npm floor

The neighbouring step reads `engines.npm` and raises npm to the major it names, because no
Node release bundles npm 12 and an explicit floor is the only way to get one. It acts on a
`>=` floor and nothing else:

```jsonc
"engines": { "npm": ">=12.0.0" }
```

`^12.0.0` is not a floor it can read, and a container whose npm stays behind because of it
now says so in the create log rather than skipping in silence.

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
