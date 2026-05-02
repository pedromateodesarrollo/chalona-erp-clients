#!/usr/bin/env bash
# Publica una nueva versión de chalona-ecf.prg en data.fox_cliente_script.
# Sin parámetros → entorno='test'    (ERPs con portal_dgii='testecf').
# --produccion   → entorno='produccion'.
#
# Sobreescribir conexión vía env vars: PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASS.

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
PRG="$SCRIPT_DIR/chalona-ecf.prg"

if [ ! -f "$PRG" ]; then
  echo "ERROR: no se encontró $PRG" >&2
  exit 1
fi

ENTORNO="test"
for arg in "$@"; do
  case "$arg" in
    --produccion) ENTORNO="produccion" ;;
    --test)       ENTORNO="test" ;;
    *) echo "Uso: $0 [--produccion|--test]" >&2; exit 1 ;;
  esac
done

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-postgres}"
PG_USER="${PG_USER:-postgres}"
PG_PASS="${PG_PASS:-postgres}"

echo "== Actualizando cliente Fox → entorno='$ENTORNO' (BD $PG_DB en $PG_HOST:$PG_PORT)"
echo "   Script: $PRG ($(wc -c < "$PRG") bytes)"

python3 - "$PRG" "$PG_HOST" "$PG_PORT" "$PG_DB" "$PG_USER" "$PG_PASS" "$ENTORNO" <<'PYEOF'
import sys, subprocess, os

prg_path, pg_host, pg_port, pg_db, pg_user, pg_pass, entorno = sys.argv[1:]

with open(prg_path, "r", encoding="utf-8", errors="replace") as f:
    script = f.read()

env = {**os.environ, "PGPASSWORD": pg_pass}
conn = ["-h", pg_host, "-p", pg_port, "-U", pg_user, "-d", pg_db, "-v", "ON_ERROR_STOP=1"]

def psql(sql):
    # Pasar SQL via stdin para evitar "Argument list too long" cuando el script Fox es grande.
    r = subprocess.run(["psql"] + conn + ["-t", "-A"],
                       input=sql, env=env, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR psql:", r.stderr, file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()

raw = psql(f"SELECT COALESCE(MAX(version), 0) FROM data.fox_cliente_script WHERE entorno = '{entorno}'")
next_ver = int(raw or "0") + 1

sql = f"""
BEGIN;
UPDATE data.fox_cliente_script SET activo = false WHERE entorno = '{entorno}' AND activo = true;
INSERT INTO data.fox_cliente_script (entorno, version, script, activo)
VALUES ('{entorno}', {next_ver}, $CHALONA_SCRIPT${script}$CHALONA_SCRIPT$, true);
COMMIT;
"""
psql(sql)
print(f"   entorno={entorno!r:<12} → v{next_ver} activo")
PYEOF

echo "== Listo."
