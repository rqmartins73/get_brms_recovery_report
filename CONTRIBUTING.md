# Contributing

Contributions are welcome. Please read these guidelines before opening an issue or pull request.

## IBM i / PASE Compatibility

`get_qp1arcy.sh` must remain compatible with IBM i PASE. Before submitting changes:

- Avoid Bash-only constructs: no `readarray`, `mapfile`, process substitution (`<()`), or `/proc` paths.
- Use POSIX-safe syntax and `IFS`-based loops where iteration is needed.
- Test against IBM i V7R5 if possible; otherwise note the limitation in the PR.

## Reporting Issues

Please include:

- IBM i OS version (`DSPPTF`)
- HTTP Server configuration (ADMIN instance active, port 2005 reachable)
- Script version (Bash or PowerShell, and shell/PS version)
- The exact error message or HTTP response code
- Sanitised output (remove credentials and hostnames)

## Pull Requests

1. Fork the repository and create a feature branch from `main`.
2. Keep changes focused — one concern per PR.
3. Update `README.md` if behaviour or usage changes.
4. Do **not** commit `ibmiscrt.json` or any file containing real credentials.

## Security

If you discover a security issue, please report it privately via the GitHub Security Advisories feature rather than opening a public issue.
