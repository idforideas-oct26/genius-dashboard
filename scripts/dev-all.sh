#!/usr/bin/env bash
# Levanta Budget Manager, Landing CRM, el admin PHP de Landings y el Dashboard juntos.
# Asume que los repos están clonados lado a lado:
#   genius-budget-manager/  genius-crm/  genius-landings/  genius-dashboard/
# El admin PHP es opcional: si no hay PHP instalado o falta el repo, se omite.
# Ctrl+C detiene todo lo que inició el script.

set -euo pipefail

DASHBOARD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BM_DIR="$DASHBOARD_DIR/../genius-budget-manager"
CRM_DIR="$DASHBOARD_DIR/../genius-crm"
LANDINGS_DIR="$DASHBOARD_DIR/../genius-landings"

for dir in "$BM_DIR" "$CRM_DIR"; do
  if [ ! -d "$dir" ]; then
    echo "No se encontró $dir — cloná el repo al lado de genius-dashboard." >&2
    exit 1
  fi
done

PORTS=(8080 3000 8000 5173)
NAMES=(budget crm landings dashboard)
STARTED=()   # puertos de los servicios que inició este script

# Antepone un prefijo a cada línea de log para distinguir los servicios
prefix() { while IFS= read -r line; do echo "[$1] $line"; done; }

port_in_use() { lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

# Todos los procesos hijos, nietos, etc. (incluye los hijos de mvn y nodemon)
descendants() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do
    descendants "$child"
    echo "$child"
  done
}

# Al salir: detiene lo que inició, espera a que liberen los puertos y muestra el estado
cleanup() {
  trap - EXIT INT TERM
  set +eu
  echo
  echo "Deteniendo servicios..."
  kill $(descendants $$) 2>/dev/null

  for _ in $(seq 1 20); do
    busy=0
    for port in "${STARTED[@]}"; do port_in_use "$port" && busy=1; done
    [ "$busy" = 0 ] && break
    sleep 0.5
  done

  for i in "${!PORTS[@]}"; do
    port=${PORTS[$i]} name=${NAMES[$i]}
    if ! port_in_use "$port"; then
      echo "[$name] :$port libre"
    elif [[ " ${STARTED[*]} " == *" $port "* ]]; then
      echo "[$name] :$port sigue en uso, corré npm run stop:all"
    else
      echo "[$name] :$port sigue corriendo (ya estaba antes de dev:all)"
    fi
  done
}
trap cleanup EXIT
trap 'exit 130' INT TERM

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
  STARTED+=(8080)
  (cd "$BM_DIR" && mvn -q spring-boot:run 2>&1 | prefix budget) &
fi

if port_in_use 3000; then
  echo "[crm] el puerto 3000 ya está en uso, uso la instancia existente"
else
  echo "[crm] iniciando en :3000..."
  STARTED+=(3000)
  (cd "$CRM_DIR" && { [ -d node_modules ] || npm install; } && npm run dev 2>&1 | prefix crm) &
fi

if port_in_use 8000; then
  echo "[landings] el puerto 8000 ya está en uso, uso la instancia existente"
elif ! command -v php >/dev/null 2>&1; then
  echo "[landings] PHP no está instalado, omito el admin (no lo necesita el Dashboard)"
elif [ ! -d "$LANDINGS_DIR" ]; then
  echo "[landings] no se encontró $LANDINGS_DIR, omito el admin"
else
  echo "[landings] iniciando admin PHP en :8000..."
  STARTED+=(8000)
  (cd "$LANDINGS_DIR" && php -S localhost:8000 2>&1 | prefix landings) &
fi

wait_for budget http://localhost:8080/api/campaigns
wait_for crm http://localhost:3000/api/landings

if port_in_use 8000; then echo "[landings] admin en http://localhost:8000/admin/"; fi

echo "[dashboard] iniciando en :5173..."
STARTED+=(5173)
cd "$DASHBOARD_DIR"
[ -d node_modules ] || npm install
npm run dev
