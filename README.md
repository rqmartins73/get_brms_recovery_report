# get_brms_recovery_report

Downloads the latest IBM i BRMS Recovery Report spool file (**QP1ARCY**) via SSH/SCP.

No IBM i Navigator, REST API, SMTP, Outlook automation, or Posh-SSH module is required.

The workflow is:

1. Upload `remote_get_qp1arcy.sh` to the IBM i IFS temp path.
2. Run it remotely over SSH.
3. Locate the most recent `QP1ARCY` spool file using `QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC`.
4. Copy the spool content to a temporary IFS text file via `CPYSPLF` + `CPYTOSTMF`.
5. Download the generated `.txt` file to the local machine using SCP.
6. Remove all temporary files from the IBM i.

---

## Files

| File | Purpose |
|---|---|
| `Add-SSHKey.ps1` | One-time setup: installs your SSH public key on the IBM i user account |
| `get_qp1arcy.sh` | Linux/macOS launcher script |
| `get_qp1arcy.ps1` | Windows PowerShell launcher script |
| `remote_get_qp1arcy.sh` | IBM i PASE script — uploaded and executed by the launcher scripts |
| `ibmiscrt.json.template.linux` | Config template for Linux/macOS (`ibmiscrt.json`) |
| `ibmiscrt.json.template.windows` | Config template for Windows (`ibmiscrt.json`) |

---

## Prerequisites

### IBM i side

| Requirement | Notes |
|---|---|
| IBM i V7R5 | Tested with IBM i V7R5 |
| SSH server active | Typically runs under `QSYSWRK` as `SSHD` |
| PASE available | Required to run `/QOpenSys/pkgs/bin/bash` |
| Home directory created | `/home/<user>` must exist before running `Add-SSHKey.ps1` |
| User authorised to `QP1ARCY` | The SSH user must be able to see and copy that spool file |
| Authority to create/delete in `QGPL` | The remote script creates temporary physical files and removes them at exit |

### Client side

| Platform | Requirements |
|---|---|
| Linux/macOS | Bash, `ssh`, `scp`, `jq` |
| Windows | PowerShell, OpenSSH client (`ssh.exe` and `scp.exe` — included with Windows 10/11) |

> Windows does **not** require Posh-SSH. Both scripts use the native OpenSSH client.

---

## One-time setup: SSH key authentication

SSH key authentication must be configured before running the launcher scripts. The user's home directory (`/home/<user>`) must already exist on the IBM i.

### Step 1 — Generate an SSH key pair (if you do not already have one)

**Linux/macOS:**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ibmcloud_rsa
```

**Windows PowerShell:**
```powershell
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\ibmcloud_rsa"
```

### Step 2 — Install the public key on the IBM i

**Linux/macOS** (`ssh-copy-id`):
```bash
ssh-copy-id -i ~/.ssh/ibmcloud_rsa.pub <user>@<IBM_i_IP>
```

**Windows PowerShell** (`Add-SSHKey.ps1`):
```powershell
.\Add-SSHKey.ps1 -User bccerqm -HostName 172.26.2.5 -KeyPath "$env:USERPROFILE\.ssh\ibmcloud_rsa.pub"
```

`Add-SSHKey.ps1` will:
- Create `~/.ssh` on the IBM i with the correct permissions (`700`).
- Copy the public key, strip any Windows line endings, and append it to `authorized_keys` (`600`).

> **Note:** The first connection will prompt for the user's IBM i password. Subsequent connections will use the key.

---

## Configuration

### Linux/macOS

Copy `ibmiscrt.json.template.linux` to `ibmiscrt.json` in the same folder as the launcher and edit it:

```json
{
    "user": "bccerqm",
    "ssh_key": "/home/rqmartins/.ssh/ibmcloud_rsa",
    "local_dir": "/home/rqmartins"
}
```

### Windows

The Windows script (`get_qp1arcy.ps1`) has its settings at the top of the file. Edit those variables directly:

```powershell
$IbmiUser = "bccerqm"
$IbmiHost = "172.26.2.5"
$SshKey   = "$env:USERPROFILE\.ssh\ibmcloud_rsa"
$LocalDir = "$env:USERPROFILE\Downloads"
```

`ibmiscrt.json.template.windows` is provided as a reference but is not used by the PowerShell script.

---

## Usage

### Linux/macOS

```bash
./get_qp1arcy.sh 172.26.2.5
```

The IBM i IP address is passed as the first argument. Config is read from `ibmiscrt.json`.

### Windows PowerShell

Edit the variables at the top of `get_qp1arcy.ps1`, then run from the folder containing the script and `remote_get_qp1arcy.sh`:

```powershell
powershell -ExecutionPolicy Bypass -File .\get_qp1arcy.ps1
```

---

## Output

The downloaded file is saved in the configured local directory.

Filename format:

```text
QP1ARCY_YYYYMMDD_HHMMSS.txt
```

Example:

```text
QP1ARCY_20260501_162849.txt
```

---

## How it works internally

The remote IBM i script (`remote_get_qp1arcy.sh`):

1. Creates a temporary physical file in `QGPL` to store the latest spool metadata.
2. Uses `RUNSQLSTM` with `QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC` to identify the most recent `QP1ARCY` spool file.
3. Creates another temporary physical file in `QGPL` for the spool content.
4. Runs `CPYSPLF` to copy the spool into that physical file.
5. Runs `CPYTOSTMF` to export the physical file member to an IFS text file.
6. Prints the IFS file path to stdout.

The launcher script downloads that file with `scp` and removes all temporary remote files.

---

## Troubleshooting

### PowerShell blocks the script

```powershell
powershell -ExecutionPolicy Bypass -File .\get_qp1arcy.ps1
```

### Host key verification failed

Remove the stale entry and reconnect:

```bash
ssh-keygen -R 172.26.2.5
```

Rerun the script and accept the new fingerprint only if it matches the expected IBM i system.

### `remote_get_qp1arcy.sh` not found

Ensure this file is in the same folder as the launcher script.

### `Add-SSHKey.ps1` fails with "Failed to create .ssh on remote"

The user's home directory (`/home/<user>`) does not exist on the IBM i. Ask the system administrator to create it before running `Add-SSHKey.ps1`.

### JSON parsing fails (Linux/macOS)

Validate that `ibmiscrt.json` has no trailing comma after the last field.

Invalid:
```json
{
    "user": "bccerqm",
    "ssh_key": "/home/rqmartins/.ssh/ibmcloud_rsa",
    "local_dir": "/home/rqmartins",
}
```

Valid:
```json
{
    "user": "bccerqm",
    "ssh_key": "/home/rqmartins/.ssh/ibmcloud_rsa",
    "local_dir": "/home/rqmartins"
}
```

---

## Notes

- Password SSH authentication is not used; key-based SSH is required.
- Email sending is intentionally not included.
- The Windows script uses native `ssh.exe` and `scp.exe` — no Outlook, SMTP, Graph API, or Posh-SSH.
- `ibmiscrt.json` must not be committed to Git (it contains local paths and credentials).
- The script targets the `QP1ARCY` spool file specifically.

---

## Author

Ricardo Martins  
IBM Power Technical Leader @ Blue Chip Portugal  
IBM Champion 2025 | 2026
