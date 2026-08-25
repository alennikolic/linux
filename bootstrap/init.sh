#!/usr/bin/env bash
#
# init.sh — inicijalizacija radnog (production) foldera
#
# Kopira šablon iz bootstrap/template/ u ciljni folder i upisuje
# apsolutne putanje ka ovom repozitorijumu.
#
# Pokreće se SAMO JEDNOM. Ako ciljni folder već sadrži ansible.cfg,
# skripta prekida rad i ne dira nijedan postojeći fajl.
#
# Upotreba:
#   ./bootstrap/init.sh [ciljni_folder]
#
# Podrazumevani ciljni folder je ../production, relativno u odnosu
# na koren repozitorijuma.

set -euo pipefail

# --- Putanje ---------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

TARGET_RAW="${1:-$REPO_ROOT/../production}"

# --- Provere ---------------------------------------------------------

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "GRESKA: sablon nije pronadjen: $TEMPLATE_DIR" >&2
  exit 1
fi

if [[ ! -d "$REPO_ROOT/roles" ]]; then
  echo "GRESKA: $REPO_ROOT ne izgleda kao koren repozitorijuma (nema roles/)." >&2
  exit 1
fi

if [[ -e "$TARGET_RAW/ansible.cfg" ]]; then
  echo "GRESKA: $TARGET_RAW je vec inicijalizovan (postoji ansible.cfg)." >&2
  echo "        Skripta se pokrece samo jednom. Prekidam bez izmena." >&2
  exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "UPOZORENJE: ansible-playbook nije pronadjen u PATH-u." >&2
  echo "            Nastavljam, ali instaliraj Ansible pre pokretanja." >&2
fi

# --- Kopiranje -------------------------------------------------------

mkdir -p "$TARGET_RAW"
TARGET="$(cd "$TARGET_RAW" && pwd)"

if [[ "$TARGET" == "$REPO_ROOT"* ]]; then
  echo "GRESKA: ciljni folder je unutar repozitorijuma: $TARGET" >&2
  echo "        Konfiguracija mora biti IZVAN git repozitorijuma." >&2
  exit 1
fi

# tacka na kraju izvora kopira i skrivene fajlove (.gitignore)
cp -r "$TEMPLATE_DIR/." "$TARGET/"

# --- Upis putanja ----------------------------------------------------

ROLES_PATH="$REPO_ROOT/roles"
PLAYBOOK_PATH="$REPO_ROOT/playbooks/playbook.yml"

sed -i.bak "s|@@ROLES_PATH@@|$ROLES_PATH|g" "$TARGET/ansible.cfg"
sed -i.bak "s|@@PLAYBOOK_PATH@@|$PLAYBOOK_PATH|g" "$TARGET/apply.sh"
rm -f "$TARGET/ansible.cfg.bak" "$TARGET/apply.sh.bak"

chmod +x "$TARGET/apply.sh"
chmod 700 "$TARGET"

# --- Ispis -----------------------------------------------------------

cat <<EOF

Inicijalizovano: $TARGET

  roles_path : $ROLES_PATH
  playbook   : $PLAYBOOK_PATH

Sledeci koraci:

  cd $TARGET
  mv inventory/hosts.ini.example inventory/hosts.ini
  \$EDITOR inventory/hosts.ini
  ./apply.sh --check --diff --limit <host>

Napomene:

  * Fajlove u inventory/group_vars/ ne treba dirati — oni postavljaju
    role_<ime>_enabled prekidace za pripadajuce grupe.
  * Ovaj folder NIJE git repozitorijum i ne treba da bude u istom
    repozitorijumu kao role. Ako ga verzionirate, iskljucivo ka
    privatnom remote-u.

EOF
