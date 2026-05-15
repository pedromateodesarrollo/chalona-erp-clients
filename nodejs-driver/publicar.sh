#!/usr/bin/env bash
# Publica el driver Node.js (JS source UTF-8) en data.nodejs_cliente_driver.
# Sin compilación — JS sube tal cual.
#
# Uso:
#   ./publicar.sh                           # entorno=test
#   ./publicar.sh --produccion              # entorno=produccion
#   ./publicar.sh --fuente=driver_src/X.js  # otra fuente
#   PG_HOST=db.example.com ./publicar.sh    # override conexión

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DRIVER_DIR="$(dirname "$SCRIPT_PATH")"

exec node "$DRIVER_DIR/bin/publicar.js" "$@"
