<#
.SYNOPSIS
    The Qt that ViewTouch builds with and carries in its packages, from
    Qt's own binaries (download.qt.io) - the Windows counterpart to
    get-qt.sh, for the same reason: aqtinstall (and so actions built on
    it, like jurplel/install-qt-action) couldn't resolve this release's
    Windows repository layout as of when this was written (a real,
    reported gap, not a guess) - a flat qt6_<v>/Updates.xml everywhere
    else, nested one level deeper (qt6_<v>_msvc2022_64/Updates.xml) for
    Windows/MSVC on this release. A future Qt version bump may need this
    path adjusted again; it's one line, marked below.

.PARAMETER Version
    Default: tools/qt-version.

.PARAMETER Prefix
    Where Qt ends up (Prefix/lib/cmake/Qt6 is then what CMAKE_PREFIX_PATH
    points at). Default: C:\Qt\<version>\msvc2022_64.

.DESCRIPTION
    Fetches only what ViewTouch uses on Windows (Qt Base, Declarative,
    SVG, image formats, Lottie, Quick Timeline, Shader Tools), checks each
    archive against the SHA-1 Qt publishes beside it, and unpacks it with
    7-Zip (winget install 7zip.7zip, or set SEVENZIP). Already there:
    nothing to do.
#>
param(
    [string]$Version,
    [string]$Prefix
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Version) { $Version = (Get-Content (Join-Path $here "qt-version")).Trim() }
if (-not $Prefix) { $Prefix = "C:\Qt\$Version\msvc2022_64" }

if (Test-Path (Join-Path $Prefix "lib\cmake\Qt6\Qt6Config.cmake")) {
    Write-Host "Qt $Version already in $Prefix"
    exit 0
}

$sevenZip = $env:SEVENZIP
if (-not $sevenZip) {
    $candidate = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($candidate) { $sevenZip = $candidate.Source }
    elseif (Test-Path "C:\Program Files\7-Zip\7z.exe") { $sevenZip = "C:\Program Files\7-Zip\7z.exe" }
}
if (-not $sevenZip) { throw "Install 7-Zip first (winget install 7zip.7zip), or set SEVENZIP." }

$v = $Version -replace '\.', ''
# This nesting (qt6_<v>_msvc2022_64, not qt6_<v>) is the Windows/MSVC-only
# layout mentioned above - the one line a future Qt version may change.
$repo = "https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/qt6_$v/qt6_${v}_msvc2022_64"

$work = Join-Path $env:TEMP "get-qt-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $updatesXml = Join-Path $work "Updates.xml"
    try {
        Invoke-WebRequest -Uri "$repo/Updates.xml" -OutFile $updatesXml -UseBasicParsing
    } catch {
        throw "No Qt $Version for windows_x86/msvc2022_64 at download.qt.io."
    }

    # package name -> the archive name prefixes ViewTouch needs from it.
    $arch = "win64_msvc2022_64"
    $wanted = @{
        "qt.qt6.$v.$arch"                           = @("qtbase", "qtdeclarative", "qtsvg", "d3dcompiler_47", "opengl32sw")
        "qt.qt6.$v.addons.qtimageformats.$arch"      = @("qtimageformats")
        "qt.qt6.$v.addons.qtlottie.$arch"            = @("qtlottie")
        # Lottie plays its animations with Qt Quick Timeline (6.12 and later).
        "qt.qt6.$v.addons.qtquicktimeline.$arch"     = @("qtquicktimeline")
        # Its shader compiler (qsb): what Qt Quick's shaders are compiled with.
        "qt.qt6.$v.addons.qtshadertools.$arch"       = @("qtshadertools")
    }

    [xml]$updates = Get-Content $updatesXml
    $archives = @()
    foreach ($pkg in $updates.Updates.PackageUpdate) {
        if (-not $wanted.ContainsKey($pkg.Name)) { continue }
        $prefixes = $wanted[$pkg.Name]
        foreach ($a in ($pkg.DownloadableArchives -split ",")) {
            $a = $a.Trim()
            if (-not $a) { continue }
            $namePrefix = $a.Split("-")[0]
            if ($prefixes -contains $namePrefix) {
                $archives += [pscustomobject]@{ Name = $pkg.Name; Version = $pkg.Version; Archive = $a }
            }
        }
    }
    if ($archives.Count -eq 0) { throw "Qt $Version's index lists none of the parts ViewTouch needs." }

    $unpacked = Join-Path $work "unpacked"
    New-Item -ItemType Directory -Path $unpacked | Out-Null
    foreach ($a in $archives) {
        $url = "$repo/$($a.Name)/$($a.Version)$($a.Archive)"
        Write-Host "Qt ${Version}: $($a.Archive)"
        $archiveFile = Join-Path $work "a.7z"
        Invoke-WebRequest -Uri $url -OutFile $archiveFile -UseBasicParsing
        $shaContent = (Invoke-WebRequest -Uri "$url.sha1" -UseBasicParsing).Content
        $shaText = if ($shaContent -is [byte[]]) { [System.Text.Encoding]::ASCII.GetString($shaContent) } else { $shaContent }
        $want = $shaText.Trim().Substring(0, 40)
        $got = (Get-FileHash -Algorithm SHA1 $archiveFile).Hash.ToLower()
        if ($want -ne $got) { throw "$($a.Archive) doesn't match Qt's checksum: not used." }
        & $sevenZip x -y -bd -o"$unpacked" $archiveFile | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to extract $($a.Archive)." }
    }

    # Qt's archives unpack to lib/, bin/... (some releases' to VERSION/msvc2022_64/...).
    $top = $unpacked
    $nested = Join-Path $unpacked "$Version\msvc2022_64"
    if (Test-Path $nested) { $top = $nested }
    if (-not (Test-Path (Join-Path $top "lib\cmake\Qt6\Qt6Config.cmake"))) {
        throw "The archives didn't hold Qt's CMake files."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Prefix) | Out-Null
    if (Test-Path $Prefix) { Remove-Item -Recurse -Force $Prefix }
    Move-Item $top $Prefix
    # Qt's binaries say where they were built; this is where they are now.
    Set-Content -Path (Join-Path $Prefix "bin\qt.conf") -Value "[Paths]`nPrefix=.." -Encoding ascii
    Write-Host "Qt $Version in $Prefix"
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
