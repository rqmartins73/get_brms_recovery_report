#!/usr/bin/env bash
# ============================================================
# get_qp1arcy.sh
# Downloads the BRMS Recovery Report spool file (QP1ARCY)
# from an IBM i V7R5 system via SSH + CPYSPLF + SCP.
#
# Usage  : ./get_qp1arcy.sh <IBM_i_IP> [-s secrets_file] [-d YYYY-MM-DD]
# Example: ./get_qp1arcy.sh 192.168.10.50
#          ./get_qp1arcy.sh 192.168.10.50 -s /etc/mysite.json
#          ./get_qp1arcy.sh 192.168.10.50 -d 2026-05-03
#          ./get_qp1arcy.sh 192.168.10.50 -s /etc/mysite.json -d 2026-05-03
#
# Depends: ssh, scp, jq
# Creds  : ibmiscrt.json  { "user": "...", "key": "/path/to/private_key" }
#
# Key setup (one-time):
#   ssh-keygen -t rsa -b 4096 -f ~/.ssh/ibmi_id_rsa
#   ssh-copy-id -i ~/.ssh/ibmi_id_rsa.pub <user>@<IBM_i_IP>
# ============================================================

set -euo pipefail

if [[ $# -lt 1 ]]; then
	echo "Usage: $0 <IBM_I_IP> [-s secrets_file] [-d YYYY-MM-DD]"
	exit 1
fi

IBMI_HOST="$1"
shift

CONFIG_FILE="./ibmiscrt.json"
TARGET_DATE=""

while getopts ":s:d:" opt; do
	case $opt in
		s) CONFIG_FILE="$OPTARG" ;;
		d) TARGET_DATE="$OPTARG" ;;
		:) echo "ERROR: Option -$OPTARG requires an argument"; exit 1 ;;
		\?) echo "ERROR: Unknown option: -$OPTARG"; exit 1 ;;
	esac
done

if [[ -n "$TARGET_DATE" && ! "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
	echo "ERROR: Date must be in YYYY-MM-DD format (e.g. 2026-05-03)"
	exit 1
fi

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

REMOTE_CMD="chmod +x /tmp/remote_get_qp1arcy.sh && /tmp/remote_get_qp1arcy.sh"
[[ -n "$TARGET_DATE" ]] && REMOTE_CMD+=" $TARGET_DATE"

remote_output=$(
	ssh "${SSH_OPTS[@]}" "${IBMI_USER}@${IBMI_HOST}" "$REMOTE_CMD"
)

if [[ -z "$remote_output" ]]; then
	echo "ERROR: Remote script did not return any file paths"
	exit 1
fi

remote_files=()
while IFS= read -r line; do
	line=$(echo "$line" | xargs)
	[[ -z "$line" ]] && continue
	remote_files+=("$line")
	scp "${SSH_OPTS[@]}" "${IBMI_USER}@${IBMI_HOST}:${line}" "$LOCAL_DIR/"
	echo "Downloaded: ${LOCAL_DIR}/$(basename "$line")"
done <<< "$remote_output"

rm_cmd="rm -f"
for f in "${remote_files[@]}"; do
	rm_cmd+=" '$f'"
done
rm_cmd+=" /tmp/remote_get_qp1arcy.sh"
ssh "${SSH_OPTS[@]}" "${IBMI_USER}@${IBMI_HOST}" "$rm_cmd" >/dev/null 2>&1 || true
