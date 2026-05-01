# ============================================================
# Get-QP1ARCY.ps1
# Downloads the BRMS Recovery Report spool file (QP1ARCY)
# from an IBM i V7R5 system via SSH + CPYSPLF + SCP.
#
# Usage  : .\Get-QP1ARCY.ps1 192.168.10.50
# Example: .\Get-QP1ARCY.ps1 -IP 192.168.10.50
#
# Depends: Posh-SSH module (provides SSH + SCP in PowerShell)
#          Install-Module -Name Posh-SSH -Scope CurrentUser
# Creds  : ibmiscrt.json  { "user": "...", "key": "C:\path\to\private_key" }
# Tested : PowerShell 5.1 (Windows) and PowerShell 7+ (cross-platform)
#
# Key setup (one-time):
#   ssh-keygen -t rsa -b 4096 -f "$HOME\.ssh\ibmi_id_rsa"
#   Then add ibmi_id_rsa.pub to ~/.ssh/authorized_keys on the IBM i
# ============================================================

param(
    [Parameter(Mandatory = $true, Position = 0,
               HelpMessage = "IBM i IP address or hostname")]
    [string]$IP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Parameters ────────────────────────────────────────────────
$CredsFile  = "ibmiscrt.json"
$SplfName   = "QP1ARCY"
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile = "${SplfName}_${Timestamp}.txt"
$IfsTemp    = "/tmp/$OutputFile"       # same basename → SCP lands as $OutputFile directly
$DB2Cmd     = "/QOpenSys/usr/bin/db2"
$SystemCmd  = "/QOpenSys/usr/bin/system"

# ── Dependency check: Posh-SSH ────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Error (
        "Posh-SSH module not found.`n" +
        "Install it with:  Install-Module -Name Posh-SSH -Scope CurrentUser"
    )
    exit 1
}
Import-Module Posh-SSH -ErrorAction Stop

# ── Read credentials ──────────────────────────────────────────
if (-not (Test-Path $CredsFile)) {
    Write-Error "Credentials file '$CredsFile' not found in $(Get-Location)"
    exit 1
}

$Creds    = Get-Content $CredsFile -Raw | ConvertFrom-Json
$IbmiUser = $Creds.user
$SshKey   = $Creds.key

if ([string]::IsNullOrWhiteSpace($IbmiUser)) {
    Write-Error "'user' key is missing or empty in $CredsFile"; exit 1
}
if ([string]::IsNullOrWhiteSpace($SshKey)) {
    Write-Error "'key' path is missing or empty in $CredsFile"; exit 1
}
if (-not (Test-Path $SshKey)) {
    Write-Error "SSH key file not found: $SshKey"; exit 1
}

# Credential object carries the username; key file handles authentication
$SecurePass = New-Object System.Security.SecureString
$Credential = New-Object System.Management.Automation.PSCredential($IbmiUser, $SecurePass)

# ── Header ────────────────────────────────────────────────────
Write-Host "────────────────────────────────────────────────"
Write-Host " IBM i BRMS Report Downloader"
Write-Host " Host  : $IP"
Write-Host " User  : $IbmiUser"
Write-Host " Key   : $SshKey"
Write-Host " Spool : $SplfName"
Write-Host " Mode  : SSH + CPYSPLF + SCP"
Write-Host "────────────────────────────────────────────────"

# ── Connect ───────────────────────────────────────────────────
$Session = New-SSHSession -ComputerName $IP -Credential $Credential `
               -KeyFile $SshKey -AcceptKey:$true -ErrorAction Stop

try {
    # ── Step 1 : Locate most recent spool via SQL ──────────────
    Write-Host "[1/3] Locating most recent $SplfName spool file..."

    # Result row format: JOBNBR/JOBUSER/JOBNAME|SPLNBR
    $SqlCmd = "${DB2Cmd} `"SELECT TRIM(CHAR(JOB_NUMBER))||'/'||TRIM(JOB_USER)||'/'||TRIM(JOB_NAME)||'|'||TRIM(CHAR(SPOOLED_FILE_NUMBER)) FROM QSYS2.OUTPUT_QUEUE_ENTRIES WHERE SPOOLED_FILE_NAME='${SplfName}' AND JOB_USER='${IbmiUser}' ORDER BY CREATION_TIMESTAMP DESC FETCH FIRST 1 ROW ONLY`" 2>/dev/null | grep '|' | tr -d ' '"

    $SqlResult = Invoke-SSHCommand -SessionId $Session.SessionId -Command $SqlCmd -ErrorAction Stop
    $SpoolRow  = $SqlResult.Output | Where-Object { $_ -match '\|' } | Select-Object -First 1
    if ($SpoolRow) { $SpoolRow = $SpoolRow.Trim() }

    if ([string]::IsNullOrWhiteSpace($SpoolRow)) {
        Write-Error "No $SplfName spool file found for user $IbmiUser.`nEnsure BRMS has generated the recovery report."
        exit 3
    }

    $Parts   = $SpoolRow -split '\|'
    $JobId   = $Parts[0]
    $SplfNbr = $Parts[1]

    Write-Host "    Job    : $JobId"
    Write-Host "    Spool# : $SplfNbr"

    # ── Step 2 : Copy spool to IFS ────────────────────────────
    Write-Host "[2/3] Copying spool to IFS temp file..."

    $CpyCmd    = "${SystemCmd} `"CPYSPLF FILE($SplfName) TOFILE(*IFS) TOSTMF('$IfsTemp') STMFOPT(*REPLACE) JOB($JobId) SPLNBR($SplfNbr) WSCST(*AUTOCVT)`""
    $CpyResult = Invoke-SSHCommand -SessionId $Session.SessionId -Command $CpyCmd -ErrorAction Stop

    if ($CpyResult.ExitStatus -ne 0) {
        Write-Error "CPYSPLF failed — check job ID '$JobId' and spool number '$SplfNbr'."
        exit 4
    }

    # ── Step 3 : Download via SCP and clean up ─────────────────
    Write-Host "[3/3] Downloading '$IfsTemp' → '$OutputFile'..."

    Get-SCPItem -ComputerName $IP -Credential $Credential -KeyFile $SshKey -AcceptKey:$true `
        -Path $IfsTemp -PathType File -Destination (Get-Location).Path -ErrorAction Stop

    Invoke-SSHCommand -SessionId $Session.SessionId -Command "rm -f '$IfsTemp'" | Out-Null

} finally {
    Remove-SSHSession -SessionId $Session.SessionId -ErrorAction SilentlyContinue | Out-Null
}

# ── Done ──────────────────────────────────────────────────────
$FileInfo = Get-Item $OutputFile
Write-Host "────────────────────────────────────────────────"
Write-Host " SUCCESS"
Write-Host " File : $($FileInfo.FullName)"
Write-Host " Size : $([Math]::Round($FileInfo.Length / 1KB, 1)) KB"
Write-Host "────────────────────────────────────────────────"
