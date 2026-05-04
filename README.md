# get_brms_recovery_report

Downloads the latest IBM i BRMS spool files (**QP1ARCY** — Recovery Report, **QP1A2RCY** — Recovery Report II, **QP1AHS** — Backup History) via SSH/SCP.

No IBM i Navigator, REST API, SMTP, Outlook automation, or Posh-SSH module is required.

The workflow is:

1. Upload `remote_get_qp1arcy.sh` to the IBM i IFS temp path.
2. Run it remotely over SSH.
3. Locate the most recent `QP1ARCY`, `QP1A2RCY`, and `QP1AHS` spool files using `QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC` (optionally filtered by a specific date).
4. Copy each spool to a temporary IFS text file via `CPYSPLF` + `CPYTOSTMF`.
5. Download all three `.txt` files to the local machine using SCP, prefixed with the IBM i LPAR name.
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
| User authorised to `QP1ARCY`, `QP1A2RCY`, and `QP1AHS` | The SSH user must be able to see and copy all three spool files |
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
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

**Windows PowerShell:**
```powershell
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\id_rsa"
```

### Step 2 — Install the public key on the IBM i

**Linux/macOS** (`ssh-copy-id`):
```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub <user>@<IBM_i_IP>
```

**Windows PowerShell** (`Add-SSHKey.ps1`):
```powershell
.\Add-SSHKey.ps1 -User bccerqm -HostName 172.26.2.5 -KeyPath "$env:USERPROFILE\.ssh\id_rsa.pub"
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
    "ssh_key": "/home/rqmartins/.ssh/id_rsa",
    "local_dir": "/home/rqmartins"
}
```

### Windows

Copy `ibmiscrt.json.template.windows` to `ibmiscrt.json` in the same folder as the launcher and edit it:

```json
{
    "user": "bccerqm",
    "ssh_key": "%USERPROFILE%\\.ssh\\id_rsa",
    "local_dir": "%USERPROFILE%\\Downloads"
}
```

`%USERPROFILE%` is expanded automatically by the launcher script.

---

## Usage

### Linux/macOS

```bash
./get_qp1arcy.sh <IBM_i_IP> [-s secrets_file] [-d YYYY-MM-DD]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `IBM_i_IP` | Yes | — | IP address or hostname of the IBM i |
| `-s secrets_file` | No | `./ibmiscrt.json` | Path to the credentials JSON file |
| `-d YYYY-MM-DD` | No | latest available | Download spool files from this specific date |

Examples:

```bash
# Latest spool files, default secrets
./get_qp1arcy.sh 172.26.2.5

# Latest spool files, custom secrets
./get_qp1arcy.sh 172.26.2.5 -s /etc/client_a.json

# Spool files from a specific date
./get_qp1arcy.sh 172.26.2.5 -d 2026-05-03

# Specific date and custom secrets
./get_qp1arcy.sh 172.26.2.5 -s /etc/client_a.json -d 2026-05-03
```

### Windows PowerShell

```powershell
powershell -ExecutionPolicy Bypass -File .\get_qp1arcy.ps1 -HostName <IBM_i_IP> [-SecretsFile <path>] [-Date YYYY-MM-DD]
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-HostName` | Yes | — | IP address or hostname of the IBM i |
| `-SecretsFile` | No | `ibmiscrt.json` | Filename or path to the credentials JSON file |
| `-Date` | No | latest available | Download spool files from this specific date (`YYYY-MM-DD`) |

If `-SecretsFile` is a relative path or filename, it is resolved relative to the script folder. Absolute paths are used as-is.

Examples:

```powershell
# Latest spool files, default secrets
powershell -ExecutionPolicy Bypass -File .\get_qp1arcy.ps1 -HostName 172.26.2.5

# Latest spool files, custom secrets
powershell -ExecutionPolicy Bypass -File .\get_qp1arcy.ps1 -HostName 172.26.2.5 -SecretsFile client_a.json

# Spool files from a specific date
powershell -ExecutionPolicy Bypass -File .\get_qp1arcy.ps1 -HostName 172.26.2.5 -Date 2026-05-03

# Specific date and custom secrets
powershell -ExecutionPolicy Bypass -File .\get_qp1arcy.ps1 -HostName 172.26.2.5 -SecretsFile client_a.json -Date 2026-05-03
```

---

## Output

Three files are downloaded to the configured local directory, one per spool file.

Filename format:

```text
<LPAR>_QP1ARCY_YYYYMMDD_HHMMSS.txt
<LPAR>_QP1A2RCY_YYYYMMDD_HHMMSS.txt
<LPAR>_QP1AHS_YYYYMMDD_HHMMSS.txt
```

The node name is the IBM i **Default local location** name (`LCLLOCNAME` network attribute, read from `DSPNETA`), uppercased. This is unique per node in a PowerHA cluster, unlike the system name which may be shared across all nodes. Falls back to `uname -n` if `DSPNETA` fails. The timestamp reflects the spool file's own `CREATE_TIMESTAMP` on the IBM i, not the time of download.

Example:

```text
SYSPROD_QP1ARCY_20260501_162849.txt
SYSPROD_QP1A2RCY_20260501_162849.txt
SYSPROD_QP1AHS_20260501_162849.txt
```

---

## How it works internally

On startup, `remote_get_qp1arcy.sh` reads the **Default local location** name from `DSPNETA` (the `LCLLOCNAME` network attribute) once to use as the node prefix in output filenames. This value is unique per node in a PowerHA cluster, unlike the system name which is shared across all nodes. Falls back to `uname -n` if `DSPNETA` is unavailable. It then runs the following steps for each of the three spool files (`QP1ARCY`, `QP1A2RCY`, `QP1AHS`):

1. Creates a temporary physical file in `QGPL` to store the spool metadata.
2. Uses `RUNSQLSTM` with `QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC` to retrieve the job name, file number, and `CREATE_TIMESTAMP` of the target spool — the most recent one, or the most recent one on a specific date if `-d` / `-Date` was passed.
3. Creates another temporary physical file in `QGPL` for the spool content.
4. Runs `CPYSPLF` to copy the spool into that physical file.
5. Runs `CPYTOSTMF` to export the physical file member to an IFS text file. The filename is `<LPAR>_<SPLF>_<YYYYMMDD_HHMMSS>.txt`, where the timestamp comes from the spool's own `CREATE_TIMESTAMP`, not the download time.
6. Prints the IFS file path to stdout (one line per spool file).

The launcher script iterates over the returned paths, downloads each file with `scp`, and removes all temporary remote files.

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

### No spool file found for the specified date

The remote script exits with an error if no spool exists for the requested date (checked for each of `QP1ARCY`, `QP1A2RCY`, `QP1AHS` in sequence):

```
ERROR: No spool file found for QP1ARCY
```

Verify that a BRMS backup ran on that date and that the spool files have not been cleared from the output queue. Omit `-d` / `-Date` to retrieve the most recent available files.

### JSON parsing fails (Linux/macOS)

Validate that `ibmiscrt.json` has no trailing comma after the last field.

Invalid:
```json
{
    "user": "bccerqm",
    "ssh_key": "/home/rqmartins/.ssh/id_rsa",
    "local_dir": "/home/rqmartins",
}
```

Valid:
```json
{
    "user": "bccerqm",
    "ssh_key": "/home/rqmartins/.ssh/id_rsa",
    "local_dir": "/home/rqmartins"
}
```

---

## Notes

- Password SSH authentication is not used; key-based SSH is required.
- The Windows script uses native `ssh.exe` and `scp.exe`.

- The script downloads `QP1ARCY` (Recovery Report), `QP1A2RCY` (Recovery Report II), and `QP1AHS` (Backup History). If any spool does not exist the remote script exits with an error.

---

## Author

Ricardo Martins  
IBM Power Technical Leader @ Blue Chip Portugal  
IBM Champion 2025 | 2026
