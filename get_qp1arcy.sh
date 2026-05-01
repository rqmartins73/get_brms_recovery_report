#!/bin/bash
# ============================================================
# get_qp1arcy.sh
# Downloads the BRMS Recovery Report spool file (QP1ARCY)
# from an IBM i V7R5 system via SSH + CPYSPLF + SCP.
#
# Usage  : ./get_qp1arcy.sh <IBM_i_IP>
# Example: ./get_qp1arcy.sh 192.168.10.50
#
# Depends: ssh, scp, sshpass, jq
# Creds  : ibmiscrt.json  { "user": "...", "password": "..." }
#
# Note: SSH key auth is recommended for production use.
#       To set up: ssh-copy-id <user>@<IBM_i_IP>
#       Then remove sshpass and use plain ssh/scp below.
# ============================================================

set -euo pipefail

# ── Parameters ────────────────────────────────────────────────
IP="${1:?ERROR: IBM i IP address required.  Usage: $0 <IP>}"
CREDS_FILE="ibmiscrt.json"
SPLF_NAME="QP1ARCY"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${SPLF_NAME}_${TIMESTAMP}.txt"
IFS_TMP="/tmp/${SPLF_NAME}_${TIMESTAMP}_$$.txt"

# IBM i PASE command paths
DB2_CMD="/QOpenSys/usr/bin/db2"
SYSTEM_CMD="/QOpenSys/usr/bin/system"

# ── Dependency check ──────────────────────────────────────────
for cmd in ssh scp sshpass jq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' is required but not installed."; exit 1; }
done

# ── Read credentials ──────────────────────────────────────────
if [[ ! -f "$CREDS_FILE" ]]; then
    echo "ERROR: Credentials file '$CREDS_FILE' not found in $(pwd)"
    exit 1
fi

IBMI_USER=$(jq -r '.user'     "$CREDS_FILE")
IBMI_PASS=$(jq -r '.password' "$CREDS_FILE")

if [[ -z "$IBMI_USER" || "$IBMI_USER" == "null" ]]; then
    echo "ERROR: 'user' key missing or empty in $CREDS_FILE"; exit 1
fi
if [[ -z "$IBMI_PASS" || "$IBMI_PASS" == "null" ]]; then
    echo "ERROR: 'password' key missing or empty in $CREDS_FILE"; exit 1
fi

# ── SSH helpers ───────────────────────────────────────────────
# Password is passed via SSHPASS env var (avoids it showing in process list)
export SSHPASS="$IBMI_PASS"
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=no -o ConnectTimeout=10"

ssh_run() { sshpass -e ssh  $SSH_OPTS "${IBMI_USER}@${IP}" "$1"; }
scp_get() { sshpass -e scp  $SSH_OPTS "${IBMI_USER}@${IP}:$1" "$2"; }

# ── Header ────────────────────────────────────────────────────
echo "────────────────────────────────────────────────"
echo " IBM i BRMS Report Downloader"
echo " Host  : ${IP}"
echo " User  : ${IBMI_USER}"
echo " Spool : ${SPLF_NAME}"
echo " Mode  : SSH + CPYSPLF + SCP"
echo "────────────────────────────────────────────────"

# ── Step 1 : Locate most recent spool file via SQL ────────────
echo "[1/3] Locating most recent ${SPLF_NAME} spool file..."

# Query QSYS2.OUTPUT_QUEUE_ENTRIES; result row: JOBNBR/JOBUSER/JOBNAME|SPLNBR
SPOOL_ROW=$(ssh_run \
    "${DB2_CMD} \"SELECT TRIM(CHAR(JOB_NUMBER))||'/'||TRIM(JOB_USER)||'/'||TRIM(JOB_NAME)||'|'||TRIM(CHAR(SPOOLED_FILE_NUMBER)) FROM QSYS2.OUTPUT_QUEUE_ENTRIES WHERE SPOOLED_FILE_NAME='${SPLF_NAME}' AND JOB_USER='${IBMI_USER}' ORDER BY CREATION_TIMESTAMP DESC FETCH FIRST 1 ROW ONLY\" 2>/dev/null | grep '|' | tr -d ' '") \
    || { echo "ERROR: SSH failed or db2 query failed (exit $?)."; exit 2; }

if [[ -z "$SPOOL_ROW" ]]; then
    echo "ERROR: No ${SPLF_NAME} spool file found for user ${IBMI_USER}."
    echo "       Ensure BRMS has generated the recovery report."
    exit 3
fi

JOB_ID=$(echo "$SPOOL_ROW"  | cut -d'|' -f1)
SPLF_NBR=$(echo "$SPOOL_ROW" | cut -d'|' -f2)

echo "    Job    : ${JOB_ID}"
echo "    Spool# : ${SPLF_NBR}"

# ── Step 2 : Copy spool to IFS ────────────────────────────────
echo "[2/3] Copying spool to IFS temp file..."

ssh_run "${SYSTEM_CMD} \"CPYSPLF FILE(${SPLF_NAME}) TOFILE(*IFS) TOSTMF('${IFS_TMP}') STMFOPT(*REPLACE) JOB(${JOB_ID}) SPLNBR(${SPLF_NBR}) WSCST(*AUTOCVT)\"" \
    || { echo "ERROR: CPYSPLF failed — check job ID '${JOB_ID}' and spool number '${SPLF_NBR}'."; exit 4; }

# ── Step 3 : Download via SCP and clean up ────────────────────
echo "[3/3] Downloading '${IFS_TMP}' → '${OUTPUT_FILE}'..."

scp_get "$IFS_TMP" "$OUTPUT_FILE" \
    || { echo "ERROR: SCP download failed."; exit 5; }

ssh_run "rm -f '${IFS_TMP}'" || true

# ── Done ──────────────────────────────────────────────────────
echo "────────────────────────────────────────────────"
echo " SUCCESS"
echo " File : $(pwd)/${OUTPUT_FILE}"
echo " Size : $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "────────────────────────────────────────────────"
