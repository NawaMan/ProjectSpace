#!/usr/bin/env pwsh
# start-compose.ps1
# Compose helper with:
#  - requires `--` before in-container commands
#  - -Daemon to run service in background (docker compose up -d)
#  - -Attach to exec into running service (bash)
#  - -RunFlags passes extra flags to `docker compose run` (before service)
#  - UID/GID export for docker-compose.yml

param(
    [switch]$Build,
    [switch]$Clean,
    [switch]$Prune,
    [switch]$Daemon,
    [switch]$Attach,
    [switch]$Help,
    # Extra flags for `docker compose run` (array), e.g. -RunFlags "--service-ports","--entrypoint","/bin/sh"
    [string[]]$RunFlags,
    # Capture remaining args so we can parse `-- <command...>`
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$Service = "app"
$Workspace = "/home/coder/workspace"

function Show-Help {
@"
Usage:
  .\start-compose.ps1 [OPTIONS]                    # interactive one-off shell (bash)
  .\start-compose.ps1 [OPTIONS] -- <command...>    # run a command then exit
  .\start-compose.ps1 [OPTIONS] -Daemon            # bring service up in background
  .\start-compose.ps1 -Attach                      # exec a bash shell into running service

Options:
  -Build        docker compose build
  -Clean        docker compose down --remove-orphans
  -Prune        docker compose down --rmi local --volumes --remove-orphans
  -Daemon       Run service in background (docker compose up -d)
  -Attach       Exec into running service with bash
  -RunFlags     Extra flags for 'docker compose run' (array)
  -Help         Show this help

Notes:
  • Commands MUST follow a literal `--` (except -Daemon / -Attach).
  • HOST_UID / HOST_GID are exported for your docker-compose.yml.
  • One-off 'run' containers are removed on exit; -Daemon uses 'up -d'.

Examples:
  .\start-compose.ps1
  .\start-compose.ps1 -- python -V
  .\start-compose.ps1 -- zsh
  .\start-compose.ps1 -RunFlags "--service-ports" -- jupyter lab --ip=0.0.0.0 --no-browser
  .\start-compose.ps1 -Daemon
  .\start-compose.ps1 -Attach
"@ | Write-Output
}

if ($Help) { Show-Help; exit 0 }

# --- Export UID/GID for compose env substitution ------------------------------
$uid = 1000; $gid = 1000
if (Get-Command id -ErrorAction SilentlyContinue) {
    try { $uid = (& id -u).ToString().Trim(); $gid = (& id -g).ToString().Trim() } catch { }
} elseif ($env:WSL_DISTRO_NAME -or (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    try { $uid = (wsl.exe id -u).Trim(); $gid = (wsl.exe id -g).Trim() } catch { }
}
$env:HOST_UID = $uid
$env:HOST_GID = $gid

# Helper to call `docker compose ...`
function Dc { param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args) & docker compose @Args }

# --- Maintenance actions ------------------------------------------------------
if ($Prune) { Dc down --rmi local --volumes --remove-orphans; exit $LASTEXITCODE }
if ($Clean) { Dc down --remove-orphans; exit $LASTEXITCODE }
if ($Build) { Dc build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }

# --- Parse `-- <command...>` safely ------------------------------------------
if (-not $Rest) { $Rest = @() }
$Cmd = @()
$idx = [Array]::IndexOf($Rest, "--")
if ($idx -ge 0) {
    if ($idx -lt ($Rest.Count - 1)) { $Cmd = $Rest[($idx+1)..($Rest.Count-1)] }
} elseif ($Rest.Count -gt 0) {
    Write-Error "Unrecognized argument(s): $Rest. If you intended to run a command inside the container, use:`n  .\start-compose.ps1 -- <command...>`nOr use -Daemon to run detached."
    exit 2
}
if (-not $RunFlags) { $RunFlags = @() }

# --- Incompatible combos ------------------------------------------------------
if ($Daemon -and $Cmd.Count -gt 0) {
    Write-Error "Cannot use -Daemon together with a one-off command (-- <command...>)."
    exit 2
}
if ($Attach -and ($Daemon -or $Cmd.Count -gt 0)) {
    Write-Error "-Attach cannot be combined with -Daemon or a one-off command."
    exit 2
}

# --- Service status -----------------------------------------------------------
$appId = (Dc ps -q $Service 2>$null | Select-Object -First 1)

# --- Attach -------------------------------------------------------------------
if ($Attach) {
    if ($appId) {
        Dc exec $Service bash
        exit $LASTEXITCODE
    } else {
        Write-Error "Service '$Service' is not running. Start it with -Daemon first."
        exit 2
    }
}

# --- Daemon mode --------------------------------------------------------------
if ($Daemon) {
    if ($appId) {
        Write-Output "Service '$Service' already running (container: $appId)."
        exit 0
    }
    Dc up -d $Service
    exit $LASTEXITCODE
}

# --- One-off run: interactive or command -------------------------------------
if ($Cmd.Count -eq 0) {
    # Interactive bash; container removed on exit
    Dc run --rm --no-deps @RunFlags $Service bash
    exit $LASTEXITCODE
} else {
    # One-off command via bash -lc
    $UserCmd = ($Cmd -join " ")
    Dc run --rm --no-deps @RunFlags $Service bash -lc "$UserCmd"
    exit $LASTEXITCODE
}
