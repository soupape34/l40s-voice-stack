#!/usr/bin/env bash
# Arrêt propre : persist modèles + stop EC2
set -euo pipefail
cd "$(dirname "$0")"
exec ./stop.sh -y "$@"
