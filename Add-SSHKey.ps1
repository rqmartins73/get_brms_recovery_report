param(
    [Parameter(Mandatory=$true)]
    [string]$User,

    [Parameter(Mandatory=$true)]
    [string]$HostName,

    [Parameter(Mandatory=$true)]
    [string]$KeyPath
)

# Verifica existência da chave pública
if (!(Test-Path $KeyPath)) {
    Write-Host "❌ Public key not found at $KeyPath"
    exit 1
}

# Normaliza finais de linha para LF e escreve ficheiro temporário local
$keyContent = Get-Content -Raw -Path $KeyPath
$keyContent = $keyContent -replace "`r`n", "`n" -replace "`r", "`n"
$tempLocal = Join-Path $env:TEMP ("_pubkey_{0}.tmp" -f (Get-Random))
Set-Content -Path $tempLocal -Value $keyContent -Encoding UTF8

Write-Host "🔐 Preparing to copy SSH key to $User@$HostName ..."
$remoteDir = "/home/$User/.ssh"
$remoteTmp = "$remoteDir/_tmp_pubkey"
$authorized = "$remoteDir/authorized_keys"

# 1) Garantir que a pasta .ssh existe (cria com permissões seguras)
ssh ${User}@${HostName} "mkdir -p $remoteDir && chmod 700 $remoteDir"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create $remoteDir on remote. Check SSH connectivity and permissions."
    Remove-Item -Path $tempLocal -ErrorAction SilentlyContinue
    exit 1
}

# 2) Copiar o ficheiro temporário para o remoto via scp
scp $tempLocal ${User}@${HostName}:$remoteTmp
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ scp failed. The remote may not accept scp or network/credentials failed."
    Remove-Item -Path $tempLocal -ErrorAction SilentlyContinue
    exit 1
}

# 3) Executar um único comando remoto (uma linha) para remover CR, acrescentar à authorized_keys, ajustar permissões e limpar
#    Usamos uma única linha para evitar problemas com CRLF em here-docs.
$singleLineCmd = "tr -d '\r' < $remoteTmp >> $authorized; touch $authorized; chown ${User}:${User} $authorized 2>/dev/null || true; chmod 600 $authorized 2>/dev/null || true; rm -f $remoteTmp"

ssh ${User}@${HostName} $singleLineCmd
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ SSH key installed on ${User}@${HostName} ($authorized)"
    Remove-Item -Path $tempLocal -ErrorAction SilentlyContinue
    exit 0
} else {
    Write-Host "❌ There was an error appending the key on the remote. Check SSH output above."
    Remove-Item -Path $tempLocal -ErrorAction SilentlyContinue
    exit 1
}
