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
