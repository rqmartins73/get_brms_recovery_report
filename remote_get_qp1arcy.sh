#!/QOpenSys/pkgs/bin/bash
set -euo pipefail

LPAR_NAME=$(uname -n | tr '[:lower:]' '[:upper:]')
TARGET_DATE="${1:-}"
_SEQ=0

get_splf() {
	local SPLF_NAME="$1"
	_SEQ=$(( _SEQ + 1 ))
	local UNIQ="${_SEQ}$(date +%H%M%S)"
	local LSTPF="L${UNIQ}"
	local SPLPF="S${UNIQ}"
	local LATEST_ROW="/tmp/latest_${SPLF_NAME}_$$.txt"
	local SQL_FILE="/tmp/get_${SPLF_NAME}_$$.sql"
	local DATE_FILTER=""

	if [[ -n "$TARGET_DATE" ]]; then
		DATE_FILTER="AND DATE(CREATE_TIMESTAMP) = '${TARGET_DATE}'"
	fi

	/QOpenSys/usr/bin/system "CRTPF FILE(QGPL/${LSTPF}) RCDLEN(128) SIZE(*NOMAX)" >/dev/null

	cat > "$SQL_FILE" <<SQLEOF
INSERT INTO QGPL.${LSTPF}
SELECT TRIM(JOB_NAME) CONCAT '|' CONCAT TRIM(CHAR(FILE_NUMBER)) CONCAT '|' CONCAT TRIM(CHAR(CREATE_TIMESTAMP))
FROM QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC
WHERE SPOOLED_FILE_NAME = '${SPLF_NAME}'
${DATE_FILTER}
ORDER BY CREATE_TIMESTAMP DESC
FETCH FIRST 1 ROW ONLY;
SQLEOF

	/QOpenSys/usr/bin/system "RUNSQLSTM SRCSTMF('${SQL_FILE}') COMMIT(*NONE)" >/dev/null
	/QOpenSys/usr/bin/system "CPYTOSTMF FROMMBR('/QSYS.LIB/QGPL.LIB/${LSTPF}.FILE/${LSTPF}.MBR') TOSTMF('${LATEST_ROW}') STMFOPT(*REPLACE) STMFCODPAG(*PCASCII)" >/dev/null

	local ROW
	ROW=$(tr -d '\r' < "$LATEST_ROW" | awk 'NF { print; exit }')
	ROW=$(echo "$ROW" | xargs)

	rm -f "$SQL_FILE" "$LATEST_ROW"
	/QOpenSys/usr/bin/system "DLTF FILE(QGPL/${LSTPF})" >/dev/null 2>&1 || true

	if [[ -z "$ROW" ]]; then
		echo "ERROR: No spool file found for ${SPLF_NAME}" >&2
		exit 1
	fi

	local JOB_NAME="${ROW%%|*}"
	local REST="${ROW#*|}"
	local SPLNBR="${REST%%|*}"
	local SPLF_TS="${ROW##*|}"
	JOB_NAME=$(echo "$JOB_NAME" | xargs)
	SPLNBR=$(echo "$SPLNBR" | xargs)
	SPLF_TS=$(echo "$SPLF_TS" | xargs)

	if [[ -z "$JOB_NAME" || -z "$SPLNBR" || -z "$SPLF_TS" ]]; then
		echo "ERROR: Failed to parse spool information for ${SPLF_NAME}. ROW=${ROW}" >&2
		exit 1
	fi

	# Strip non-digits from timestamp (handles any IBM i separator style),
	# take YYYYMMDDHHMMSS (14 digits), insert _ between date and time.
	local SPLF_DT
	SPLF_DT=$(echo "$SPLF_TS" | tr -cd '0-9' | cut -c1-14 | sed 's/^\(.\{8\}\)/\1_/')

	local REMOTE_STMF="/tmp/${LPAR_NAME}_${SPLF_NAME}_${SPLF_DT}.txt"

	/QOpenSys/usr/bin/system "CRTPF FILE(QGPL/${SPLPF}) RCDLEN(378) SIZE(*NOMAX)" >/dev/null
	/QOpenSys/usr/bin/system "CPYSPLF FILE(${SPLF_NAME}) TOFILE(QGPL/${SPLPF}) JOB(${JOB_NAME}) SPLNBR(${SPLNBR}) CTLCHAR(*NONE) MBROPT(*REPLACE)" >/dev/null
	/QOpenSys/usr/bin/system "CPYTOSTMF FROMMBR('/QSYS.LIB/QGPL.LIB/${SPLPF}.FILE/${SPLPF}.MBR') TOSTMF('${REMOTE_STMF}') STMFOPT(*REPLACE) STMFCODPAG(*PCASCII)" >/dev/null
	/QOpenSys/usr/bin/system "DLTF FILE(QGPL/${SPLPF})" >/dev/null 2>&1 || true

	echo "$REMOTE_STMF"
}

get_splf "QP1ARCY"
get_splf "QP1A2RCY"
get_splf "QP1AHS"
