<#
.SYNOPSIS
    Build ViewTouch's Windows package (a .msi) into modern/dist/.

.DESCRIPTION
    The Windows counterpart to packaging/build-packages.sh. Needs, already
    on this machine: Visual Studio Build Tools (the C++ workload), CMake,
    Ninja, a Qt 6.12+ matching tools/qt-version (MSVC2022_64; -QtDir, or the
    VTM_QT environment variable, says where), and the WiX Toolset v3
    (candle.exe / light.exe on PATH, or its own WIX environment variable -
    its installer sets this). OpenSSL (its libcrypto DLL) is optional: found
    and bundled if -OpenSslDir (or VTM_OPENSSL_DIR) says where, encrypted
    backups just aren't in the package otherwise.

.PARAMETER QtDir
    The Qt install to build and package with, e.g. C:\Qt\6.12.0\msvc2022_64.
    Default: the VTM_QT environment variable, or C:\Qt\<tools/qt-version>\msvc2022_64.

.PARAMETER OpenSslDir
    Where to find libcrypto's DLL to bundle (its bin folder). Default: the
    VTM_OPENSSL_DIR environment variable, or Packaging.cmake's own guesses
    (a plain "Win64 OpenSSL" install).

.PARAMETER BuildDir
    Default: modern/build-package-windows.
#>
param(
    [string]$QtDir = $(if ($env:VTM_QT) { $env:VTM_QT } else { $null }),
    [string]$OpenSslDir = $env:VTM_OPENSSL_DIR,
    [string]$BuildDir
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$modern = Split-Path -Parent $here
$dist = Join-Path $modern "dist"

if (-not $QtDir) {
    $qtVersion = (Get-Content (Join-Path $here "..\tools\qt-version")).Trim()
    $QtDir = "C:\Qt\$qtVersion\msvc2022_64"
}
if (-not (Test-Path "$QtDir\lib\cmake\Qt6\Qt6Config.cmake")) {
    throw "No Qt at $QtDir (pass -QtDir, or set VTM_QT). See tools/qt-version for the version this project builds with."
}
if (-not $BuildDir) { $BuildDir = Join-Path $modern "build-package-windows" }

# vcvarsall.bat sets the MSVC compiler up in its own cmd.exe; this imports
# its environment into this PowerShell session (the same thing
# "Developer PowerShell for VS" does at launch).
function Import-VisualStudioEnvironment {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw "Visual Studio Build Tools not found (vswhere.exe missing)." }
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) { throw "No Visual Studio installation has the C++ build tools." }
    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
    # 2>nul inside cmd's own command line: vcvarsall.bat's harmless "vswhere.exe
    # not found" notice (it still works without it) would otherwise reach
    # PowerShell as a NativeCommandError under $ErrorActionPreference = Stop.
    $lines = cmd /c "`"$vcvars`" x64 2>nul && set"
    foreach ($line in $lines) {
        if ($line -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
}

# A shell open since before installing the WiX Toolset won't see its WIX
# environment variable (set at the machine level by its installer) until
# restarted; look it up directly rather than asking this process to.
if (-not $env:WIX) {
    $wix = [System.Environment]::GetEnvironmentVariable("WIX", "Machine")
    if ($wix) {
        $env:WIX = $wix
        $env:PATH = "$($wix)bin;$env:PATH"
    }
}
if (-not (Get-Command candle.exe -ErrorAction SilentlyContinue)) {
    throw "WiX Toolset v3 not found (candle.exe). Install it (winget install WiXToolset.WiXToolset) and, " +
          "if you just did, open a new shell."
}

Write-Host "Qt: $QtDir"
Import-VisualStudioEnvironment
if ($OpenSslDir) {
    $env:VTM_OPENSSL_DIR = $OpenSslDir
    Write-Host "OpenSSL: $OpenSslDir"
} else {
    Write-Host "OpenSSL: none given - Packaging.cmake will look in the usual places, or warn and leave it out."
}

cmake -S $modern -B $BuildDir -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QtDir" -DVTM_BUILD_TESTS=OFF
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed." }
cmake --build $BuildDir
if ($LASTEXITCODE -ne 0) { throw "cmake build failed." }

New-Item -ItemType Directory -Force -Path $dist | Out-Null
Push-Location $BuildDir
try {
    cpack -G WIX
    if ($LASTEXITCODE -ne 0) { throw "cpack failed." }
} finally {
    Pop-Location
}

# Named with the build number (vtmodern-...-b1628.msi), like the Linux
# packages: a store's computer tells screens that are behind from it.
$numberLine = Get-Content (Join-Path $BuildDir "generated\vtm_build_number.hh") |
    Where-Object { $_ -match "^#define VTM_BUILD_NUMBER (\d+)" }
$number = if ($numberLine -match "(\d+)") { $matches[1] } else { "0" }
Get-ChildItem (Join-Path $BuildDir "*.msi") | ForEach-Object {
    $named = Join-Path $dist ($_.BaseName + "-b$number" + $_.Extension)
    Move-Item -Force $_.FullName $named
    Write-Host "Built $named"
}
