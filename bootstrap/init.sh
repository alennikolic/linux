#!/usr/bin/env bash
#
# bootstrap/init.sh
#
# init.sh — inicijalizacija radnog (production) foldera
#
# Kopira sablon iz bootstrap/template/ u ciljni folder i upisuje
# apsolutne putanje ka ovom repozitorijumu.
#
# Pokrece se SAMO JEDNOM. Ako ciljni folder vec sadrzi ansible.cfg,
# skripta prekida rad i ne dira nijedan postojeci fajl.
#
# Upotreba:
#   bash bootstrap/init.sh [ciljni_folder]
#
# Podrazumevani ciljni folder je ../production, relativno u odnosu
# na koren repozitorijuma.

set -euo pipefail

# Sve sto skripta napravi je citljivo samo vlasniku. Postavlja se pre
# prvog mkdir-a: u suprotnom bi izmedju kopiranja i zavrsnog chmod-a
# postojao prozor u kojem folder mogu citati svi nalozi na sistemu.
umask 077

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

# --- Razresavanje ciljne putanje -------------------------------------
# Putanja se razresava preko roditeljskog foldera, bez kreiranja
# ciljnog. Raniji redosled (mkdir pa provera) ostavljao je prazan
# folder u git stablu kada bi provera zatim prekinula rad.

TARGET_PARENT_RAW="$(dirname "$TARGET_RAW")"

if [[ ! -d "$TARGET_PARENT_RAW" ]]; then
  echo "GRESKA: roditeljski folder ne postoji: $TARGET_PARENT_RAW" >&2
  echo "        Napravi ga rucno, pa pokreni skriptu ponovo." >&2
  exit 1
fi

TARGET_PARENT="$(cd "$TARGET_PARENT_RAW" && pwd)"
TARGET="$TARGET_PARENT/$(basename "$TARGET_RAW")"

# Poredjenje mora imati granicu na kosoj crti. Golo poredjenje prefiksa
# ("$TARGET" == "$REPO_ROOT"*) tretira /opt/ansible/linux-production
# kao da je unutar /opt/ansible/linux.
if [[ "$TARGET" == "$REPO_ROOT" || "$TARGET" == "$REPO_ROOT"/* ]]; then
  echo "GRESKA: ciljni folder je unutar repozitorijuma: $TARGET" >&2
  echo "        Konfiguracija mora biti IZVAN git repozitorijuma." >&2
  exit 1
fi

# --- Kopiranje -------------------------------------------------------

mkdir -p "$TARGET"

# tacka na kraju izvora kopira i skrivene fajlove (.gitignore)
cp -r "$TEMPLATE_DIR/." "$TARGET/"

# --- Folderi za fajlove van sablona ----------------------------------
# Ovi folderi se ne isporucuju kroz template/ jer im dozvole zavise od
# sadrzaja, a git ih ne cuva. Prave se ovde, sa izricitim chmod-om.
#
#   files/csr/   ulazni CSR-ovi za rolu root_ca. Zahtev je javan
#                podatak — potpisuje ga privatni kljuc koji ostaje na
#                hostu koji ga je napravio.
#
#   files/pki/   ono sto rola root_ca vraca sa CA hosta. Kod unosa iz
#                role_root_ca_issued_certs tu zavrsavaju i PRIVATNI
#                KLJUCEVI, pa folder mora biti 0700. Ovo je najlakse
#                prevideti mesto u celoj postavci.

mkdir -p "$TARGET/files/csr" "$TARGET/files/pki"
chmod 0755 "$TARGET/files" "$TARGET/files/csr"
chmod 0700 "$TARGET/files/pki"

# --- Upis putanja ----------------------------------------------------

ROLES_PATH="$REPO_ROOT/roles"
PLAYBOOK_PATH="$REPO_ROOT/playbooks/playbook.yml"

sed -i.bak "s|@@ROLES_PATH@@|$ROLES_PATH|g" "$TARGET/ansible.cfg"
sed -i.bak "s|@@PLAYBOOK_PATH@@|$PLAYBOOK_PATH|g" "$TARGET/apply.sh"
rm -f "$TARGET/ansible.cfg.bak" "$TARGET/apply.sh.bak"

# Fajlovi napravljeni kroz GitHub web interfejs nemaju izvrsni bit.
chmod +x "$TARGET/apply.sh"
chmod 700 "$TARGET"

# --- Ispis -----------------------------------------------------------

cat <<EOF
Inicijalizovano: $TARGET

  roles_path : $ROLES_PATH
  playbook   : $PLAYBOOK_PATH

Napravljeni folderi:

  files/csr/   0755   ulazni CSR-ovi (polje src u role_root_ca_signed_csrs)
  files/pki/   0700   sertifikati i kljucevi preuzeti sa CA hosta

Sledeci koraci:

  cd $TARGET
  mv inventory/hosts.ini.example inventory/hosts.ini
  \$EDITOR inventory/hosts.ini
  ./apply.sh --check --diff --limit <host>

Napomene:

  * Fajlove u inventory/group_vars/ ne treba dirati — oni postavljaju
    role_<ime>_enabled prekidace za pripadajuce grupe.

  * files/pki/ je 0700 sa razlogom: rola root_ca tu spusta i privatne
    kljuceve sertifikata koje sama izdaje. Ne otvaraj dozvole.

  * Ovaj folder NIJE git repozitorijum i ne treba da bude u istom
    repozitorijumu kao role. Ako ga verzionirate, iskljucivo ka
    privatnom remote-u.
EOF
