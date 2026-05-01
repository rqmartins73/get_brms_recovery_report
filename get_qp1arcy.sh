#!/usr/bin/env bash
# ============================================================
# get_qp1arcy.sh
# Downloads the BRMS Recovery Report spool file (QP1ARCY)
# from an IBM i V7R5 system via SSH + CPYSPLF + SCP.
#
# Usage  : ./get_qp1arcy.sh <IBM_i_IP>
# Example: ./get_qp1arcy.sh 192.168.10.50
#
# Depends: ssh, scp, jq
# Creds  : ibmiscrt.json  { "user": "...", "key": "/path/to/private_key" }
#
# Key setup (one-time):
#   ssh-keygen -t rsa -b 4096 -f ~/.ssh/ibmi_id_rsa
#   ssh-copy-id -i ~/.ssh/ibmi_id_rsa.pub <user>@<IBM_i_IP>
# ============================================================

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 IBM_I_IP"
	exit 1
fi

IBMI_HOST="$1"
CONFIG_FILE="./ibmiscrt.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "ERROR: Config file not found: $CONFIG_FILE"
	exit 1
fi

IBMI_USER=$(jq -r '.user' "$CONFIG_FILE")
SSH_KEY=$(jq -r '.ssh_key' "$CONFIG_FILE")
LOCAL_DIR=$(jq -r '.local_dir' "$CONFIG_FILE")

if [[ -z "$IBMI_USER" || "$IBMI_USER" == "null" || -z "$SSH_KEY" || "$SSH_KEY" == "null" || -z "$LOCAL_DIR" || "$LOCAL_DIR" == "null" ]]; then
	echo "ERROR: Invalid ibmiscrt.json. Required fields: user, ssh_key, local_dir"
	exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
	echo "ERROR: SSH key not found: $SSH_KEY"
	exit 1
fi

if [[ ! -f "./remote_get_qp1arcy.sh" ]]; then
	echo "ERROR: remote_get_qp1arcy.sh not found in current directory"
	exit 1
fi

mkdir -p "$LOCAL_DIR"

SSH_OPTS=(
	-i "$SSH_KEY"
	-o BatchMode=yes
	-o StrictHostKeyChecking=accept-new
)

scp "${SSH_OPTS[@]}" remote_get_qp1arcy.sh "${IBMI_USER}@${IBMI_HOST}:/tmp/remote_get_qp1arcy.sh"

remote_file=$(
	ssh "${SSH_OPTS[@]}" "${IBMI_USER}@${IBMI_HOST}" \
	"chmod +x /tmp/remote_get_qp1arcy.sh && /tmp/remote_get_qp1arcy.sh"
)

remote_file=$(echo "$remote_file" | tail -1 | xargs)

if [[ -z "$remote_file" ]]; then
	echo "ERROR: Remote script did not return a file path"
	exit 1
fi

scp "${SSH_OPTS[@]}" "${IBMI_USER}@${IBMI_HOST}:${remote_file}" "$LOCAL_DIR/"

ssh "${SSH_OPTS[@]}" "${IBMI_USER}@${IBMI_HOST}" \
	"rm -f '$remote_file' /tmp/remote_get_qp1arcy.sh" >/dev/null 2>&1 || true

echo "Downloaded: ${LOCAL_DIR}/$(basename "$remote_file")"
