param(
    [Parameter(Mandatory=$true)]
    [string]$HostName
)

$ScriptDir  = $PSScriptRoot
$ConfigFile = Join-Path $ScriptDir "ibmiscrt.json"

if (!(Test-Path $ConfigFile)) {
    Write-Host "ERROR: Config file not found: $ConfigFile"
    exit 1
}

$cfg = Get-Content -Raw $ConfigFile | ConvertFrom-Json

$IbmiUser = $cfg.user
$SshKey   = $cfg.ssh_key
$LocalDir = $cfg.local_dir

if (!$IbmiUser -or !$SshKey -or !$LocalDir) {
    Write-Host "ERROR: ibmiscrt.json must contain: user, ssh_key, local_dir"
    exit 1
}

if (!(Test-Path $SshKey)) {
    Write-Host "ERROR: SSH key not found: $SshKey"
    exit 1
}

$RemoteScript = Join-Path $ScriptDir "remote_get_qp1arcy.sh"
$RemotePath   = "/tmp/remote_get_qp1arcy.sh"

if (!(Test-Path $RemoteScript)) {
    Write-Host "ERROR: remote_get_qp1arcy.sh not found in $ScriptDir"
    exit 1
}

$SshOpts = @("-i", $SshKey, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new")

scp @SshOpts $RemoteScript "${IbmiUser}@${HostName}:$RemotePath"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$RemoteFile = ssh @SshOpts "${IbmiUser}@${HostName}" "chmod +x $RemotePath && $RemotePath"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$RemoteFile = $RemoteFile.Trim()

scp @SshOpts "${IbmiUser}@${HostName}:$RemoteFile" $LocalDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

ssh @SshOpts "${IbmiUser}@${HostName}" "rm -f '$RemoteFile' '$RemotePath'" | Out-Null

Write-Host "Downloaded: $LocalDir\$(Split-Path $RemoteFile -Leaf)"
