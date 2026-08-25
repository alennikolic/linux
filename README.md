# linux

Kolekcija Ansible rola za centralizovano upravljanje Linux serverima.

Repozitorijum sadrži **isključivo kod** — role i glavni playbook. Inventory, varijable i tajne ostaju izvan repozitorijuma, na Ansible kontrolnom čvoru.

---

## Sadržaj repozitorijuma

```text
linux/
├── roles/
│   ├── banner/
│   │   ├── defaults/main.yml     # dokumentovane default varijable
│   │   ├── tasks/main.yml
│   │   └── handlers/main.yml
│   ├── timezone/
│   ├── firewall/
│   └── ...
├── playbooks/
│   └── playbook.yml              # glavni playbook, poziva sve role
├── .gitignore
└── README.md
```

### Šta ovde namerno **ne** postoji

| Nije u repozitorijumu | Gde se nalazi |
|---|---|
| `inventory/` | privatni folder na kontrolnom čvoru |
| `group_vars/`, `host_vars/` | isto |
| `ansible.cfg` | isto (definiše putanje ka ovom repo-u) |
| `apply.sh` | isto |
| Vault lozinke, sertifikati, ključevi | isto, nikada u git |

Sve vrednosti u `roles/*/defaults/main.yml` su neutralni podrazumevani parametri. Stvarna konfiguracija se definiše kroz `group_vars` i `host_vars` na strani korisnika.

---

## Princip rada

Aktivacija role je **dvostepena**. Oba uslova moraju biti ispunjena da bi se rola izvršila nad hostom:

1. **Članstvo u grupi** — svaki play u `playbook.yml` cilja tačno određenu inventory grupu. Ako host nije u grupi, play ga preskače.
2. **Enable varijabla** — taskovi unutar role su omotani u `when: role_<ime>_enabled | bool`. Podrazumevana vrednost je uvek `false`.

> **Napomena:** ako je host u grupi ali `role_<ime>_enabled` nije postavljen na `true`, playbook će prijaviti `skipped`, a ne `changed`. Ovo je najčešći uzrok zabune pri prvom podešavanju.

Ovakav pristup znači da je **podrazumevano stanje uvek „ne diraj ništa"**. Rola mora biti eksplicitno uključena na oba nivoa.

---

## Pregled rola

### Osnovna konfiguracija sistema

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `timezone` | `apply_timezone` | `role_timezone_enabled` | Vremenska zona i NTP |
| `banner` | `apply_banner` | `role_banner_enabled` | `/etc/motd` baner |
| `firewall` | `apply_firewall` | `role_firewall_enabled` | Pravila zaštitnog zida |
| `hosts` | `apply_hosts` | `role_hosts_enabled` | `/etc/hosts` unosi |
| `users` | `apply_users` | `role_users_enabled` | Nalozi, grupe, SSH ključevi |

### Upravljanje paketima

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `package_manager` | `package_manager` | `role_package_manager_enabled` | Konfiguracija menadžera paketa |
| `package_update` | `package_update` | `role_package_update_enabled` | Ažuriranje paketa (`serial: 1`) |
| `package_sync` | `package_sync` | `role_package_sync_enabled` | Sinhronizacija stanja paketa |

> `package_update` se izvršava sa `serial: 1` — host po host, da ažuriranje ne obori celu grupu istovremeno.

### Repozitorijumi

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `custom_repo` | `deploy_custom_repo` | `role_custom_repo_enabled` | Interni repozitorijum |
| `repository` | `apply_repository` | `role_repository_enabled` | Sistemski repozitorijumi |

### Održavanje sistema

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `system_update` | `apply_system_update` | `role_system_update_enabled` | Nadogradnja sistema |
| `tools` | `deploy_tools` | `role_tools_enabled` | Osnovni alati |

### Sertifikati

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `root_ca` | `deploy_root_ca` | `role_root_ca_enabled` | Instalacija Root CA sertifikata |

### Zabbix

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `zabbix_agent` | `deploy_zabbix_agent` | `role_zabbix_agent_enabled` | Zabbix agent |
| `zabbix_db` | `deploy_zabbix_db` | `role_zabbix_db_enabled` | Baza podataka |
| `zabbix_server` | `deploy_zabbix_server` | `role_zabbix_server_enabled` | Zabbix server |
| `zabbix_web` | `deploy_zabbix_web` | `role_zabbix_web_enabled` | Web frontend |
| `zabbix_proxy` | `deploy_zabbix_proxy` | `role_zabbix_proxy_enabled` | Zabbix proxy |
| `zabbix_provisioning` | `zabbix_provisioning` | `role_zabbix_provisioning_enabled` | Hostovi, šabloni, akcije |

### Virtuelizacija i platforme

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `vcenter_deploy` | `deploy_vms` | `role_vcenter_deploy_enabled` | Kreiranje VM iz šablona |
| `hashicorp_deploy` | `hashicorp_deploy` | `role_hashicorp_deploy_enabled` | HashiCorp komponente |

> `vcenter_deploy` je jedini play **bez `become`** — komunicira sa vCenter API-jem, ne sa ciljnim sistemom.

### Priprema šablona

| Rola | Inventory grupa | Enable varijabla | Namena |
|---|---|---|---|
| `system_prep` | `system_prep` | `role_system_prep_enabled` | Čišćenje sistema pre pravljenja šablona |

---

## Postavljanje

### Preduslovi

- Ansible 2.14 ili noviji na kontrolnom čvoru
- SSH pristup do ciljnih sistema
- `sudo` privilegije (osim za `vcenter_deploy`)

### Preporučena struktura na kontrolnom čvoru

Kod i konfiguracija stoje jedan pored drugog, kao dva odvojena direktorijuma:

```text
/opt/ansible/
├── linux/                    # git clone ovog repozitorijuma
│   ├── roles/
│   └── playbooks/
│
└── production/               # privatno, van git-a
    ├── ansible.cfg
    ├── apply.sh
    ├── inventory/
    │   ├── hosts.ini
    │   ├── group_vars/
    │   └── host_vars/
    └── vault-pass.txt
```

### Kloniranje

```bash
mkdir -p /opt/ansible && cd /opt/ansible
git clone https://github.com/<korisnik>/linux.git
mkdir -p production/inventory/{group_vars,host_vars}
```

### `production/ansible.cfg`

```ini
[defaults]
inventory          = ./inventory
roles_path         = ../linux/roles
host_key_checking  = True
interpreter_python = auto_silent
retry_files_enabled = False

[privilege_escalation]
become        = True
become_method = sudo
```

### `production/apply.sh`

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ansible-playbook ../linux/playbooks/playbook.yml "$@"
```

```bash
chmod +x production/apply.sh
```

Pokretanje uvek iz `production/` direktorijuma, kako bi Ansible pročitao lokalni `ansible.cfg`.

### Ažuriranje rola

```bash
git -C /opt/ansible/linux pull
```

Konfiguracija se ne dira — kod i podaci su potpuno razdvojeni.

---

## Konfiguracija inventory-ja

### `inventory/hosts.ini`

Host se u grupu upisuje samo ako želiš da odgovarajuća rola bude primenjena nad njim:

```ini
[apply_timezone]
srv-web-01
srv-web-02
srv-db-01

[apply_banner]
srv-web-01
srv-web-02
srv-db-01

[deploy_zabbix_agent]
srv-web-01
srv-web-02

[deploy_zabbix_server]
srv-mon-01
```

Isti host se pojavljuje u onoliko grupa koliko rola treba da primi.

### Prioritet varijabli

Od najnižeg ka najvišem:

```text
roles/<rola>/defaults/main.yml   →   group_vars/all.yml   →   group_vars/<grupa>.yml   →   host_vars/<host>.yml
```

### Konvencija imenovanja

Sve varijable su prefiksirane imenom role, čime se izbegavaju kolizije između rola:

```text
role_<ime_role>_<parametar>
```

Svaka rola ima potpunu dokumentaciju varijabli sa primerima u sopstvenom `defaults/main.yml`. To je primarni izvor informacija — ovaj README daje samo pregled.

---

## Primer: uključivanje `banner` role

**1.** Dodaj hostove u grupu `apply_banner` u `hosts.ini`.

**2.** Uključi rolu globalno u `group_vars/all.yml`:

```yaml
role_banner_enabled: true
```

**3.** Po potrebi definiši prilagođen tekst u `host_vars/srv-web-01.yml`:

```yaml
role_banner_text: |
  *****************************************************************
  * UPOZORENJE: Pristup samo za ovlašćena lica                    *
  * Host: {{ inventory_hostname }}
  * Sve aktivnosti se beleže.                                     *
  *****************************************************************
```

Ako `role_banner_text` nije definisan, koristi se `role_banner_default_text` iz `defaults/main.yml`.

---

## Pokretanje

```bash
cd /opt/ansible/production

# Sve role nad svim hostovima
./apply.sh

# Provera bez izmena
./apply.sh --check --diff

# Ograničenje na pojedinačan host
./apply.sh --limit srv-web-01

# Ograničenje na jedan play
./apply.sh --limit apply_banner

# Detaljan ispis
./apply.sh -vv
```

Pre primene nad produkcijom preporučuje se `--check --diff` uz `--limit` na jedan host.

---

## Dodavanje nove role

Da bi rola bila u skladu sa ostatkom projekta:

1. Kreiraj `roles/<ime>/` sa `defaults/`, `tasks/` i po potrebi `handlers/` i `templates/`.
2. U `defaults/main.yml` definiši `role_<ime>_enabled: false` uz komentar i primer korišćenja.
3. Sve ostale varijable prefiksiraj sa `role_<ime>_`.
4. U `tasks/main.yml` omotaj taskove u `block:` sa `when: role_<ime>_enabled | default(false) | bool`.
5. U `playbooks/playbook.yml` dodaj play sa odgovarajućom grupom.
6. Dodaj red u tabelu u ovom README-u.

Nijedna vrednost specifična za neko okruženje — imena domena, IP adrese, nazivi organizacija, kredencijali — ne sme se naći u `defaults/main.yml`. Koristi neutralne placeholder vrednosti (`example.com`, `CHANGEME`).

---

## Licenca

MIT
