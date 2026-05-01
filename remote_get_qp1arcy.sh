#!/QOpenSys/pkgs/bin/bash
set -euo pipefail

SPLF_NAME="QP1ARCY"

UNIQ="$(date +%H%M%S)"
LSTPF="LS${UNIQ}"
SPLPF="SP${UNIQ}"

REMOTE_STMF="/tmp/${SPLF_NAME}_$(date +%Y%m%d_%H%M%S).txt"
LATEST_ROW="/tmp/latest_${SPLF_NAME}_$$.txt"
SQL_FILE="/tmp/get_${SPLF_NAME}_$$.sql"

cleanup() {
	/QOpenSys/usr/bin/system "DLTF FILE(QGPL/${LSTPF})" >/dev/null 2>&1 || true
	/QOpenSys/usr/bin/system "DLTF FILE(QGPL/${SPLPF})" >/dev/null 2>&1 || true
	rm -f "$SQL_FILE" "$LATEST_ROW"
}
trap cleanup EXIT

/QOpenSys/usr/bin/system "CRTPF FILE(QGPL/${LSTPF}) RCDLEN(128) SIZE(*NOMAX)" >/dev/null

cat > "$SQL_FILE" <<EOF
INSERT INTO QGPL.${LSTPF}
SELECT TRIM(JOB_NAME) CONCAT '|' CONCAT TRIM(CHAR(FILE_NUMBER))
FROM QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC
WHERE SPOOLED_FILE_NAME = '${SPLF_NAME}'
ORDER BY CREATE_TIMESTAMP DESC
FETCH FIRST 1 ROW ONLY;
EOF

/QOpenSys/usr/bin/system "RUNSQLSTM SRCSTMF('${SQL_FILE}') COMMIT(*NONE)" >/dev/null

/QOpenSys/usr/bin/system "CPYTOSTMF FROMMBR('/QSYS.LIB/QGPL.LIB/${LSTPF}.FILE/${LSTPF}.MBR') TOSTMF('${LATEST_ROW}') STMFOPT(*REPLACE) STMFCODPAG(*PCASCII)" >/dev/null

ROW=$(tr -d '\r' < "$LATEST_ROW" | awk 'NF { print; exit }')
ROW=$(echo "$ROW" | xargs)

if [[ -z "$ROW" ]]; then
	echo "ERROR: No spool file found for ${SPLF_NAME}" >&2
	exit 1
fi

JOB_NAME="${ROW%%|*}"
SPLNBR="${ROW##*|}"

JOB_NAME=$(echo "$JOB_NAME" | xargs)
SPLNBR=$(echo "$SPLNBR" | xargs)

if [[ -z "$JOB_NAME" || -z "$SPLNBR" || "$JOB_NAME" == "$SPLNBR" ]]; then
	echo "ERROR: Failed to parse spool information. ROW=${ROW}" >&2
	exit 1
fi

/QOpenSys/usr/bin/system "CRTPF FILE(QGPL/${SPLPF}) RCDLEN(378) SIZE(*NOMAX)" >/dev/null

/QOpenSys/usr/bin/system "CPYSPLF FILE(${SPLF_NAME}) TOFILE(QGPL/${SPLPF}) JOB(${JOB_NAME}) SPLNBR(${SPLNBR}) CTLCHAR(*NONE) MBROPT(*REPLACE)" >/dev/null

/QOpenSys/usr/bin/system "CPYTOSTMF FROMMBR('/QSYS.LIB/QGPL.LIB/${SPLPF}.FILE/${SPLPF}.MBR') TOSTMF('${REMOTE_STMF}') STMFOPT(*REPLACE) STMFCODPAG(*PCASCII)" >/dev/null

echo "$REMOTE_STMF"
