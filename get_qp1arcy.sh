#!/bin/bash
# ============================================================
# get_qp1arcy.sh
# Downloads the BRMS Recovery Report spool file (QP1ARCY)
# from an IBM i V7R5 system via REST API.
#
# Usage  : ./get_qp1arcy.sh <IBM_i_IP>
# Example: ./get_qp1arcy.sh 192.168.10.50
#
# Depends: curl, jq
# Creds  : ibmiscrt.json  { "user": "...", "password": "..." }
# ============================================================

set -euo pipefail

# ── Parameters ────────────────────────────────────────────────
IP="${1:?ERROR: IBM i IP address required.  Usage: $0 <IP>}"
CREDS_FILE="ibmiscrt.json"
SPLF_NAME="QP1ARCY"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${SPLF_NAME}_${TIMESTAMP}.txt"
TMP_LIST="/tmp/ibmi_splf_list_$$.json"
BASE_URL="https://${IP}:2003/ibmi/v1"

# ── Dependency check ──────────────────────────────────────────
for cmd in curl jq; do
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
    echo "ERROR: 'user' key missing or empty in $CREDS_FILE"
    exit 1
fi
if [[ -z "$IBMI_PASS" || "$IBMI_PASS" == "null" ]]; then
    echo "ERROR: 'password' key missing or empty in $CREDS_FILE"
    exit 1
fi

# ── Step 1 : List spool files ─────────────────────────────────
echo "────────────────────────────────────────────────"
echo " IBM i BRMS Report Downloader"
echo " Host     : ${IP}"
echo " User     : ${IBMI_USER}"
echo " Spool    : ${SPLF_NAME}"
echo "────────────────────────────────────────────────"
echo "[1/3] Querying spool file list..."

HTTP_CODE=$(curl -s -k \
    --user "${IBMI_USER}:${IBMI_PASS}" \
    -H "Accept: application/json" \
    -o "$TMP_LIST" \
    -w "%{http_code}" \
    "${BASE_URL}/spooledfiles?userName=${IBMI_USER}&fileName=${SPLF_NAME}") \
    || { echo "ERROR: curl failed (exit $?) — check host, port, and network connectivity."; rm -f "$TMP_LIST"; exit 2; }

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "ERROR: API call failed — HTTP ${HTTP_CODE}"
    echo "Response body:"
    cat "$TMP_LIST"
    rm -f "$TMP_LIST"
    exit 2
fi

# ── Step 2 : Parse result ─────────────────────────────────────
SPLF_COUNT=$(jq '.spooledFiles | length' "$TMP_LIST" 2>/dev/null || echo "0")

if [[ "$SPLF_COUNT" -eq 0 ]]; then
    echo "ERROR: No spool file named '${SPLF_NAME}' found for user '${IBMI_USER}'."
    rm -f "$TMP_LIST"
    exit 3
fi

echo "[2/3] Found ${SPLF_COUNT} spool file(s). Selecting the most recent..."

# The IBM i REST API returns entries in creation order; take the last (most recent)
SPLF_ID=$(jq -r '.spooledFiles[-1].id'               "$TMP_LIST")
SPLF_JOB=$(jq -r '.spooledFiles[-1].jobName    // "N/A"' "$TMP_LIST")
SPLF_USR=$(jq -r '.spooledFiles[-1].jobUser    // "N/A"' "$TMP_LIST")
SPLF_NBR=$(jq -r '.spooledFiles[-1].spooledFileNumber // "N/A"' "$TMP_LIST")
SPLF_CRE=$(jq -r '.spooledFiles[-1].creationDate // "N/A"' "$TMP_LIST")

echo "    Spool ID      : ${SPLF_ID}"
echo "    Job           : ${SPLF_JOB} / ${SPLF_USR}"
echo "    File number   : ${SPLF_NBR}"
echo "    Created       : ${SPLF_CRE}"

rm -f "$TMP_LIST"

if [[ -z "$SPLF_ID" || "$SPLF_ID" == "null" ]]; then
    echo "ERROR: Could not extract spool file ID from API response."
    exit 4
fi

# ── Step 3 : Download content ─────────────────────────────────
# format=*TEXT  → plain text  (default, readable, ideal for log storage)
# format=*PDF   → PDF output  (uncomment the PDF block below if preferred)
echo "[3/3] Downloading spool file to '${OUTPUT_FILE}'..."

HTTP_CODE=$(curl -s -k \
    --user "${IBMI_USER}:${IBMI_PASS}" \
    -H "Accept: text/plain" \
    -o "$OUTPUT_FILE" \
    -w "%{http_code}" \
    "${BASE_URL}/spooledfiles/${SPLF_ID}/content?format=%2ATEXT") \
    || { echo "ERROR: curl failed (exit $?) — could not download spool content."; rm -f "$OUTPUT_FILE"; exit 5; }

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "ERROR: Download failed — HTTP ${HTTP_CODE}"
    echo "Response:"
    cat "$OUTPUT_FILE"
    rm -f "$OUTPUT_FILE"
    exit 5
fi

# ── Done ──────────────────────────────────────────────────────
echo "────────────────────────────────────────────────"
echo " SUCCESS"
echo " File : $(pwd)/${OUTPUT_FILE}"
echo " Size : $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "────────────────────────────────────────────────"

# ── Optional: PDF download (comment out *TEXT block above first) ──
# HTTP_CODE=$(curl -s -k \
#     --user "${IBMI_USER}:${IBMI_PASS}" \
#     -H "Accept: application/pdf" \
#     -o "${SPLF_NAME}_${TIMESTAMP}.pdf" \
#     -w "%{http_code}" \
#     "${BASE_URL}/spooledfiles/${SPLF_ID}/content?format=%2APDF")
