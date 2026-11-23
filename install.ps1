# Nakbox installer for Windows. This file works alone: it needs no other
# Nakbox files, everything is downloaded from GitHub. Run it by hand
# (or double-click "Install Nakbox.bat" next to it):
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -InstallDir C:\Nakbox
#
# The Inno Setup wizards (nakbox.iss) run it too.
#
# -InstallDir DIR : where Nakbox goes. Without it: %USERPROFILE%\Nakbox.
# -Python PATH    : the Python that Nakbox's environment is built with (3.10+;
#                   a Linux path with -Target wsl). Without it the first
#                   usable Python is taken, as run_windows.bat does.
# -ListPythons    : only print the Python installs found on this computer
#                   (inside WSL with -Target wsl) as "label<TAB>path" lines,
#                   newest first; -OutFile writes them to a file (UTF-8).
#                   The setup wizard uses this for its Python page.
#
# -Target windows : download the newest release into InstallDir and prepare
#                   the Python environment there.
# -Target wsl     : run nakbox-install.sh inside the default WSL distribution
#                   and write a launcher (Nakbox (WSL).bat) into InstallDir.
#                   nakbox-install.sh is taken from next to this file (or the
#                   folder above); if it is not there, it is downloaded from
#                   the GitHub release.
#
# The Nakbox repository is private: the GitHub token comes from -TokenFile
# (deleted after reading) or from the NAKBOX_GITHUB_TOKEN environment variable.
# If neither gives one, the token saved by an earlier install is used, and
# when there is none either, the token is asked for (not with -TokenFile or
# -NoPause). The token is saved in config\update_token so Nakbox can look
# for updates.
# Keep this file ASCII only (Windows PowerShell 5.1 reads it as ANSI).
param(
    [ValidateSet('windows', 'wsl')][string]$Target = 'windows',
    [string]$InstallDir = '',
    [string]$WslDir = '~/Nakbox',
    [switch]$Portable,
    [string]$TokenFile = '',
    [string]$Repo = 'Aksulaattori/Nakbox',
    [string]$Version = 'latest',
    [string]$Python = '',
    [switch]$ListPythons,
    [string]$OutFile = '',
    [string]$ApiBase = 'https://api.github.com',
    [switch]$NoSetup,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$LogFile = Join-Path $env:TEMP 'nakbox-install.log'
$Work = Join-Path $env:TEMP ('nakbox-install-' + [Guid]::NewGuid().ToString('N'))
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$Token = $env:NAKBOX_GITHUB_TOKEN
if ($TokenFile -and (Test-Path -LiteralPath $TokenFile)) {
    $Token = (Get-Content -LiteralPath $TokenFile -Raw)
    Remove-Item -LiteralPath $TokenFile -Force
}
if ($Token) { $Token = $Token.Trim() }
if (-not $InstallDir -and -not $ListPythons) { $InstallDir = Join-Path $env:USERPROFILE 'Nakbox' }
$SavedTokenFile = ''
if ($InstallDir) { $SavedTokenFile = Join-Path $InstallDir 'config\update_token' }
if (-not $Token -and $Target -eq 'windows' -and $SavedTokenFile -and (Test-Path -LiteralPath $SavedTokenFile)) {
    $Token = (Get-Content -LiteralPath $SavedTokenFile -Raw)
    if ($Token) { $Token = $Token.Trim() }
}
# Run by hand with no token anywhere: ask for it. The setup wizard has its own
# token page and always passes -TokenFile, so it is never asked twice.
if (-not $Token -and -not $TokenFile -and -not $NoPause -and -not $ListPythons) {
    Write-Host "The Nakbox repository is private. Paste a GitHub token that can read $Repo"
    Write-Host '(leave empty if the repository is public or a token was saved by an earlier install).'
    $secure = Read-Host 'GitHub token' -AsSecureString
    $Token = (New-Object Management.Automation.PSCredential('token', $secure)).GetNetworkCredential().Password
    if ($Token) { $Token = $Token.Trim() }
}

function Get-GitHubHeaders([string]$Accept) {
    $headers = @{ 'Accept' = $Accept; 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    return $headers
}

function Get-Release {
    if ($Version -eq 'latest') { $url = "$ApiBase/repos/$Repo/releases/latest" }
    else { $url = "$ApiBase/repos/$Repo/releases/tags/$Version" }
    try {
        return Invoke-RestMethod -Uri $url -UseBasicParsing -UserAgent 'nakbox-installer' `
            -Headers (Get-GitHubHeaders 'application/vnd.github+json')
    }
    catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        switch ($code) {
            401 { throw 'GitHub rejected the token (401). Check that it was copied whole and has not expired.' }
            403 { throw "GitHub refused the request (403): rate limit, or the token has no access to $Repo." }
            404 {
                if ($Token) { throw "No release found (404). Check that the token can read $Repo and that a release has been published." }
                throw 'No release found (404). The repository is private: a GitHub token is needed.'
            }
            default { throw "Could not reach GitHub: $($_.Exception.Message)" }
        }
    }
}

function Update-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Invoke-Setup {
    Push-Location -LiteralPath $InstallDir
    try {
        & cmd.exe /c 'run_windows.bat --setup-only'
        return $LASTEXITCODE
    }
    finally { Pop-Location }
}

# Runs a Python and returns what it prints for -c CODE, or $null when it does
# not start, fails or is older than 3.10. -X utf8 keeps paths with letters
# such as a-umlaut whole.
function Invoke-PythonProbe([string]$Exe, [string]$Code) {
    $ErrorActionPreference = 'Continue'
    $full = 'import sys; sys.version_info >= (3, 10) or sys.exit(1); ' + $Code
    try {
        $out = @(& $Exe -X utf8 -c $full 2>$null)
        if ($LASTEXITCODE -ne 0 -or $out.Count -eq 0) { return $null }
        return [string]$out[0]
    }
    catch { return $null }
}

# Every Python 3.10+ on this computer: the py launcher, the registry
# (PEP 514), PATH and the usual install folders. "label<TAB>path", newest first.
function Get-WindowsPythons {
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $ErrorActionPreference = 'Continue'
        foreach ($line in @(& py.exe -0p 2>$null)) {
            if ([string]$line -match '([A-Za-z]:\\.+\.exe)\s*$') { $candidates.Add($Matches[1]) }
        }
    }
    catch { }
    $ErrorActionPreference = 'Stop'
    foreach ($root in 'HKCU:\Software\Python', 'HKLM:\SOFTWARE\Python', 'HKLM:\SOFTWARE\WOW6432Node\Python') {
        foreach ($key in @(Get-Item -Path "$root\*\*\InstallPath" -ErrorAction SilentlyContinue)) {
            $exe = $key.GetValue('ExecutablePath')
            if (-not $exe -and $key.GetValue('')) { $exe = Join-Path $key.GetValue('') 'python.exe' }
            if ($exe) { $candidates.Add([string]$exe) }
        }
    }
    foreach ($cmd in @(Get-Command python.exe, python3.exe -All -CommandType Application -ErrorAction SilentlyContinue)) {
        $candidates.Add($cmd.Source)
    }
    $patterns = @(
        "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-*\python.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\python3*.exe",
        "$env:ProgramFiles\Python*\python.exe",
        "${env:ProgramFiles(x86)}\Python*\python.exe",
        "$env:SystemDrive\Python*\python.exe",
        "$env:USERPROFILE\.pyenv\pyenv-win\versions\*\python.exe",
        "$env:APPDATA\uv\python\*\python.exe",
        "$env:USERPROFILE\scoop\apps\python*\current\python.exe",
        "$env:USERPROFILE\miniconda3\python.exe",
        "$env:USERPROFILE\miniforge3\python.exe",
        "$env:USERPROFILE\anaconda3\python.exe",
        "$env:ProgramData\miniconda3\python.exe",
        "$env:ProgramData\anaconda3\python.exe"
    )
    foreach ($pattern in $patterns) {
        foreach ($hit in @(Resolve-Path -Path $pattern -ErrorAction SilentlyContinue)) { $candidates.Add($hit.ProviderPath) }
    }

    $seen = @{}
    $found = @()
    $code = "print('%d.%d.%d|%d|%s' % (sys.version_info[0], sys.version_info[1], sys.version_info[2], 64 if sys.maxsize > 2**32 else 32, sys.executable))"
    foreach ($exe in $candidates) {
        if (-not $exe -or $seen.ContainsKey($exe.ToLower())) { continue }
        $seen[$exe.ToLower()] = $true
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $info = Invoke-PythonProbe $exe $code
        if (-not $info) { continue }
        $parts = $info.Split('|', 3)
        if ($parts.Count -ne 3) { continue }
        # Several names can start the same Python (py launcher, PATH alias).
        $real = $parts[2]
        if ($real.ToLower() -ne $exe.ToLower()) {
            if ($seen.ContainsKey($real.ToLower())) { continue }
            $seen[$real.ToLower()] = $true
        }
        $found += New-Object PSObject -Property @{ Version = [version]$parts[0]; Bits = [int]$parts[1]; Path = $real }
    }
    foreach ($item in @($found | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'Bits'; Descending = $true })) {
        "Python $($item.Version) ($($item.Bits)-bit)`t$($item.Path)"
    }
}

function Get-WslExe {
    $wsl = Join-Path $env:SystemRoot 'System32\wsl.exe'
    if (-not (Test-Path -LiteralPath $wsl)) { throw 'WSL is not installed on this computer.' }
    return $wsl
}

# nakbox-install.sh next to this file or one folder up (the repository
# layout); otherwise it is downloaded from the release, so install.ps1 works
# alone. WSL needs its Linux path.
function Get-LinuxScript([string]$Wsl) {
    $script = ''
    foreach ($dir in $ScriptDir, (Split-Path -Parent $ScriptDir)) {
        if (-not $dir) { continue }
        $candidate = Join-Path $dir 'nakbox-install.sh'
        if (Test-Path -LiteralPath $candidate) { $script = $candidate; break }
    }
    if (-not $script) {
        if (-not $ListPythons) { Write-Host 'Downloading nakbox-install.sh from GitHub...' }
        $release = Get-Release
        $asset = $release.assets | Where-Object { $_.name -eq 'nakbox-install.sh' } | Select-Object -First 1
        if (-not $asset) { throw 'The release has no nakbox-install.sh.' }
        New-Item -ItemType Directory -Force -Path $Work | Out-Null
        $script = Join-Path $Work 'nakbox-install.sh'
        Invoke-WebRequest -Uri $asset.url -OutFile $script -UseBasicParsing -UserAgent 'nakbox-installer' `
            -Headers (Get-GitHubHeaders 'application/octet-stream')
    }
    $linuxScript = [string](@(& $Wsl -e wslpath -a -u ($script -replace '\\', '/'))[0])
    if (-not $linuxScript) { throw 'Could not reach the installer files from WSL.' }
    return $linuxScript
}

function Get-WslPythons {
    $wsl = Get-WslExe
    $linuxScript = Get-LinuxScript $wsl
    foreach ($line in @(& $wsl -e sh $linuxScript --list-pythons)) {
        $parts = ([string]$line).Split("`t", 2)
        if ($parts.Count -eq 2 -and $parts[1]) { "Python $($parts[0])`t$($parts[1])" }
    }
}

# -Python was given: build .venv from that Python here, so run_windows.bat
# only has to install the packages. An environment built from another Python
# is thrown away first.
function Initialize-Venv {
    if (-not $Python) { return }
    $code = "print(sys.base_prefix + '|%d.%d' % (sys.version_info[0], sys.version_info[1]))"
    $want = Invoke-PythonProbe $Python $code
    if (-not $want) { throw "The chosen Python does not run or is older than 3.10: $Python" }
    $venv = Join-Path $InstallDir '.venv'
    $venvPython = Join-Path $venv 'Scripts\python.exe'
    if (Test-Path -LiteralPath $venv) {
        $have = $null
        if (Test-Path -LiteralPath $venvPython) { $have = Invoke-PythonProbe $venvPython $code }
        if ($have -ne $want) {
            Write-Host 'Removing the Python environment built with another Python...'
            Remove-Item -LiteralPath $venv -Recurse -Force
        }
    }
    if (-not (Test-Path -LiteralPath $venvPython)) {
        Write-Host "Creating the Python environment with $Python..."
        & $Python -m venv $venv
        if ($LASTEXITCODE -ne 0) { throw "Creating the Python environment with $Python failed." }
    }
}

function Install-Windows {
    Write-Host 'Looking up the release on GitHub...'
    $release = Get-Release
    $asset = $release.assets | Where-Object { $_.name -like 'Nakbox-*.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'The release has no Nakbox-*.zip package.' }

    Write-Host "Downloading Nakbox $($release.tag_name)..."
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    $zip = Join-Path $Work 'nakbox.zip'
    Invoke-WebRequest -Uri $asset.url -OutFile $zip -UseBasicParsing -UserAgent 'nakbox-installer' `
        -Headers (Get-GitHubHeaders 'application/octet-stream')

    $stage = Join-Path $Work 'stage'
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'main.py'))) { throw 'The package does not look like Nakbox.' }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    # Updating an existing install: keep the settings the user may have changed.
    # Saves, games and profiles are not in the package at all, so they stay.
    $keep = @('catalog.json')
    $stageConfig = Join-Path $stage 'config'
    if (Test-Path -LiteralPath $stageConfig) {
        $keep += Get-ChildItem -LiteralPath $stageConfig -File | ForEach-Object { Join-Path 'config' $_.Name }
    }
    foreach ($rel in $keep) {
        $staged = Join-Path $stage $rel
        if ((Test-Path -LiteralPath (Join-Path $InstallDir $rel)) -and (Test-Path -LiteralPath $staged)) {
            Remove-Item -LiteralPath $staged -Force
        }
    }
    Copy-Item -Path (Join-Path $stage '*') -Destination $InstallDir -Recurse -Force
    Set-Content -LiteralPath (Join-Path $InstallDir 'VERSION') -Value $release.tag_name -Encoding ASCII
    # Nakbox's updater (updater.py) reads the token from here.
    if ($Token) {
        New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'config') | Out-Null
        Set-Content -LiteralPath $SavedTokenFile -Value $Token -Encoding ASCII
    }
    Write-Host "Nakbox $($release.tag_name) is in $InstallDir"

    if ($NoSetup) { return }
    Write-Host 'Setting up the Python environment. This takes a few minutes the first time...'
    Initialize-Venv
    $code = Invoke-Setup
    if ($code -eq 3 -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        $answer = 'y'
        if (-not $NoPause) { $answer = Read-Host 'Python is missing. Install Python 3.14 now with winget? [Y/n]' }
        if ($answer -notmatch '^[nN]') {
            & winget.exe install -e --id Python.Python.3.14 --accept-source-agreements --accept-package-agreements
            Update-PathFromRegistry
            $code = Invoke-Setup
        }
    }
    if ($code -ne 0) {
        Write-Warning 'The Python environment is not ready. Nakbox tries again when it starts (run_windows.bat).'
    }
}

# The WSL folder must end up as an absolute Linux path. A Windows path to the
# same place (\\wsl.localhost\Ubuntu\home\me\Nakbox, C:\Games\Nakbox) is
# converted with wslpath. Handed over as it is, Linux would take it for a
# relative folder name and install under the current directory.
function Resolve-WslDir([string]$Wsl, [string]$Dir, [string]$LinuxHome) {
    $Dir = $Dir.Trim()
    if ($Dir -match '^\\\\' -or $Dir -match '^//wsl(\.localhost|\$)/' -or $Dir -match '^[A-Za-z]:[\\/]') {
        # No "| Select-Object -First 1" here: it stops the pipeline early and
        # leaves $LASTEXITCODE at -1 even when wslpath worked.
        $converted = [string](@(& $Wsl -e wslpath -a -u ($Dir -replace '\\', '/'))[0])
        if ($LASTEXITCODE -ne 0 -or -not $converted.StartsWith('/')) {
            throw "The folder $Dir is not inside the default WSL distribution. Give a Linux path such as ~/Nakbox."
        }
        $Dir = $converted
    }
    if ($Dir -eq '~') { $Dir = $LinuxHome }
    elseif ($Dir.StartsWith('~/')) { $Dir = $LinuxHome + $Dir.Substring(1) }
    if (-not $Dir.StartsWith('/') -or $Dir.Contains('\')) {
        throw "The WSL folder must be a Linux path such as ~/Nakbox or /opt/nakbox, not: $Dir"
    }
    if ($Dir.Length -gt 1) { $Dir = $Dir.TrimEnd('/') }
    if (-not $Dir) { $Dir = '/' }
    return $Dir
}

function Install-Wsl {
    $wsl = Get-WslExe
    & $wsl -e true
    if ($LASTEXITCODE -ne 0) { throw 'WSL has no working Linux distribution. Install one first (wsl --install).' }

    $linuxScript = Get-LinuxScript $wsl
    $linuxHome = (& $wsl -e sh -c 'echo $HOME' | Select-Object -First 1)
    $resolved = Resolve-WslDir $wsl $WslDir $linuxHome

    # Hand the token to WSL through the environment, not the command line.
    # -Repo and -ApiBase go the same way, so both halves use the same source.
    $env:NAKBOX_REPO = $Repo
    $env:NAKBOX_API = $ApiBase
    $pass = 'NAKBOX_REPO/u:NAKBOX_API/u'
    if ($Token) {
        $env:NAKBOX_GITHUB_TOKEN = $Token
        $pass = "NAKBOX_GITHUB_TOKEN/u:$pass"
    }
    if ($env:WSLENV) { $env:WSLENV = "${pass}:$env:WSLENV" }
    else { $env:WSLENV = $pass }

    $shArgs = @('-e', 'sh', $linuxScript, '--yes', '--dir', $resolved, '--version', $Version)
    if ($Portable) { $shArgs += '--portable' } else { $shArgs += '--standard' }
    if ($NoSetup) { $shArgs += '--no-setup' }
    if ($Python) { $shArgs += @('--python', $Python) }
    Write-Host 'Installing inside WSL (it may ask for your Linux password)...'
    & $wsl @shArgs
    if ($LASTEXITCODE -ne 0) { throw 'The install inside WSL failed. See the messages above.' }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $launcher = Join-Path $InstallDir 'Nakbox (WSL).bat'
    $lines = @(
        '@echo off',
        'rem Starts the Nakbox that is installed inside WSL.',
        "start `"Nakbox`" /min wsl.exe -e sh -c `"exec '$resolved/run_linux.sh'`""
    )
    Set-Content -LiteralPath $launcher -Value $lines -Encoding ASCII
    Write-Host "Launcher written to $launcher"
}

if ($ListPythons) {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $lines = @()
    try {
        if ($Target -eq 'wsl') { $lines = @(Get-WslPythons) } else { $lines = @(Get-WindowsPythons) }
    }
    catch { $lines = @() }
    if ($OutFile) { [IO.File]::WriteAllLines($OutFile, [string[]]$lines, (New-Object Text.UTF8Encoding($true))) }
    else { $lines }
    if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
    exit 0
}

try { Start-Transcript -Path $LogFile -Force | Out-Null } catch { }
$exit = 0
try {
    if ($Portable) { Write-Host "Nakbox installer (portable, target: $Target)" }
    else { Write-Host "Nakbox installer (target: $Target)" }
    if ($Target -eq 'wsl') { Install-Wsl } else { Install-Windows }
    Write-Host 'Done.'
}
catch {
    $exit = 1
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log: $LogFile"
}
finally {
    $env:NAKBOX_GITHUB_TOKEN = $null
    if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
    try { Stop-Transcript | Out-Null } catch { }
}
if ($exit -ne 0 -and -not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
exit $exit
