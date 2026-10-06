#!/usr/bin/env bash
# Muestra qué servicios del ecosistema están corriendo. No detiene nada.
#   8080 Budget Manager · 3000 Landing CRM · 8000 Admin PHP · 5173 Dashboard

set -uo pipefail

PORTS=(8080 3000 8000 5173)
NAMES=(budget crm landings dashboard)
URLS=(
  http://localhost:8080/api/campaigns
  http://localhost:3000/api/landings
  http://localhost:8000/admin/
  http://localhost:5173/
)

active=0
for i in "${!PORTS[@]}"; do
  port=${PORTS[$i]} name=${NAMES[$i]} url=${URLS[$i]}
  pid=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -1)
  if [ -z "$pid" ]; then
    echo "[$name] :$port libre"
    continue
  fi

  active=$((active + 1))
  proc=$(ps -o comm= -p "$pid" | xargs basename)
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$url")
  echo "[$name] :$port activo · $proc (PID $pid) · $url → $code"
done

echo "$active de ${#PORTS[@]} servicios activos."
