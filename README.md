# linux

Kolekcija Ansible rola za centralizovano upravljanje Linux serverima.

Repozitorijum sadrži **isključivo kod** — role, playbook-ove i inicijalni scaffold. Inventory, varijable i tajne ostaju izvan repozitorijuma, na Ansible kontrolnom čvoru.

---

## Sadržaj repozitorijuma

```text
linux/
├── roles/
│   ├── ansible_user/             # priprema sveze instaliranog servera
│   ├── banner/                   # /etc/motd, /etc/issue
│   ├── repos/                    # APT repozitorijumi
│   ├── packages/                 # instalacija i uklanjanje paketa
│   ├── updates/                  # azuriranje sistema
│   ├── firewall/                 # UFW pravila
│   ├── zabbix_agent/
│   ├── zabbix_db/
│   ├── zabbix_server/
│   ├── zabbix_web/
│   └── zabbix_proxy/
├── playbooks/
│   ├── playbook.yml              # svakodnevni rad, sve role
│   └── bootstrap.yml             # jednokratna priprema novog servera
├── bootstrap/
│   ├── init.sh                   # inicijalizacija radnog foldera
│   └── template/                 # šablon konfiguracije
├── .gitignore
└── README.md
```

Svaka rola ima sopstveni `README.md` sa tabelom varijabli, primerima i napomenama o zamkama. To je primarni izvor informacija — ovaj dokument daje pregled principa.

### Šta ovde namerno **ne** postoji

| Nije u repozitorijumu | Gde se nalazi |
|---|---|
| `inventory/` sa stvarnim hostovima | privatni folder na kontrolnom čvoru |
| Popunjen `group_vars/all.yml`, `host_vars/` | isto |
| Aktivan `ansible.cfg` | isto (kreira ga `init.sh`) |
| Vault lozinke, sertifikati, ključevi | isto, nikada u git |

Sve vrednosti u `roles/*/defaults/main.yml` su neutralni podrazumevani parametri.

---

## Princip rada

Svaka rola ima svoj prekidač `role_<ime>_enabled`, čija je podrazumevana vrednost u `defaults/main.yml` uvek `false`. Taskovi role su omotani u:

```yaml
when: role_<ime>_enabled | default(false) | bool
```

Podrazumevano stanje je dakle **„ne diraj ništa"**.

### Aktivacija ide preko grupe

Prekidač ne uključuješ ručno. Svakoj namenskoj grupi pripada `group_vars` fajl koji postavlja odgovarajući flag:

```yaml
# inventory/group_vars/apply_banner.yml
role_banner_enabled: true
```

Ovi fajlovi dolaze gotovi iz `bootstrap/template/` i posle inicijalizacije se ne diraju.

Praktična posledica: **u svakodnevnom radu uređuješ samo `hosts.ini`.**

```ini
[apply_banner]
srv-web-01        # dobija baner
srv-web-02        # dobija baner
                  # srv-db-01 nije naveden → ne dobija ništa
```

Članstvo u grupi je jedini izvor istine. Provera bez otvaranja ijednog fajla:

```bash
ansible-inventory --graph
ansible-inventory --host srv-web-01
```

### Prefiks grupe

| Prefiks | Značenje | Primer |
|---|---|---|
| `apply_` | menja stanje onoga što već postoji | `apply_firewall`, `apply_updates` |
| `deploy_` | donosi nešto novo na sistem | `deploy_packages`, `deploy_zabbix_agent` |

Pravilo je konvencija, ne tehnička razlika. Grupa `[bootstrap]` je jedini izuzetak bez prefiksa — ne pripada svakodnevnom toku.

### Izuzetak po hostu

Pošto `host_vars` ima viši prioritet od `group_vars`, host može ostati u grupi a da rola nad njim bude privremeno isključena:

```yaml
# inventory/host_vars/srv-db-01.yml
role_banner_enabled: false
```

Playbook će prijaviti `skipped`. Korisno kada host ne sme da se dira, a ne želiš da izgubiš trag da inače pripada toj grupi.

### Kaskadno uključivanje

```ini
[webservers]
srv-web-01
srv-web-02

[dbservers]
srv-db-01

[deploy_zabbix_agent:children]
webservers
dbservers
```

### Isključivanje pri pokretanju

```bash
./apply.sh --limit '!apply_updates'     # preskoči jednu grupu
./apply.sh --limit apply_banner         # pokreni samo jednu
```

---

## Preduslovi

**Na kontrolnom čvoru:**

- `ansible-core` **2.15 ili noviji** — rola `repos` koristi modul `deb822_repository`, dodat u toj verziji
- Tri kolekcije:

```bash
  ansible-galaxy collection install ansible.posix community.general community.mysql
```

  | Kolekcija | Koristi je |
  |---|---|
  | `ansible.posix` | `ansible_user` (SSH ključevi) |
  | `community.general` | `firewall` (UFW) |
  | `community.mysql` | `zabbix_db` |

- SSH ključni par; ako ne postoji:

```bash
  ssh-keygen -t ed25519 -C "ansible@control"
```

**Na ciljnim sistemima:**

- Ubuntu 22.04 ili noviji, odnosno Debian 12+ — `apt` 2.4+ zbog `.sources` formata
- SSH pristup i `sudo` privilegije

---

## Instalacija

Kod i konfiguracija stoje kao dva odvojena direktorijuma, jedan pored drugog:

```text
/opt/ansible/
├── linux/                    # git clone ovog repozitorijuma
└── production/               # tvoja konfiguracija, van git-a
    ├── ansible.cfg
    ├── apply.sh
    ├── .gitignore
    └── inventory/
        ├── hosts.ini
        ├── group_vars/       # po jedan fajl za svaku grupu
        └── host_vars/
```

### 1. Kloniraj repozitorijum

```bash
mkdir -p /opt/ansible && cd /opt/ansible
git clone https://github.com/<korisnik>/linux.git
```

### 2. Inicijalizuj radni folder

```bash
bash linux/bootstrap/init.sh /opt/ansible/production
```

> Skripta se namerno poziva kroz `bash`, jer fajlovi kreirani preko GitHub web interfejsa nemaju izvršni bit. `apply.sh` u radnom folderu tu nema problem — njemu izvršni bit postavlja sam `init.sh`.

Skripta kopira šablon iz `bootstrap/template/`, upiše putanje ka repozitorijumu i ispiše sledeće korake.

`init.sh` se pokreće **samo jednom**. Ako ciljni folder već sadrži `ansible.cfg`, skripta prekida rad i ne dira postojeće fajlove.

Skripta namerno **ne** pokreće `git init` u ciljnom folderu. Ako želiš da versioniraš svoju konfiguraciju, uradi to svesno i isključivo ka privatnom remote-u.

### 3. Upiši SSH ključ kontrolnog čvora

```bash
cd /opt/ansible/production
cat ~/.ssh/id_ed25519.pub
```

Dobijenu vrednost upiši u `inventory/group_vars/all.yml`:

```yaml
role_ansible_user_ssh_key: "ssh-ed25519 AAAAC3Nz... ansible@control"
```

> `all.yml` je jedini fajl u `group_vars/` koji se popunjava. Ostali su aktivacioni i ne diraju se.

### 4. Popuni inventory

```bash
mv inventory/hosts.ini.example inventory/hosts.ini
```

Šablon sadrži spisak svih dostupnih grupa, praznih. Upisuješ samo hostove koje želiš.

---

## Priprema novog servera

Sveže instaliran server još nema nalog pod kojim se Ansible povezuje. Zato prvo prolazi kroz `playbooks/bootstrap.yml`, koji se povezuje **postojećim** nalogom (`root`, `admin`, cloud-init korisnik) i tek kreira `ansible` nalog.

Ovaj playbook se **ne** pokreće kroz `apply.sh`.

**1.** Dodaj host u grupu `[bootstrap]`:

```ini
[bootstrap]
srv-web-01
```

**2.** Pokreni pripremu:

```bash
cd /opt/ansible/production

ansible-playbook ../linux/playbooks/bootstrap.yml \
  --limit srv-web-01 \
  --user root --ask-pass --ask-become-pass
```

| Situacija | Zastavice |
|---|---|
| root sa lozinkom | `--user root --ask-pass` |
| sudo korisnik sa lozinkom | `--user admin --ask-pass --ask-become-pass` |
| cloud-init sa ključem | `--user ubuntu` |

**3.** Proveri da ključ i sudo rade:

```bash
ssh ansible@srv-web-01 sudo whoami
```

Očekivani izlaz je `root`, bez pitanja za lozinku.

**4.** Ukloni host iz `[bootstrap]` i upiši ga u grupe rola koje treba da dobije.

Detalji su u [`roles/ansible_user/README.md`](roles/ansible_user/README.md).

---

## Pokretanje

Uvek iz `production/` foldera, kako bi Ansible pročitao lokalni `ansible.cfg`:

```bash
cd /opt/ansible/production

# Provera bez izmena — uvek prvo ovo
./apply.sh --check --diff --limit srv-web-01

# Sve role nad svim hostovima
./apply.sh

# Ograničenje na pojedinačan host
./apply.sh --limit srv-web-01

# Ograničenje na jednu grupu
./apply.sh --limit apply_banner

# Detaljan ispis
./apply.sh -vv
```

Role koje menjaju stanje sistema nepovratno su kao takve označene na vrhu svog `defaults/main.yml`.

---

## Ažuriranje rola

```bash
git -C /opt/ansible/linux pull
```

Konfiguracija se ne dira — kod i podaci su potpuno razdvojeni.

Nakon `pull`-a proveri da li je dodata nova grupa:

```bash
diff <(grep '^\[' linux/bootstrap/template/inventory/hosts.ini.example) \
     <(grep '^\[' production/inventory/hosts.ini)
```

Ako jeste, dodaj je u svoj `hosts.ini` i prekopiraj pripadajući `group_vars` fajl iz šablona. `init.sh` nikada ne prepisuje postojeće fajlove.

---

## Konfiguracija inventory-ja

### Prioritet varijabli

Od najnižeg ka najvišem:

```text
roles/<rola>/defaults/main.yml   →   group_vars/all.yml   →   group_vars/<grupa>.yml   →   host_vars/<host>.yml
```

Aktivacione flagove postavlja `group_vars/<grupa>.yml`. Parametre role menjaj u `group_vars/all.yml` (globalno) ili `host_vars/<host>.yml` (za pojedinačan host).

### Konvencija imenovanja

```text
role_<ime_role>_<parametar>
```

Varijable sa donjom crtom na početku (`_zabbix_server_service`) su izvedene vrednosti iz `vars/main.yml` — putanje i imena servisa koje rola sama računa. Njih **ne treba menjati**.

### Tajne

Lozinke i ključevi idu kroz `ansible-vault`:

```bash
ansible-vault encrypt_string 'lozinka' --name 'role_zabbix_db_password'
```

Rezultat upiši u `host_vars/<host>.yml`. Nikada u repozitorijum.

---

## Role

| Rola | Grupa | Status |
|---|---|---|
| [`ansible_user`](roles/ansible_user/) | `bootstrap` | implementirana |
| [`banner`](roles/banner/) | `apply_banner` | implementirana |
| [`repos`](roles/repos/) | `apply_repos` | implementirana |
| [`packages`](roles/packages/) | `deploy_packages` | implementirana |
| [`updates`](roles/updates/) | `apply_updates` | implementirana |
| [`firewall`](roles/firewall/) | `apply_firewall` | implementirana |
| [`zabbix_agent`](roles/zabbix_agent/) | `deploy_zabbix_agent` | implementirana |
| [`zabbix_db`](roles/zabbix_db/) | `deploy_zabbix_db` | implementirana |
| [`zabbix_server`](roles/zabbix_server/) | `deploy_zabbix_server` | implementirana |
| [`zabbix_web`](roles/zabbix_web/) | `deploy_zabbix_web` | implementirana |
| [`zabbix_proxy`](roles/zabbix_proxy/) | `deploy_zabbix_proxy` | implementirana |
| `timezone` | `apply_timezone` | planirana |
| `etc_hosts` | `apply_etc_hosts` | planirana |
| `users` | `apply_users` | planirana |
| `root_ca` | `deploy_root_ca` | planirana |
| `zabbix_provisioning` | `apply_zabbix_provisioning` | planirana |

> Grupe planiranih rola već postoje u šablonu inventory-ja. Dok rola nije implementirana, play nad njenom grupom pada — **ne upisuj hostove u te grupe** pre nego što rola bude dodata.

### Redosled u `playbook.yml`

Za neke role redosled nije proizvoljan:

```text
repos  →  packages  →  updates
```

Instalacija iz repozitorijuma koji još nije dodat bi pala.

```text
zabbix_db  →  zabbix_server  →  zabbix_web
```

Server uvozi šemu u bazu koju je `zabbix_db` kreirao; frontend čita tu istu bazu.

---

## Primer: Zabbix okruženje

Monitoring server sa bazom, frontendom i agentima na ostalim hostovima.

### `inventory/hosts.ini`

```ini
[all]
srv-mon-01  ansible_host=10.0.0.50
srv-web-01  ansible_host=10.0.0.11
srv-web-02  ansible_host=10.0.0.12

[webservers]
srv-web-01
srv-web-02

# Repozitorijum svima
[apply_repos]
srv-mon-01
srv-web-01
srv-web-02

# Zabbix server
[deploy_zabbix_db]
srv-mon-01

[deploy_zabbix_server]
srv-mon-01

[deploy_zabbix_web]
srv-mon-01

# Agenti svuda
[deploy_zabbix_agent]
srv-mon-01

[deploy_zabbix_agent:children]
webservers

# Zastitni zid
[apply_firewall]
srv-mon-01
srv-web-01
srv-web-02
```

### `inventory/group_vars/all.yml`

```yaml
role_ansible_user_ssh_key: "ssh-ed25519 AAAAC3Nz... ansible@control"

role_repos_list:
  - name: zabbix
    uris: "https://repo.zabbix.com/zabbix/7.0/ubuntu"
    suites: "{{ ansible_distribution_release }}"
    components: [main]
    signed_by: "https://repo.zabbix.com/zabbix-official-repo.key"

role_zabbix_agent_server: "10.0.0.50"

role_firewall_rules:
  - { rule: allow, port: 10050, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> agent" }
```

### `inventory/host_vars/srv-mon-01.yml`

```yaml
# Jedna lozinka, tri role
_zabbix_db_pass: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...

role_zabbix_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_web_db_password: "{{ _zabbix_db_pass }}"

role_zabbix_web_server_name: "Monitoring — Produkcija"

role_firewall_rules:
  - { rule: allow, port: 10050, proto: tcp, from: "10.0.0.50", comment: "Agent" }
  - { rule: allow, port: 10051, proto: tcp, from: "10.0.0.0/8", comment: "Agenti -> server" }
  - { rule: allow, port: 8080,  proto: tcp, from: "10.0.0.0/8", comment: "Frontend" }
```

### Primena

```bash
./apply.sh --check --diff --limit srv-mon-01
./apply.sh --limit srv-mon-01
./apply.sh --limit webservers
```

Frontend je zatim dostupan na `http://10.0.0.50:8080`. Podrazumevani nalog je `Admin` sa lozinkom `zabbix` — **promeni je odmah**.

---

## Dodavanje nove role

1. Kreiraj `roles/<ime>/` sa `defaults/`, `tasks/`, po potrebi `handlers/`, `templates/`, `vars/`.
2. U `defaults/main.yml` definiši `role_<ime>_enabled: false` uz komentar i primer korišćenja.
3. Sve ostale varijable prefiksiraj sa `role_<ime>_` i dokumentuj ih na istom mestu.
4. Izvedene vrednosti — putanje, imena servisa — idu u `vars/main.yml` sa prefiksom `_`.
5. U `tasks/main.yml` omotaj taskove u `block:` sa `when: role_<ime>_enabled | default(false) | bool`.
6. Prvi taskovi su `assert` provere: podržana distribucija, obavezne varijable, ispravni izbori.
7. Ako rola menja stanje sistema nepovratno, napiši upozorenje na vrhu `defaults/main.yml`.
8. Dodaj play u `playbooks/playbook.yml`, uz prefiks `apply_` ili `deploy_` prema tabeli iznad.
9. Dodaj tu grupu, praznu, u `bootstrap/template/inventory/hosts.ini.example`.
10. Dodaj `bootstrap/template/inventory/group_vars/<grupa>.yml` koji postavlja `role_<ime>_enabled: true`.

> Koraci 9 i 10 idu zajedno — grupa bez pripadajućeg `group_vars` fajla neće aktivirati rolu, a Ansible to **neće** prijaviti kao grešku.

Svaka rola dobija i sopstveni `README.md` sa preduslovima, tabelom varijabli, primerima, napomenama o zamkama, strukturom, idempotentnošću i komandama za proveru.

Konfiguracioni fajlovi se upisuju iz šablona **u celosti**, sa zaglavljem `UPRAVLJA ANSIBLE ROLA: <ime>` i `backup: true`. Taskovi koji dodiruju lozinke imaju `no_log: true`.

**Nijedna vrednost specifična za neko okruženje** — imena domena, IP adrese, nazivi organizacija, kredencijali — ne sme se naći u `defaults/main.yml`. Koristi neutralne placeholder vrednosti (`example.com`, `10.0.0.0/8`, `CHANGEME`).

---

## Licenca

MIT
