#!/usr/bin/env pwsh
# start-container.ps1

param(
    [switch]$Build,
    [switch]$Clean,
    [switch]$Help,
    [switch]$Daemon,
    [switch]$Attach,   # NEW: attach to an existing running container
    [string[]]$RunArgs,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ImageName     = "workspace-base"
$ContainerName = "workspace-base-run"
$Workspace     = "/home/coder/workspace"
$ShellName     = "bash"

function Show-Help {
@"
Usage:
  .\start-container.ps1 [OPTIONS]                   # interactive shell
  .\start-container.ps1 [OPTIONS] -- <command...>   # run a command then exit
  .\start-container.ps1 [OPTIONS] -Daemon           # run container detached
  .\start-container.ps1 -Attach                     # attach bash to running container

Options:
  -Build      Force rebuild image before run
  -Clean      Remove container and image
  -Daemon     Run container detached (background)
  -Attach     Attach to an already running container
  -Help       Show this help message
  -RunArgs    Pass raw docker run flags (array), e.g. -RunArgs "-p","8888:8888"

Notes:
  • Commands MUST follow a literal `--` (except when using -Daemon).
  • Workspace inside container is fixed at $Workspace.

Examples:
  .\start-container.ps1
  .\start-container.ps1 -- python -V
  .\start-container.ps1 -RunArgs "-p","8888:8888" -- jupyter lab --ip=0.0.0.0 --no-browser
  .\start-container.ps1 -Daemon
  .\start-container.ps1 -Attach
"@ | Write-Output
}

if ($Help) { Show-Help; exit 0 }

# --- UID/GID detection --------------------------------------------------------
$uid = 1000; $gid = 1000
if (Get-Command id -ErrorAction SilentlyContinue) {
    try { $uid = (& id -u).ToString().Trim(); $gid = (& id -g).ToString().Trim() } catch { }
} elseif ($env:WSL_DISTRO_NAME -or (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    try { $uid = (wsl.exe id -u).Trim(); $gid = (wsl.exe id -g).Trim() } catch { }
}
$env:HOST_UID = $uid
$env:HOST_GID = $gid

# --- Clean --------------------------------------------------------------------
if ($Clean) {
    docker rm -f $ContainerName 2>$null | Out-Null
    docker rmi $ImageName 2>$null | Out-Null
    exit 0
}

# --- Build --------------------------------------------------------------------
if ($Build) {
    docker build -t $ImageName .
}

# --- Parse `-- <command...>` safely ------------------------------------------
if (-not $Rest) { $Rest = @() }             # avoid null
$Cmd = @()
$idx = [Array]::IndexOf($Rest, "--")        # robust for PowerShell arrays
if ($idx -ge 0) {
    if ($idx -lt ($Rest.Count - 1)) { $Cmd = $Rest[($idx+1)..($Rest.Count-1)] }
} elseif ($Rest.Count -gt 0) {
    Write-Error "Unrecognized argument(s): $Rest. If you intended to run a command inside the container, use:`n  .\start-container.ps1 -- <command...>`nOr use -Daemon to run detached."
    exit 2
}

# --- Container existence handling --------------------------------------------
$runningId = (docker ps -q --filter "name=^/${ContainerName}$" | Select-Object -First 1)
$anyId     = (docker ps -aq --filter "name=^/${ContainerName}$" | Select-Object -First 1)

# If a stopped container with the same name exists, clean it up automatically
if (-not $runningId -and $anyId) {
    docker rm $ContainerName 2>$null | Out-Null
}

# If running and user asked to attach
if ($runningId -and $Attach) {
    exec docker exec -it $ContainerName $ShellName
}

# If running but we're about to start another, guide the user
if ($runningId -and -not $Attach -and -not $Daemon) {
    Write-Error "A container named '$ContainerName' is already running.`nUse -Attach to open a shell in it, or -Clean to remove it."
    exit 2
}

# --- Common docker args -------------------------------------------------------
$hostPath = (Get-Location).Path
$CommonArgs = @(
    "--name", $ContainerName,
    "-e", "HOST_UID=$($env:HOST_UID)",
    "-e", "HOST_GID=$($env:HOST_GID)",
    "-v", "$($hostPath):$Workspace"
) + ($RunArgs ?? @())

# --- Run modes ----------------------------------------------------------------
if ($Daemon) {
    # Detached: leave container running
    docker run -d `
        @CommonArgs `
        $ImageName `
        $ShellName -lc "while true; do sleep 3600; done" | Out-String | Write-Output
}
elseif ($Cmd.Count -eq 0) {
    # Interactive shell; auto-remove on exit
    docker run --rm -it `
        @CommonArgs `
        $ImageName `
        $ShellName
}
else {
    # One-off command; auto-remove on exit
    $UserCmd = ($Cmd -join " ")
    docker run --rm -it `
        @CommonArgs `
        $ImageName `
        $ShellName -lc "$UserCmd"
}
