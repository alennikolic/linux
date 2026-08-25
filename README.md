# linux

Kolekcija Ansible rola za centralizovano upravljanje Linux serverima.

Repozitorijum sadrži **isključivo kod** — role, glavni playbook i inicijalni scaffold. Inventory, varijable i tajne ostaju izvan repozitorijuma, na Ansible kontrolnom čvoru.

---

## Sadržaj repozitorijuma

```text
linux/
├── roles/
│   └── <ime_role>/
│       ├── defaults/main.yml     # dokumentovane default varijable
│       ├── tasks/main.yml
│       └── handlers/main.yml
├── playbooks/
│   └── playbook.yml              # glavni playbook, poziva sve role
├── bootstrap/
│   ├── init.sh                   # inicijalizacija radnog foldera
│   └── template/                 # šablon konfiguracije
├── .gitignore
└── README.md
```

### Šta ovde namerno **ne** postoji

| Nije u repozitorijumu | Gde se nalazi |
|---|---|
| `inventory/` sa stvarnim hostovima | privatni folder na kontrolnom čvoru |
| Popunjeni `group_vars/`, `host_vars/` | isto |
| Aktivan `ansible.cfg` | isto (kreira ga `init.sh`) |
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

## Preduslovi

- Ansible 2.14 ili noviji na kontrolnom čvoru
- SSH pristup do ciljnih sistema
- `sudo` privilegije na ciljnim sistemima

---

## Instalacija

Kod i konfiguracija stoje kao dva odvojena direktorijuma, jedan pored drugog:

```text
/opt/ansible/
├── linux/                    # git clone ovog repozitorijuma
│   ├── roles/
│   ├── playbooks/
│   └── bootstrap/
│
└── production/               # tvoja konfiguracija, van git-a
    ├── ansible.cfg
    ├── apply.sh
    ├── .gitignore
    └── inventory/
        ├── hosts.ini
        ├── group_vars/
        └── host_vars/
```

### 1. Kloniraj repozitorijum

```bash
mkdir -p /opt/ansible && cd /opt/ansible
git clone https://github.com/<korisnik>/linux.git
```

### 2. Inicijalizuj radni folder

```bash
./linux/bootstrap/init.sh /opt/ansible/production
```

Skripta kopira šablon iz `bootstrap/template/`, postavi izvršne dozvole i ispiše sledeće korake.

`init.sh` se pokreće **samo jednom**. Ako ciljni folder već sadrži `ansible.cfg`, skripta prekida rad i ne dira postojeće fajlove — nema rizika od gubitka konfiguracije pri ponovnom pokretanju.

Skripta namerno **ne** pokreće `git init` u ciljnom folderu. Ako želiš da versioniraš svoju konfiguraciju, uradi to svesno i isključivo ka privatnom remote-u.

### 3. Popuni konfiguraciju

```bash
cd /opt/ansible/production
mv inventory/hosts.ini.example inventory/hosts.ini
mv inventory/group_vars/all.yml.example inventory/group_vars/all.yml
```

Zatim uredi oba fajla prema svom okruženju.

### 4. Provera

```bash
./apply.sh --check --diff --limit <host>
```

---

## Ažuriranje rola

```bash
git -C /opt/ansible/linux pull
```

Konfiguracija se ne dira — kod i podaci su potpuno razdvojeni. Ako novo izdanje donese promene u `bootstrap/template/`, uporedi ih ručno sa svojim folderom; `init.sh` nikada ne prepisuje postojeće fajlove.

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

[deploy_tools]
srv-web-01
srv-web-02
```

Isti host se pojavljuje u onoliko grupa koliko rola treba da primi.

### Prioritet varijabli

Od najnižeg ka najvišem:

```text
roles/<rola>/defaults/main.yml   →   group_vars/all.yml   →   group_vars/<grupa>.yml   →   host_vars/<host>.yml
```

### Konvencija imenovanja

Sve varijable su prefiksirane imenom role, čime se izbegavaju kolizije:

```text
role_<ime_role>_<parametar>
```

Svaka rola ima potpunu dokumentaciju varijabli sa primerima u sopstvenom `defaults/main.yml`. To je primarni izvor informacija — ovaj README daje samo pregled principa.

---

## Primer: uključivanje role

Na primeru role `banner`, koja upravlja sadržajem `/etc/motd`:

**1.** Dodaj hostove u grupu `apply_banner` u `hosts.ini`.

**2.** Uključi rolu u `group_vars/all.yml`:

```yaml
role_banner_enabled: true
```

**3.** Po potrebi definiši prilagođenu vrednost u `host_vars/srv-web-01.yml`:

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

Uvek iz `production/` foldera, kako bi Ansible pročitao lokalni `ansible.cfg`:

```bash
cd /opt/ansible/production

# Sve role nad svim hostovima
./apply.sh

# Provera bez izmena
./apply.sh --check --diff

# Ograničenje na pojedinačan host
./apply.sh --limit srv-web-01

# Ograničenje na jednu grupu
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
5. U `playbooks/playbook.yml` dodaj play sa odgovarajućom inventory grupom.
6. Ako rola zahteva novu grupu, dodaj je u `bootstrap/template/inventory/hosts.ini.example`.

Nijedna vrednost specifična za neko okruženje — imena domena, IP adrese, nazivi organizacija, kredencijali — ne sme se naći u `defaults/main.yml`. Koristi neutralne placeholder vrednosti (`example.com`, `10.0.0.0/8`, `CHANGEME`).

---

## Status

Projekat je u ranoj fazi. Spisak dostupnih rola sa pripadajućim inventory grupama biće dodat kada role budu implementirane.

---

## Licenca

MIT
