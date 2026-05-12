[CmdletBinding(DefaultParameterSetName='Run')]
param(
    [Parameter(ParameterSetName='Version')]
    [switch]$Version,

    [Parameter(ParameterSetName='Run', Mandatory=$true)]
    [string]$HostName,

    [Parameter(ParameterSetName='Run', Mandatory=$false)]
    [string]$SecretsFile = "",

    [Parameter(ParameterSetName='Run', Mandatory=$false)]
    [string]$Date = "",

    [Parameter(ParameterSetName='Run', Mandatory=$false)]
    [switch]$UploadToCOS
)

if ($Version) {
    [ordered]@{
        tool       = "get_qp1arcy.ps1"
        version    = "1.1.0"
        author     = "Ricardo Martins"
        company    = "Blue Chip Portugal"
        license    = "MIT"
        maintained = "2026-2026"
    } | ConvertTo-Json
    exit 0
}

$ScriptDir = $PSScriptRoot

if ($SecretsFile -eq "") {
    $ConfigFile = Join-Path $ScriptDir "ibmiscrt.json"
} elseif ([System.IO.Path]::IsPathRooted($SecretsFile)) {
    $ConfigFile = $SecretsFile
} else {
    $ConfigFile = Join-Path $ScriptDir $SecretsFile
}

if ($Date -ne "" -and $Date -notmatch '^\d{4}-\d{2}-\d{2}$') {
    Write-Host "ERROR: Date must be in YYYY-MM-DD format (e.g. 2026-05-03)"
    exit 1
}

if (!(Test-Path $ConfigFile)) {
    Write-Host "ERROR: Config file not found: $ConfigFile"
    exit 1
}

$cfg = Get-Content -Raw $ConfigFile | ConvertFrom-Json

$IbmiUser = $cfg.user
$SshKey   = [System.Environment]::ExpandEnvironmentVariables($cfg.ssh_key)
$LocalDir = [System.Environment]::ExpandEnvironmentVariables($cfg.local_dir)

if (!$IbmiUser -or !$SshKey -or !$LocalDir) {
    Write-Host "ERROR: ibmiscrt.json must contain: user, ssh_key, local_dir"
    exit 1
}

if (!(Test-Path $SshKey)) {
    Write-Host "ERROR: SSH key not found: $SshKey"
    exit 1
}

# COS — validate config and import module only when -UploadToCOS is requested
$CosEndpoint = $null
$CosBucket   = $null
$CosAccess   = $null
$CosSecret   = $null
$CosRegion   = $null

if ($UploadToCOS) {
    $CosEndpoint = $cfg.cos_endpoint
    $CosBucket   = $cfg.cos_bucket
    $CosAccess   = $cfg.cos_access_key
    $CosSecret   = $cfg.cos_secret_key
    $CosRegion   = $cfg.cos_region

    if (!$CosEndpoint -or !$CosBucket -or !$CosAccess -or !$CosSecret -or !$CosRegion) {
        Write-Host "[ERROR] -UploadToCOS requires ibmiscrt.json to contain:"
        Write-Host "        cos_endpoint, cos_bucket, cos_access_key, cos_secret_key, cos_region"
        exit 1
    }

    if (-not (Get-Module -ListAvailable -Name AWS.Tools.S3)) {
        Write-Host "[ERROR] PowerShell module AWS.Tools.S3 not found."
        Write-Host "        Install it with: Install-Module -Name AWS.Tools.S3 -Scope CurrentUser"
        exit 1
    }
    Import-Module AWS.Tools.S3 -ErrorAction Stop
}

$RemoteScript = Join-Path $ScriptDir "remote_get_qp1arcy.sh"
$RemotePath   = "/tmp/remote_get_qp1arcy.sh"

if (!(Test-Path $RemoteScript)) {
    Write-Host "ERROR: remote_get_qp1arcy.sh not found in $ScriptDir"
    exit 1
}

$SshOpts = @("-i", $SshKey, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new")

# Normalise to LF before upload — IBM i bash cannot execute CRLF scripts
$scriptContent = (Get-Content -Raw $RemoteScript) -replace "`r`n", "`n" -replace "`r", "`n"
$tempScript = Join-Path $env:TEMP ("remote_get_qp1arcy_{0}.sh" -f (Get-Random))
[System.IO.File]::WriteAllText($tempScript, $scriptContent, [System.Text.UTF8Encoding]::new($false))

Write-Host "[INFO] Uploading remote script to ${IbmiUser}@${HostName} ..."
scp @SshOpts $tempScript "${IbmiUser}@${HostName}:$RemotePath"
Remove-Item $tempScript -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] scp upload failed (exit $LASTEXITCODE). Check SSH key, user, and host reachability."
    exit $LASTEXITCODE
}

$RemoteCmd = "chmod +x $RemotePath && $RemotePath"
if ($Date -ne "") { $RemoteCmd += " $Date" }
Write-Host "[INFO] Running remote script ..."
$RemoteOutput = ssh @SshOpts "${IbmiUser}@${HostName}" $RemoteCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Remote script failed (exit $LASTEXITCODE). Check IBM i user authority and spool file availability."
    exit $LASTEXITCODE
}

$RemoteFiles = $RemoteOutput -split "`n" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" }

if (!$RemoteFiles -or $RemoteFiles.Count -eq 0) {
    Write-Host "ERROR: Remote script did not return any file paths"
    exit 1
}

foreach ($RemoteFile in $RemoteFiles) {
    Write-Host "[INFO] Downloading $RemoteFile ..."
    scp @SshOpts "${IbmiUser}@${HostName}:$RemoteFile" $LocalDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] scp download failed for $RemoteFile (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
    $leaf      = Split-Path $RemoteFile -Leaf
    $localFile = Join-Path $LocalDir $leaf
    Write-Host "[OK] Downloaded: $localFile"

    if ($UploadToCOS) {
        # Derive YYYYMM from filename: {LPAR}_{SPLF}_{YYYYMMDD}_{HHMMSS}.txt
        if ($leaf -match '_(\d{8})_') {
            $cosFolder = $Matches[1].Substring(0, 6)
        } else {
            $cosFolder = (Get-Date).ToString("yyyyMM")
        }
        $cosKey = "$cosFolder/$leaf"
        Write-Host "[INFO] Uploading to COS: $CosBucket/$cosKey ..."
        try {
            Write-S3Object -BucketName $CosBucket `
                           -Key        $cosKey `
                           -File       $localFile `
                           -AccessKey  $CosAccess `
                           -SecretKey  $CosSecret `
                           -EndpointUrl $CosEndpoint `
                           -Region     $CosRegion `
                           -ErrorAction Stop
            Write-Host "[OK] COS: $cosKey"
        } catch {
            Write-Host "[ERROR] COS upload failed for ${leaf}: $_"
            exit 1
        }
    }
}

$rmList = ($RemoteFiles | ForEach-Object { "'$_'" }) -join " "
ssh @SshOpts "${IbmiUser}@${HostName}" "rm -f $rmList '$RemotePath'" | Out-Null
