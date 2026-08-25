#!/usr/bin/env bash
#
# apply.sh — pokretanje glavnog playbook-a
#
# Putanju do playbook-a upisuje bootstrap/init.sh prilikom
# inicijalizacije. Ako premestis repozitorijum, izmeni PLAYBOOK ispod.
#
# Svi argumenti se prosledjuju direktno ansible-playbook komandi:
#
#   ./apply.sh                                  # sve role, svi hostovi
#   ./apply.sh --check --diff                   # provera bez izmena
#   ./apply.sh --limit srv-web-01               # jedan host
#   ./apply.sh --limit apply_banner             # jedna grupa
#   ./apply.sh --limit '!apply_system_update'   # sve osim jedne grupe
#   ./apply.sh -vv                              # detaljan ispis

set -euo pipefail

PLAYBOOK="@@PLAYBOOK_PATH@@"

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -f "$PLAYBOOK" ]]; then
  echo "GRESKA: playbook nije pronadjen: $PLAYBOOK" >&2
  echo "        Proveri da li je repozitorijum premesten i izmeni" >&2
  echo "        promenljivu PLAYBOOK u ovoj skripti." >&2
  exit 1
fi

if [[ ! -f inventory/hosts.ini ]]; then
  echo "GRESKA: inventory/hosts.ini ne postoji." >&2
  echo "        Pokreni: mv inventory/hosts.ini.example inventory/hosts.ini" >&2
  exit 1
fi

exec ansible-playbook "$PLAYBOOK" "$@"
