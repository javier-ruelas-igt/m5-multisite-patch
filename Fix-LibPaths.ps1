<#
.SYNOPSIS
    Makes a Media Manager HTML5 build compatible with multi-version IIS sub-path hosting (/v1/, /v2/, etc.).

.DESCRIPTION
    Three categories of fixes are applied in a single pass:

    1. HTML files in reference_contents\ and shell\
       src="/lib/...  ->  src="../lib/...
       (covers all reference content screens + shell/index.html, shell/indexHoriz.html)

    2. Web worker JS files in reference_contents\js\webworks\
       Injects:  const _base = location.pathname.replace(/\/reference_contents\/.*$/, '');
       Replaces: ${location.origin}/lib/             ->  ${location.origin}${_base}/lib/
                 ${location.origin}/reference_contents/  ->  ${location.origin}${_base}/reference_contents/

    The script is idempotent: files already patched are skipped automatically.

.PARAMETER Version
    The site version folder to target, e.g. v1, v2, v3.
    Processes reference_contents\, shell\, and reference_contents\js\webworks\ automatically.

.PARAMETER RootPath
    The wwwroot base path. Defaults to C:\inetpub\wwwroot.

.PARAMETER TargetDir
    Override: point directly at a reference_contents folder (or any HTML folder).
    Webworkers are also fixed if a js\webworks\ subfolder exists inside TargetDir.

.PARAMETER WhatIf
    Preview all changes without writing any files.

.EXAMPLE
    .\Fix-LibPaths.ps1 -Version v1
    .\Fix-LibPaths.ps1 -Version v2 -WhatIf
    .\Fix-LibPaths.ps1 -Version v3 -RootPath "D:\sites\wwwroot"
    .\Fix-LibPaths.ps1 -TargetDir "C:\inetpub\wwwroot\v1\reference_contents"
#>

param(
    [Parameter(Mandatory = $true, ParameterSetName = "ByVersion")]
    [string]$Version,

    [Parameter(ParameterSetName = "ByVersion")]
    [string]$RootPath = "C:\inetpub\wwwroot",

    [Parameter(Mandatory = $true, ParameterSetName = "ByPath")]
    [string]$TargetDir,

    [switch]$WhatIf
)

# -------------------------------------------------------------------------
# Resolve target directories
# -------------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq "ByPath") {
    $htmlDirs = @($TargetDir)
    $wwDirs   = @((Join-Path $TargetDir "js\webworks"))
} else {
    $htmlDirs = @(
        (Join-Path $RootPath "$Version\reference_contents"),
        (Join-Path $RootPath "$Version\shell")
    )
    $wwDirs = @(
        (Join-Path $RootPath "$Version\reference_contents\js\webworks"),
        (Join-Path $RootPath "$Version\reference_contents\responsible_gaming\massachusetts\js\worker"),
        (Join-Path $RootPath "$Version\reference_contents\responsible_gaming\standard\js\worker")
    )
}
# Keep $wwDir as a display-friendly summary label
$wwDir = if ($PSCmdlet.ParameterSetName -eq "ByPath") { $wwDirs[0] } else { Join-Path $RootPath "$Version\reference_contents\...(webworks + rg workers)" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Fix-LibPaths.ps1" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
if ($PSCmdlet.ParameterSetName -eq "ByVersion") {
    Write-Host "  Version    : $Version"
    Write-Host "  Root path  : $RootPath"
}
Write-Host "  HTML dirs  :"
foreach ($d in $htmlDirs) { Write-Host "    $d" }
Write-Host "  Worker dirs:"
foreach ($d in $wwDirs) { Write-Host "    $d" }
Write-Host "  Mode       : $(if ($WhatIf) { 'DRY RUN (no files will be written)' } else { 'LIVE' })"
Write-Host ""

# -------------------------------------------------------------------------
# Task A — HTML files: src="/lib/  ->  src="/vN/lib/  (absolute, version-specific)
# -------------------------------------------------------------------------
$htmlSearch  = 'src="/lib/'
# Derive the version prefix for absolute path replacement:
#   ByVersion mode: use $Version directly (e.g. v1)
#   ByPath mode:    attempt to extract vN segment from the TargetDir path
if ($PSCmdlet.ParameterSetName -eq "ByVersion") {
    $versionPrefix = $Version
} else {
    # Extract the last vN segment from the path (e.g. ...\v1\reference_contents -> v1)
    if ($TargetDir -match '[\\/](v\d+)[\\/]') {
        $versionPrefix = $Matches[1]
    } else {
        $versionPrefix = $null
        Write-Host "WARNING: Could not detect version prefix from TargetDir. HTML src replacement will use ../lib/ fallback." -ForegroundColor Yellow
    }
}
$htmlReplace = if ($versionPrefix) { "src=`"/$versionPrefix/lib/" } else { 'src="../lib/' }

$htmlAffected = @()
foreach ($dir in $htmlDirs) {
    if (-not (Test-Path $dir)) {
        Write-Host "WARNING: HTML dir not found, skipping: $dir" -ForegroundColor Yellow
        continue
    }
    foreach ($file in Get-ChildItem -Path $dir -Filter "*.html") {
        $content = Get-Content $file.FullName -Raw
        if ($content.Contains($htmlSearch)) {
            $htmlAffected += $file
        }
    }
}

# -------------------------------------------------------------------------
# Task B — Webworker JS files: inject _base + fix origin-relative paths
# Covers: js\webworks\*.js  +  responsible_gaming\*\js\worker\*.js
# -------------------------------------------------------------------------
$wwOldLib = '${location.origin}/lib/'
$wwNewLib = '${location.origin}${_base}/lib/'
$wwOldRef = '${location.origin}/reference_contents/'
$wwNewRef = '${location.origin}${_base}/reference_contents/'
$wwBaseDef = "const _base = location.pathname.replace(/\/reference_contents\/.*${'$'}/, '');"

$wwAffected = @()
foreach ($dir in $wwDirs) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($file in Get-ChildItem -Path $dir -Filter "*.js") {
        $content = Get-Content $file.FullName -Raw
        # Already patched if _base is present and old patterns are gone
        if (-not $content.Contains($wwOldLib) -and -not $content.Contains($wwOldRef)) { continue }
        $wwAffected += $file
    }
}

# -------------------------------------------------------------------------
# Task C — Targeted bundle/JS patches (search & replace in specific files)
#           String literals survive minification — safe to patch directly.
#           Only runs in -Version mode (file paths are predictable).
# -------------------------------------------------------------------------
$patchAffected = @()
if ($PSCmdlet.ParameterSetName -eq "ByVersion") {
    $patches = @(
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\reference_contents\js\idle_screen.skin.js"
            Description = 'idle_screen.skin.js goToDf: origin + /reference_contents/direct_funding.html'
            Search      = 'IGTMediaElements.loadContent(`${window.location.origin}/reference_contents/direct_funding.html`)'
            Replace     = 'IGTMediaElements.loadContent(`${window.location.origin}${window.location.pathname.replace(/\/reference_contents\/.*$/, "")}/reference_contents/direct_funding.html`)'
        },
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\reference_contents\js\banner.skin.js"
            Description = 'banner.skin.js: origin + /reference_contents/cashless.html#/'
            Search      = 'IGTMediaElements.loadContent(`${window.location.origin}/reference_contents/cashless.html#/`)'
            Replace     = 'IGTMediaElements.loadContent(`${window.location.origin}${window.location.pathname.replace(/\/reference_contents\/.*$/, "")}/reference_contents/cashless.html#/`)'
        },
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\lib\shell-core-logic\dist\ShellCoreLogic.bundle.js"
            Description = 'NgxComm.hostReachable: /shell/launcher.html absolute path'
            Search      = '"/shell/launcher.html?rand="'
            Replace     = 'window.location.pathname.replace(/\/shell\/.*$/,"")+"/shell/launcher.html?rand="'
            SkipIf      = 'pathname.replace(/\/shell\/.*$/'
        },
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\reference_contents\js\model\all_in_one.model.js"
            Description = 'navToPatronView: /patron/index.html absolute path'
            Search      = 'location.origin+"/patron/index.html"'
            Replace     = 'location.origin+window.location.pathname.replace(/\/reference_contents\/.*$/,"")+"/patron/index.html"'
        },
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\reference_contents\js\model\all_in_one.model.js"
            Description = 'navToPatronView: /patron/indexHoriz.html absolute path'
            Search      = 'location.origin+"/patron/indexHoriz.html"'
            Replace     = 'location.origin+window.location.pathname.replace(/\/reference_contents\/.*$/,"")+"/patron/indexHoriz.html"'
        },
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\reference_contents\js\attendant_cardin_patch.js"
            Description = 'attendant_cardin_patch: origin + screenIdMap URL missing base path'
            Search      = 'IGTMediaElements.loadContent(`${window.location.origin}/${attendantScreenURL}`)'
            Replace     = 'IGTMediaElements.loadContent(`${window.location.origin}${window.location.pathname.replace(/\/reference_contents\/.*$/, "")}/${attendantScreenURL}`)'
        },
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\reference_contents\js\model\all_in_one.model.js"
            Description = 'store.js getURLMaps: urlMapVertical.json built with only version prefix, missing shell/ segment'
            Search      = 'n="/"+n[1]+"/",e=a.k.location.protocol+"//"+a.k.location.host+n+e,console.log("fetching urlmap'
            Replace     = 'n=window.top.location.pathname.replace(/[^\/]+$/,""),e=a.k.location.protocol+"//"+a.k.location.host+n+e,console.log("fetching urlmap'
        },
        [PSCustomObject]@{
            File        = Join-Path $RootPath "$Version\reference_contents\js\model\all_in_one.model.js"
            Description = 'store.js getAppConfig: appconfig.json built with slice(0,2), missing reference_contents/ segment'
            Search      = 'slice(0,2).join("/"),n=window.location.protocol+"//"+window.location.host+r+"/appconfig.json"'
            Replace     = 'join("/"),n=window.location.protocol+"//"+window.location.host+r+"/appconfig.json"'
        }
    )

    foreach ($patch in $patches) {
        if (-not (Test-Path $patch.File)) {
            Write-Host "WARNING: Patch target not found, skipping: $($patch.File)" -ForegroundColor Yellow
            continue
        }
        $content = Get-Content $patch.File -Raw
        # SkipIf: some replacements leave the Search string present — use SkipIf to detect already-patched
        $alreadyPatched = $patch.SkipIf -and $content.Contains($patch.SkipIf)
        if (-not $alreadyPatched -and $content.Contains($patch.Search)) {
            $patchAffected += $patch
        }
    }
}

# -------------------------------------------------------------------------
# Preview
# -------------------------------------------------------------------------
$totalAffected = $htmlAffected.Count + $wwAffected.Count + $patchAffected.Count

if ($totalAffected -eq 0) {
    Write-Host "All files are already patched. Nothing to do." -ForegroundColor Green
    exit 0
}

if ($htmlAffected.Count -gt 0) {
    Write-Host "--- HTML files  [src=""/lib/""  ->  $htmlReplace...] ---" -ForegroundColor Yellow
    $htmlAffected | Group-Object { $_.DirectoryName } | ForEach-Object {
        Write-Host "  [$($_.Name)]"
        foreach ($f in $_.Group) {
            $n = ([regex]::Matches((Get-Content $f.FullName -Raw), [regex]::Escape($htmlSearch))).Count
            Write-Host "    $($f.Name)  ($n occurrence$(if ($n -ne 1){'s'}))"
        }
    }
    Write-Host ""
}

if ($wwAffected.Count -gt 0) {
    Write-Host "--- Webworker JS files  [inject _base + fix origin paths] ---" -ForegroundColor Yellow
    $wwAffected | Group-Object { $_.DirectoryName } | ForEach-Object {
        Write-Host "  [$($_.Name)]"
        foreach ($f in $_.Group) {
            $content = Get-Content $f.FullName -Raw
            $changes = @()
            if ($content.Contains($wwOldLib)) { $changes += 'origin}/lib/' }
            if ($content.Contains($wwOldRef)) { $changes += 'origin}/reference_contents/' }
            Write-Host "    $($f.Name)  ($($changes -join ', '))"
        }
    }
    Write-Host ""
}

if ($patchAffected.Count -gt 0) {
    Write-Host "--- Bundle/JS patches  [targeted search & replace] ---" -ForegroundColor Yellow
    $patchAffected | Group-Object File | ForEach-Object {
        Write-Host "  [$($_.Name)]"
        foreach ($p in $_.Group) { Write-Host "    $($p.Description)" }
    }
    Write-Host ""
}

Write-Host "Total: $totalAffected file(s)/patch(es) to modify" -ForegroundColor White

if ($WhatIf) {
    Write-Host ""
    Write-Host "DRY RUN complete. No files were modified. Remove -WhatIf to apply." -ForegroundColor Cyan
    exit 0
}

# -------------------------------------------------------------------------
# Confirm
# -------------------------------------------------------------------------
Write-Host ""
$confirm = Read-Host "Apply changes to $totalAffected file(s)? [y/N]"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Aborted. No files were modified." -ForegroundColor Yellow
    exit 0
}

# -------------------------------------------------------------------------
# Apply Task A — HTML
# -------------------------------------------------------------------------
$successCount = 0
$errorCount   = 0

foreach ($file in $htmlAffected) {
    try {
        $content = Get-Content $file.FullName -Raw
        $updated = $content.Replace($htmlSearch, $htmlReplace)
        Set-Content -Path $file.FullName -Value $updated -NoNewline
        Write-Host "  [OK] $($file.Name)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "  [FAIL] $($file.Name): $_" -ForegroundColor Red
        $errorCount++
    }
}

# -------------------------------------------------------------------------
# Apply Task B — Webworker JS
# -------------------------------------------------------------------------
foreach ($file in $wwAffected) {
    try {
        $content = Get-Content $file.FullName -Raw

        # Inject _base definition at the very top (only if not already present)
        if (-not $content.Contains('const _base = location.pathname')) {
            $content = $wwBaseDef + "`n" + $content
        }

        # Replace origin-relative paths
        $content = $content.Replace($wwOldLib, $wwNewLib)
        $content = $content.Replace($wwOldRef, $wwNewRef)

        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "  [OK] $($file.Name)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "  [FAIL] $($file.Name): $_" -ForegroundColor Red
        $errorCount++
    }
}

# -------------------------------------------------------------------------
# Apply Task C - Bundle/JS patches
# -------------------------------------------------------------------------
foreach ($patch in $patchAffected) {
    try {
        $content = Get-Content $patch.File -Raw
        $updated = $content.Replace($patch.Search, $patch.Replace)
        Set-Content -Path $patch.File -Value $updated -NoNewline
        Write-Host "  [OK] $(Split-Path $patch.File -Leaf) - $($patch.Description)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "  [FAIL] $(Split-Path $patch.File -Leaf) - $($patch.Description): $_" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host ""
Write-Host "Done. $successCount file(s) updated, $errorCount error(s)." -ForegroundColor Cyan
