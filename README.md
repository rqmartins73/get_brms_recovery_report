# get_brms_recovery_report

Downloads the IBM i BRMS Recovery Report spool file (**QP1ARCY**) via the IBM i Access REST API — no client software required beyond `curl`/`jq` (Bash) or PowerShell 5.1+.

Both scripts follow the same three-step flow against `https://<IP>:2005/ibmi/v1`:

1. **List** spool files matching `QP1ARCY` for the authenticated user
2. **Select** the most recent entry (IBM i returns them in creation order)
3. **Download** the content as plain text (or optionally PDF)

---

## Prerequisites

### IBM i side

| Requirement | How to verify |
|---|---|
| IBM i V7R5 or later | `DSPPTF` |
| HTTP Server (ADMIN instance) running | `WRKACTJOB SBS(QHTTPSVR)` |
| Port 2005 open on firewall | `NETSTAT *CNN` |
| User profile has `*USE` on `QBRMS` output queue | `WRKOBJPDM QBRMS *OUTQ` |
| REST API enabled | IBM i Navigator → HTTP Servers |

### Client side

| Script | Requirements |
|---|---|
| `get_qp1arcy.sh` | Bash, `curl`, `jq` |
| `Get-QP1ARCY.ps1` | PowerShell 5.1 (Windows) or PowerShell 7+ (cross-platform) |

---

## Setup

1. Copy the credentials template and fill in your IBM i credentials:

```bash
cp ibmiscrt.json.template ibmiscrt.json
```

```json
{
  "user": "QBRMS",
  "password": "yourpassword"
}
```

> `ibmiscrt.json` is listed in `.gitignore` and will never be committed.

2. Make the Bash script executable (Linux/PASE):

```bash
chmod +x get_qp1arcy.sh
```

---

## Usage

### Bash

```bash
./get_qp1arcy.sh <IBM_i_IP>
```

```bash
./get_qp1arcy.sh 192.168.10.50
```

### PowerShell

```powershell
.\Get-QP1ARCY.ps1 192.168.10.50
```

If your execution policy blocks unsigned scripts on Windows:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Get-QP1ARCY.ps1 192.168.10.50
```

### Output

Both scripts save the report to the current directory as:

```
QP1ARCY_YYYYMMDD_HHMMSS.txt
```

---

## Notes

**SSL:** Both scripts skip certificate validation (`-k` / `-SkipCertificateCheck`) because IBM i V7R5 ships with a self-signed certificate by default. Replace with a trusted certificate in production environments.

**PowerShell editions:** The `.ps1` script detects the PowerShell edition at runtime and uses the appropriate SSL bypass method for PS 5.1 (ServicePointManager) and PS 7+ (-SkipCertificateCheck).

**PDF output:** A commented-out PDF block is included at the bottom of both scripts. To use it, swap `format=*TEXT` / `Accept: text/plain` for `format=*PDF` / `Accept: application/pdf`.

---

## IBM i Compatibility

`get_qp1arcy.sh` is written to be compatible with IBM i PASE (Portable Application Solutions Environment). It avoids Linux-only constructs (`readarray`, `/proc`, `systemctl`) and uses POSIX-safe syntax throughout.

---

## License

MIT — see [LICENSE](LICENSE).

---
## Author

Ricardo Martins  
IBM Power Technical Leader @ Blue Chip Portugal  
IBM Champion 2025 | 2026