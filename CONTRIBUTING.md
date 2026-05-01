# Contributing

Contributions are welcome. Please read these guidelines before opening an issue or pull request.

## IBM i / PASE Compatibility

The remote commands sent by `get_qp1arcy.sh` execute inside IBM i PASE. Before submitting changes:

- Use full PASE paths (`/QOpenSys/usr/bin/db2`, `/QOpenSys/usr/bin/system`).
- Avoid Bash-only constructs on the remote side: no `readarray`, `mapfile`, process substitution (`<()`), or `/proc` paths.
- Test against IBM i V7R5 if possible; otherwise note the limitation in the PR.

## Reporting Issues

Please include:

- IBM i OS version (`DSPPTF`)
- Whether SSH is reachable from the client (`ssh -i <key> <user>@<host> echo ok`)
- Whether `db2` is available on the IBM i (`ls /QOpenSys/usr/bin/db2`)
- Script version (Bash or PowerShell) and shell/PS version
- The exact error message or exit code
- Sanitised output (remove credentials, hostnames, and key paths)

## Pull Requests

1. Fork the repository and create a feature branch from `main`.
2. Keep changes focused — one concern per PR.
3. Update `README.md` if behaviour or usage changes.
4. Do **not** commit `ibmiscrt.json` or any file containing real credentials or private keys.

## Security

If you discover a security issue, please report it privately via the GitHub Security Advisories feature rather than opening a public issue.
