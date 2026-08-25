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
| Popunjeni `host_vars/`, `group_vars/all.yml` | isto |
| Aktivan `ansible.cfg` | isto (kreira ga `init.sh`) |
| Vault lozinke, sertifikati, ključevi | isto, nikada u git |

Sve vrednosti u `roles/*/defaults/main.yml` su neutralni podrazumevani parametri. Stvarna konfiguracija se definiše kroz `group_vars` i `host_vars` na strani korisnika.

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
| `deploy_` | donosi nešto novo na sistem | `deploy_packages`, `deploy_root_ca` |

Pravilo je konvencija, ne tehnička razlika — Ansible-u je svejedno. Postoji da bi iz imena grupe bilo jasno da li rola konfiguriše ili instalira.

### Izuzetak po hostu

Pošto `host_vars` ima viši prioritet od `group_vars`, host može ostati u grupi a da rola nad njim bude privremeno isključena:

```yaml
# inventory/host_vars/srv-db-01.yml
role_banner_enabled: false    # u grupi je, ali privremeno preskoči
```

Korisno kada host ne sme da se dira, a ne želiš da izgubiš trag da inače pripada toj grupi. Playbook će prijaviti `skipped`.

### Kaskadno uključivanje

Ako više grupa servera treba da dobije istu rolu, koristi `children` umesto ponavljanja hostova:

```ini
[webservers]
srv-web-01
srv-web-02

[dbservers]
srv-db-01

[deploy_packages:children]
webservers
dbservers
```

### Isključivanje pri pokretanju

Privremeno izuzimanje ne zahteva izmenu inventory-ja:

```bash
./apply.sh --limit '!apply_updates'     # preskoči jednu grupu
./apply.sh --limit apply_banner         # pokreni samo jednu
```

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

`init.sh` se pokreće **samo jednom**. Ako ciljni folder već sadrži `ansible.cfg`, skripta prekida rad i ne dira postojeće fajlove — nema rizika od gubitka konfiguracije pri ponovnom pokretanju.

Skripta namerno **ne** pokreće `git init` u ciljnom folderu. Ako želiš da versioniraš svoju konfiguraciju, uradi to svesno i isključivo ka privatnom remote-u.

### 3. Popuni konfiguraciju

```bash
cd /opt/ansible/production
mv inventory/hosts.ini.example inventory/hosts.ini
```

Uredi `hosts.ini` prema svom okruženju — sadrži spisak svih dostupnih grupa, praznih. Upisuješ samo hostove koje želiš.

Fajlove u `group_vars/` ne treba dirati; oni već postavljaju odgovarajuće `role_*_enabled` prekidače.

### 4. Provera

```bash
./apply.sh --check --diff --limit <host>
```

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

Sve varijable su prefiksirane imenom role, čime se izbegavaju kolizije:

```text
role_<ime_role>_<parametar>
```

Svaka rola ima potpunu dokumentaciju varijabli sa primerima u sopstvenom `defaults/main.yml`. To je primarni izvor informacija — ovaj README daje samo pregled principa.

---

## Primer: primena role

Na primeru role `banner`, koja upravlja sadržajem `/etc/motd`:

**1.** Dodaj hostove u grupu `apply_banner` u `hosts.ini`:

```ini
[apply_banner]
srv-web-01
srv-web-02
```

**2.** To je dovoljno. `group_vars/apply_banner.yml` već postavlja `role_banner_enabled: true`, pa se rola primenjuje sa podrazumevanim tekstom iz `defaults/main.yml`.

**3.** Po potrebi prilagodi sadržaj u `host_vars/srv-web-01.yml`:

```yaml
role_banner_text: |
  *****************************************************************
  * UPOZORENJE: Pristup samo za ovlašćena lica                    *
  * Host: {{ inventory_hostname }}
  * Sve aktivnosti se beleže.                                     *
  *****************************************************************
```

Ako `role_banner_text` nije definisan, koristi se `role_banner_default_text`.

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

Pre prve primene nad produkcijom pokreni `--check --diff` uz `--limit` na jedan host. Role koje menjaju stanje sistema nepovratno su kao takve označene na vrhu svog `defaults/main.yml`.

---

## Dodavanje nove role

Da bi rola bila u skladu sa ostatkom projekta:

1. Kreiraj `roles/<ime>/` sa `defaults/`, `tasks/` i po potrebi `handlers/` i `templates/`.
2. U `defaults/main.yml` definiši `role_<ime>_enabled: false` uz komentar i primer korišćenja.
3. Sve ostale varijable prefiksiraj sa `role_<ime>_` i dokumentuj ih na istom mestu.
4. U `tasks/main.yml` omotaj taskove u `block:` sa `when: role_<ime>_enabled | default(false) | bool`.
5. Ako rola menja stanje sistema nepovratno, napiši upozorenje na vrhu `defaults/main.yml`.
6. U `playbooks/playbook.yml` dodaj play sa namenskom grupom, uz prefiks `apply_` ili `deploy_` prema tabeli iznad.
7. Dodaj tu grupu, praznu, u `bootstrap/template/inventory/hosts.ini.example`.
8. Dodaj `bootstrap/template/inventory/group_vars/<grupa>.yml` koji postavlja `role_<ime>_enabled: true`.

Koraci 7 i 8 idu zajedno — grupa bez pripadajućeg `group_vars` fajla neće aktivirati rolu, a Ansible to neće prijaviti kao grešku.

Nijedna vrednost specifična za neko okruženje — imena domena, IP adrese, nazivi organizacija, kredencijali — ne sme se naći u `defaults/main.yml`. Koristi neutralne placeholder vrednosti (`example.com`, `10.0.0.0/8`, `CHANGEME`).

---

## Status

Projekat je u ranoj fazi. Spisak dostupnih rola sa pripadajućim inventory grupama biće dodat kada role budu implementirane.

---

## Licenca

MIT
