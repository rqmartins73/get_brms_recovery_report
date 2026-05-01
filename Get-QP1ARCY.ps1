# ============================================================
# Get-QP1ARCY.ps1
# Downloads the BRMS Recovery Report spool file (QP1ARCY)
# from an IBM i V7R5 system via REST API.
#
# Usage  : .\Get-QP1ARCY.ps1 192.168.10.50
# Example: .\Get-QP1ARCY.ps1 -IP 192.168.10.50
#
# Creds  : ibmiscrt.json  { "user": "...", "password": "..." }
# Tested : PowerShell 5.1 (Windows) and PowerShell 7+ (cross-platform)
# ============================================================

param(
    [Parameter(Mandatory = $true, Position = 0,
               HelpMessage = "IBM i IP address or hostname")]
    [string]$IP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Parameters ────────────────────────────────────────────────
$CredsFile   = "ibmiscrt.json"
$SplfName    = "QP1ARCY"
$Timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile  = "${SplfName}_${Timestamp}.txt"
$BaseUrl     = "https://${IP}:2005/ibmi/v1"

# ── SSL bypass for self-signed IBM i certificates ─────────────
# PowerShell 7+ : use -SkipCertificateCheck on each Invoke-* call
# PowerShell 5.1: use the ServicePointManager callback below
$IsPSCore = $PSVersionTable.PSEdition -eq "Core"

if (-not $IsPSCore) {
    # Windows PowerShell 5.1 — bypass self-signed cert globally for this session
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAll : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint sp, X509Certificate cert, WebRequest req, int problem) {
        return true;
    }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll
    [System.Net.ServicePointManager]::SecurityProtocol  =
        [System.Net.SecurityProtocolType]::Tls12 -bor
        [System.Net.SecurityProtocolType]::Tls13
}

# ── Read credentials ──────────────────────────────────────────
if (-not (Test-Path $CredsFile)) {
    Write-Error "Credentials file '$CredsFile' not found in $(Get-Location)"
    exit 1
}

$Creds    = Get-Content $CredsFile -Raw | ConvertFrom-Json
$IbmiUser = $Creds.user
$IbmiPass = $Creds.password

if ([string]::IsNullOrWhiteSpace($IbmiUser)) {
    Write-Error "'user' key is missing or empty in $CredsFile"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($IbmiPass)) {
    Write-Error "'password' key is missing or empty in $CredsFile"
    exit 1
}

# Build Basic Auth header
$AuthBytes  = [System.Text.Encoding]::UTF8.GetBytes("${IbmiUser}:${IbmiPass}")
$AuthBase64 = [Convert]::ToBase64String($AuthBytes)

$HeadersJson = @{
    "Authorization" = "Basic $AuthBase64"
    "Accept"        = "application/json"
}
$HeadersText = @{
    "Authorization" = "Basic $AuthBase64"
    "Accept"        = "text/plain"
}

# ── Step 1 : List spool files ─────────────────────────────────
Write-Host "────────────────────────────────────────────────"
Write-Host " IBM i BRMS Report Downloader"
Write-Host " Host     : $IP"
Write-Host " User     : $IbmiUser"
Write-Host " Spool    : $SplfName"
Write-Host "────────────────────────────────────────────────"
Write-Host "[1/3] Querying spool file list..."

$ListUrl = "${BaseUrl}/spooledfiles?userName=${IbmiUser}&fileName=${SplfName}"

try {
    if ($IsPSCore) {
        $SplfList = Invoke-RestMethod -Uri $ListUrl -Headers $HeadersJson `
                        -Method GET -SkipCertificateCheck
    } else {
        $SplfList = Invoke-RestMethod -Uri $ListUrl -Headers $HeadersJson -Method GET
    }
} catch {
    Write-Error "API call failed: $($_.Exception.Message)"
    exit 2
}

# ── Step 2 : Parse result ─────────────────────────────────────
$SplfFiles = $SplfList.spooledFiles

if (-not $SplfFiles -or $SplfFiles.Count -eq 0) {
    Write-Error "No spool file named '$SplfName' found for user '$IbmiUser'."
    exit 3
}

Write-Host "[2/3] Found $($SplfFiles.Count) spool file(s). Selecting the most recent..."

# The IBM i REST API returns entries in creation order; take the last (most recent)
$SplfEntry  = $SplfFiles[-1]
$SplfId     = $SplfEntry.id
$SplfJob    = if ($SplfEntry.jobName)           { $SplfEntry.jobName }           else { "N/A" }
$SplfUser   = if ($SplfEntry.jobUser)           { $SplfEntry.jobUser }           else { "N/A" }
$SplfNumber = if ($SplfEntry.spooledFileNumber) { $SplfEntry.spooledFileNumber } else { "N/A" }
$SplfDate   = if ($SplfEntry.creationDate)      { $SplfEntry.creationDate }      else { "N/A" }

Write-Host "    Spool ID      : $SplfId"
Write-Host "    Job           : $SplfJob / $SplfUser"
Write-Host "    File number   : $SplfNumber"
Write-Host "    Created       : $SplfDate"

if ([string]::IsNullOrEmpty($SplfId)) {
    Write-Error "Could not extract spool file ID from API response."
    exit 4
}

# ── Step 3 : Download content ─────────────────────────────────
# format=*TEXT  → plain text  (default, readable, ideal for log storage)
# format=*PDF   → PDF output  (change Accept to application/pdf if preferred)
Write-Host "[3/3] Downloading spool file to '$OutputFile'..."

$ContentUrl = "${BaseUrl}/spooledfiles/${SplfId}/content?format=*TEXT"

try {
    if ($IsPSCore) {
        Invoke-WebRequest -Uri $ContentUrl -Headers $HeadersText `
            -Method GET -SkipCertificateCheck -OutFile $OutputFile
    } else {
        Invoke-WebRequest -Uri $ContentUrl -Headers $HeadersText `
            -Method GET -OutFile $OutputFile
    }
} catch {
    Write-Error "Download failed: $($_.Exception.Message)"
    exit 5
}

# ── Done ──────────────────────────────────────────────────────
$FileInfo = Get-Item $OutputFile
Write-Host "────────────────────────────────────────────────"
Write-Host " SUCCESS"
Write-Host " File : $($FileInfo.FullName)"
Write-Host " Size : $([Math]::Round($FileInfo.Length / 1KB, 1)) KB"
Write-Host "────────────────────────────────────────────────"

# ── Optional: PDF download ────────────────────────────────────
# Replace the Invoke-WebRequest block above with this to get PDF output:
#
# $HeadersPdf     = @{
#     "Authorization" = "Basic $AuthBase64"
#     "Accept"        = "application/pdf"
# }
# $OutputFilePdf  = "${SplfName}_${Timestamp}.pdf"
# $ContentUrlPdf  = "${BaseUrl}/spooledfiles/${SplfId}/content?format=*PDF"
# if ($IsPSCore) {
#     Invoke-WebRequest -Uri $ContentUrlPdf -Headers $HeadersPdf `
#         -Method GET -SkipCertificateCheck -OutFile $OutputFilePdf
# } else {
#     Invoke-WebRequest -Uri $ContentUrlPdf -Headers $HeadersPdf `
#         -Method GET -OutFile $OutputFilePdf
# }
