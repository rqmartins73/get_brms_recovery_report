$IbmiUser = "bccerqm"
$IbmiHost = "172.26.2.5"
$SshKey   = "$env:USERPROFILE\.ssh\ibmcloud_rsa"
$LocalDir = "$env:USERPROFILE\Downloads"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RemoteScript = Join-Path $ScriptDir "remote_get_qp1arcy.sh"
$RemotePath   = "/tmp/remote_get_qp1arcy.sh"

scp -i $SshKey -o BatchMode=yes -o StrictHostKeyChecking=accept-new `
	$RemoteScript "${IbmiUser}@${IbmiHost}:$RemotePath"

$RemoteFile = ssh -i $SshKey -o BatchMode=yes -o StrictHostKeyChecking=accept-new `
	"${IbmiUser}@${IbmiHost}" `
	"chmod +x $RemotePath && $RemotePath"

$RemoteFile = $RemoteFile.Trim()

scp -i $SshKey -o BatchMode=yes -o StrictHostKeyChecking=accept-new `
	"${IbmiUser}@${IbmiHost}:$RemoteFile" $LocalDir

ssh -i $SshKey -o BatchMode=yes -o StrictHostKeyChecking=accept-new `
	"${IbmiUser}@${IbmiHost}" `
	"rm -f '$RemoteFile' '$RemotePath'" | Out-Null

Write-Host "Downloaded: $LocalDir\$(Split-Path $RemoteFile -Leaf)"
