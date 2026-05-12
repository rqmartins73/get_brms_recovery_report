# Changelog

All notable changes to this project will be documented in this file.
Follows [Semantic Versioning](https://semver.org/).

---

## [1.1.0] — 2026-05-12

### Added
- `-UploadToCOS` flag on `get_qp1arcy.ps1`: uploads each downloaded spool file to IBM COS after SCP transfer
- Bucket subfolder derived from the spool's `CREATE_TIMESTAMP` (`YYYYMM`), not the download date
- COS fields in `ibmiscrt.json` templates: `cos_endpoint`, `cos_region`, `cos_bucket`, `cos_access_key`, `cos_secret_key`
- README: IBM Cloud Object Storage section with endpoint table, credential instructions, and folder structure example
- Uses `AWS.Tools.S3` PowerShell module (S3-compatible API); no AWS account required

---

## [1.0.0] — 2026-05-11

### Added
- `-Version` / `--version` flag on all scripts (`get_qp1arcy.ps1`, `Add-SSHKey.ps1`, `get_qp1arcy.sh`, `remote_get_qp1arcy.sh`) — outputs structured JSON block
- `VERSION` and `CHANGELOG.md` files
- Progress and error messages on all silent exit points in `get_qp1arcy.ps1`
- Fixed `Add-SSHKey.ps1` emoji encoding causing parse failures on Windows PowerShell 5.1
- BRMS spool download includes `QP1ARCY`, `QP1A2RCY`, and `QP1AHS`
- Spool filename uses IBM i `CREATE_TIMESTAMP` and `LCLLOCNAME` (DSPNETA) as prefix
- Optional `-d YYYY-MM-DD` date filter on `get_qp1arcy.ps1` and `get_qp1arcy.sh`
