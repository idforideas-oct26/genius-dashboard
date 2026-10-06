#!/usr/bin/env bash
# Levanta Budget Manager, Landing CRM y el Dashboard juntos.
# Asume que los repos están clonados lado a lado:
#   genius-budget-manager/  genius-crm/  genius-dashboard/
# Ctrl+C detiene los tres.

set -euo pipefail

DASHBOARD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BM_DIR="$DASHBOARD_DIR/../genius-budget-manager"
CRM_DIR="$DASHBOARD_DIR/../genius-crm"

for dir in "$BM_DIR" "$CRM_DIR"; do
  if [ ! -d "$dir" ]; then
    echo "No se encontró $dir — cloná el repo al lado de genius-dashboard." >&2
    exit 1
  fi
done

# Al salir, detiene todo el grupo de procesos (incluye los hijos de mvn y nodemon)
trap 'trap - EXIT INT TERM; echo; echo "Deteniendo servicios..."; kill 0 2>/dev/null' EXIT INT TERM

# Antepone un prefijo a cada línea de log para distinguir los servicios
prefix() { while IFS= read -r line; do echo "[$1] $line"; done; }

port_in_use() { lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

wait_for() {
  local name=$1 url=$2
  for _ in $(seq 1 120); do
    if curl -s -o /dev/null "$url"; then
      echo "[$name] listo en $url"
      return 0
    fi
    sleep 1
  done
  echo "[$name] no respondió en $url después de 120s" >&2
  exit 1
}

if port_in_use 8080; then
  echo "[budget] el puerto 8080 ya está en uso, uso la instancia existente"
else
  echo "[budget] iniciando en :8080..."
  (cd "$BM_DIR" && mvn -q spring-boot:run 2>&1 | prefix budget) &
fi

if port_in_use 3000; then
  echo "[crm] el puerto 3000 ya está en uso, uso la instancia existente"
else
  echo "[crm] iniciando en :3000..."
  (cd "$CRM_DIR" && { [ -d node_modules ] || npm install; } && npm run dev 2>&1 | prefix crm) &
fi

wait_for budget http://localhost:8080/api/campaigns
wait_for crm http://localhost:3000/api/landings

echo "[dashboard] iniciando en :5173..."
cd "$DASHBOARD_DIR"
[ -d node_modules ] || npm install
npm run dev
