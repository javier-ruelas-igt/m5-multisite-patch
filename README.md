# m5-multisite-patch
PowerShell script to make Media Manager HTML5 (M5) content builds compatible with multi-version IIS sub-path hosting (/v1/, /v2/, etc.) — no rebuild required.

## Script

[Fix-LibPaths.ps1](./Fix-LibPaths.ps1) patches an existing deployed build:

- Updates root-relative `/lib/` script sources in HTML files directly inside
  `reference_contents` and `shell` to use the selected version prefix.
- Adds the hosting base path to webworker library and reference-content URLs,
  including the Massachusetts and standard responsible-gaming workers.
- Applies targeted JavaScript and bundle replacements for direct funding,
  cashless navigation, shell reachability, patron navigation, attendant screens,
  URL maps, and application configuration.

The script uses literal search-and-replace patterns, so compatibility depends on
the deployed build matching those patterns. Already-patched patterns are skipped.

## Usage

Back up the deployed build first. Run PowerShell with permission to modify the
target files, from this repository's directory.

Preview changes before applying them:

```powershell
.\Fix-LibPaths.ps1 -Version v1 -WhatIf
```

The default root is `C:\inetpub\wwwroot`, so this targets
`C:\inetpub\wwwroot\v1`. To apply the changes, omit `-WhatIf` and answer `y`
at the confirmation prompt:

```powershell
.\Fix-LibPaths.ps1 -Version v1
```

Use a different deployment root:

```powershell
.\Fix-LibPaths.ps1 -Version v3 -RootPath "D:\sites\wwwroot" -WhatIf
```

To target a single HTML folder:

```powershell
.\Fix-LibPaths.ps1 -TargetDir "C:\inetpub\wwwroot\v1\reference_contents" -WhatIf
```

`-TargetDir` processes HTML files directly in that folder and JavaScript files in
its `js\webworks` subfolder only. It does not apply the targeted bundle patches
or process responsible-gaming worker folders; use `-Version` for the full patch.
This mode infers a version prefix from a `vN` path segment, falling back to
`../lib/` when no version can be detected.
