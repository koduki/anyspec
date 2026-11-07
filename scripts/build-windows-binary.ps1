<# 
.SYNOPSIS
    Build anyspec Spinel binary on Windows
    
.DESCRIPTION
    This script builds a native Windows executable (.exe) for anyspec using
    Spinel AOT compiler. Requires MSYS2 or RubyInstaller Devkit.
    
.PARAMETER SpinelPath
    Path to existing Spinel installation (optional). If not provided,
    the script will guide you to install Spinel first.
    
.PARAMETER OutputDir
    Output directory for the binary (default: dist)
    
.EXAMPLE
    .\build-windows-binary.ps1
    
.EXAMPLE
    .\build-windows-binary.ps1 -OutputDir C:\output
    
.NOTES
    Requirements:
    - Windows 10/11 or Windows Server 2019+
    - MSYS2 (https://www.msys2.org/) with UCRT64 toolchain
      OR RubyInstaller with Devkit (https://rubyinstaller.org/)
    - Spinel compiler (built from https://github.com/matz/spinel)
    
    The resulting binary requires 'oci' CLI to be installed separately.
#>

param(
    [string]$SpinelPath = "",
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Error-Exit {
    param([string]$Message)
    Write-Host "`nError: $Message" -ForegroundColor Red
    exit 1
}

function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

function Find-MSYS2 {
    # Standalone MSYS2 locations
    $locations = @(
        "$env:SystemDrive\msys64",
        "$env:ProgramFiles\msys64",
        "${env:ProgramFiles(x86)}\msys64"
    )
    
    # Check standalone MSYS2 first
    foreach ($loc in $locations) {
        if (Test-Path "$loc\usr\bin\bash.exe") {
            return @{ Path = $loc; Type = "standalone" }
        }
    }
    
    # Check RubyInstaller Devkit paths
    # RubyInstaller installs MSYS2 under the Ruby directory
    $rubyPaths = @()
    
    # Common RubyInstaller locations
    $rubyPaths += Get-ChildItem -Path "$env:SystemDrive\" -Filter "Ruby*" -Directory -ErrorAction SilentlyContinue | 
        ForEach-Object { $_.FullName }
    $rubyPaths += Get-ChildItem -Path "$env:ProgramFiles\" -Filter "Ruby*" -Directory -ErrorAction SilentlyContinue | 
        ForEach-Object { $_.FullName }
    
    # Check registry for RubyInstaller
    try {
        $regPaths = @(
            "HKLM:\SOFTWARE\RubyInstaller",
            "HKCU:\SOFTWARE\RubyInstaller",
            "HKLM:\SOFTWARE\WOW6432Node\RubyInstaller"
        )
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $installPath = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).InstallPath
                    if ($installPath) {
                        $rubyPaths += $installPath
                    }
                }
            }
        }
    } catch {
        # Registry access may fail, continue with filesystem paths
    }
    
    # Check each Ruby path for Devkit's MSYS2
    foreach ($rubyPath in $rubyPaths | Select-Object -Unique) {
        $devkitPath = Join-Path $rubyPath "msys64"
        if (Test-Path "$devkitPath\usr\bin\bash.exe") {
            return @{ Path = $devkitPath; Type = "devkit"; RubyPath = $rubyPath }
        }
    }
    
    return $null
}

function Find-Spinel {
    if ($SpinelPath -and (Test-Path "$SpinelPath\spinel.exe")) {
        return $SpinelPath
    }
    if ($SpinelPath -and (Test-Path "$SpinelPath\bin\spinel.exe")) {
        return "$SpinelPath\bin"
    }
    
    if (Test-Command "spinel") {
        return (Get-Command "spinel").Source | Split-Path
    }
    
    $locations = @(
        "$env:USERPROFILE\spinel\bin",
        "$env:SystemDrive\spinel\bin",
        "$env:ProgramFiles\spinel\bin"
    )
    
    foreach ($loc in $locations) {
        if (Test-Path "$loc\spinel.exe") {
            return $loc
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Write-Host @"
======================================================
  anyspec Windows Binary Builder
======================================================
"@ -ForegroundColor Green

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "Project root: $ProjectRoot"
Write-Host "Output directory: $OutputDir"

# Check for MSYS2 or RubyInstaller Devkit
Write-Step "Checking for MSYS2 / RubyInstaller Devkit"
$MSYS2Info = Find-MSYS2
if (-not $MSYS2Info) {
    Write-Host @"
MSYS2 not found in standard locations.

To build anyspec on Windows, you need MSYS2 with the UCRT64 toolchain.

Installation options:
1. Install MSYS2: https://www.msys2.org/
   Then in MSYS2 UCRT64 shell:
   pacman -S --needed make diffutils curl tar git mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-ruby

2. Or install RubyInstaller with Devkit: https://rubyinstaller.org/
   Then run this script again, or use the bash script in a Devkit shell:
   > ridk enable
   > bash scripts/build-windows-binary.sh

"@ -ForegroundColor Yellow
    Write-Error-Exit "MSYS2 not found. Please install MSYS2 or RubyInstaller Devkit."
}

$MSYS2Path = $MSYS2Info.Path
$MSYS2Type = $MSYS2Info.Type

if ($MSYS2Type -eq "devkit") {
    Write-Host "Found RubyInstaller Devkit MSYS2 at: $MSYS2Path" -ForegroundColor Green
    Write-Host "  (Ruby installation: $($MSYS2Info.RubyPath))" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: For Devkit environments, you may also run in a Devkit shell:" -ForegroundColor Yellow
    Write-Host "  > ridk enable" -ForegroundColor Yellow
    Write-Host "  > bash scripts/build-windows-binary.sh" -ForegroundColor Yellow
} else {
    Write-Host "Found standalone MSYS2 at: $MSYS2Path" -ForegroundColor Green
}

# Check for Spinel
Write-Step "Checking for Spinel"
$SpinelDir = Find-Spinel
if (-not $SpinelDir) {
    Write-Host @"
Spinel compiler not found.

To build Spinel on Windows, run these commands in MSYS2 UCRT64 shell:

    # Install dependencies
    pacman -S --needed make diffutils curl tar git mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-ruby

    # Clone and build Spinel
    git clone https://github.com/matz/spinel.git
    cd spinel
    make deps && make
    
    # Optionally install to PATH
    make install PREFIX=/usr/local

After building Spinel, run this script again or specify the path:
    .\build-windows-binary.ps1 -SpinelPath C:\path\to\spinel

"@ -ForegroundColor Yellow
    Write-Error-Exit "Spinel not found. Please build Spinel first (see instructions above)."
}
Write-Host "Found Spinel at: $SpinelDir" -ForegroundColor Green

# Verify spinel works
Write-Step "Verifying Spinel installation"
$SpinelExe = Join-Path $SpinelDir "spinel.exe"
$SpinExe = Join-Path $SpinelDir "spin.exe"

if (-not (Test-Path $SpinelExe)) {
    Write-Error-Exit "spinel.exe not found in $SpinelDir"
}

try {
    $version = & $SpinelExe --version 2>&1
    Write-Host "Spinel version: $version" -ForegroundColor Green
} catch {
    Write-Error-Exit "Failed to run spinel.exe: $_"
}

# Set up environment for spin
Write-Step "Setting up build environment"

# Find MSYS2 shell for spin
$MSYS2Shell = "$MSYS2Path\usr\bin\sh.exe"
if (-not (Test-Path $MSYS2Shell)) {
    Write-Error-Exit "MSYS2 shell not found at $MSYS2Shell"
}

$env:SPINEL_SHELL = $MSYS2Shell
$env:PATH = "$SpinelDir;$MSYS2Path\ucrt64\bin;$MSYS2Path\usr\bin;$env:PATH"

Write-Host "SPINEL_SHELL set to: $env:SPINEL_SHELL"

# Build anyspec
Write-Step "Building anyspec"
Push-Location $ProjectRoot

try {
    Write-Host "Running: spin build"
    & $SpinExe build
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Exit "spin build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# Copy binary to output
Write-Step "Copying binary to output directory"
$BuildBinary = Join-Path $ProjectRoot "build\bin\anyspec.exe"
if (-not (Test-Path $BuildBinary)) {
    Write-Error-Exit "Build output not found at $BuildBinary"
}

$OutputPath = Join-Path $ProjectRoot $OutputDir
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$OutputBinary = Join-Path $OutputPath "anyspec.exe"
Copy-Item $BuildBinary $OutputBinary -Force

# Verify
Write-Step "Verifying output"
if (Test-Path $OutputBinary) {
    $info = Get-Item $OutputBinary
    Write-Host "Binary created: $OutputBinary"
    Write-Host "Size: $([math]::Round($info.Length / 1MB, 2)) MB"
    
    Write-Host "`nTesting binary..."
    try {
        $ver = & $OutputBinary --version 2>&1
        Write-Host "Version: $ver" -ForegroundColor Green
    } catch {
        Write-Host "Warning: Could not run binary: $_" -ForegroundColor Yellow
    }
} else {
    Write-Error-Exit "Binary was not created"
}

Write-Host @"

======================================================
  Build Complete!
======================================================

Binary: $OutputBinary

To use:
  1. Ensure 'oci' CLI is installed and configured
  2. Run: .\$OutputDir\anyspec.exe check <spec.yml>

Note: The 'oci' CLI is NOT bundled with anyspec.
      Install it separately: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm

"@ -ForegroundColor Green
