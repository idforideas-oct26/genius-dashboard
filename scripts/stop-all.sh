#!/usr/bin/env bash
# Detiene todo lo que esté escuchando en los puertos del ecosistema,
# lo haya iniciado dev:all o no. Útil si quedó algún proceso huérfano.
#   8080 Budget Manager · 3000 Landing CRM · 5173 Dashboard · 8000 Admin PHP

set -uo pipefail

PORTS=(8080 3000 5173 8000)
NAMES=(budget crm dashboard landings)

pids_on() { lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null; }

stopped=0
for i in "${!PORTS[@]}"; do
  port=${PORTS[$i]} name=${NAMES[$i]}
  pids=$(pids_on "$port")
  if [ -z "$pids" ]; then
    echo "[$name] :$port libre"
    continue
  fi

  for pid in $pids; do
    echo "[$name] :$port deteniendo $(ps -o comm= -p "$pid" | xargs basename) (PID $pid)"
    kill "$pid" 2>/dev/null
  done

  # Espera hasta 5s a que cierre; si no, lo fuerza
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -z "$(pids_on "$port")" ] && break
    sleep 0.5
  done
  if [ -n "$(pids_on "$port")" ]; then
    echo "[$name] :$port no respondió, forzando cierre"
    kill -9 $(pids_on "$port") 2>/dev/null
  fi
  stopped=$((stopped + 1))
done

echo "Listo: $stopped servicio(s) detenido(s)."
