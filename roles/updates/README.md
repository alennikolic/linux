# Rola: updates

Ažurira pakete na Debian/Ubuntu sistemima — ceo sistem ili pojedinačno navedene pakete.

> **Rola menja stanje sistema.** Nadogradnja može promeniti ponašanje servisa, a kod kernela zahteva restart da bi izmena počela da važi. Pokreni `--check --diff` pre primene.

---

## Mesto u redosledu

```text
repos  →  packages  →  updates
```

Play u `playbook.yml` koristi **`serial: 1`** — hostovi se ažuriraju jedan po jedan. Ako nadogradnja obori servis, oboriće ga na jednom serveru, ne na celoj grupi istovremeno.

---

## Aktivacija

```ini
# inventory/hosts.ini
[apply_updates]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/apply_updates.yml`, koji postavlja `role_updates_enabled: true`. Taj fajl ne treba dirati.

Izuzetak po hostu:

```yaml
# inventory/host_vars/srv-db-01.yml
role_updates_enabled: false
```

Privremeno izuzimanje bez izmene inventory-ja:

```bash
./apply.sh --limit '!apply_updates'
```

---

## Dva režima

| Varijabla | Efekat |
|---|---|
| `role_updates_all: true` | Ažurira ceo sistem. |
| `role_updates_packages` | Ažurira samo navedene pakete. |

Međusobno se isključuju. Ako zadaš oboje, rola prekida rad — bez toga bi lista bila tiho ignorisana, a ti bi dobio nadogradnju celog sistema umesto jednog paketa.

Ako ne zadaš nijedno, rola takođe prekida rad. Host u grupi bez zadatog obima je skoro sigurno propust.

---

## Varijable

### Obim

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_updates_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_updates_all` | `false` | Ažurira ceo sistem. |
| `role_updates_packages` | `[]` | Lista paketa za pojedinačno ažuriranje. |
| `role_updates_upgrade_type` | `safe` | `safe` ili `full`. Važi samo uz `role_updates_all`. |

### Keš i čišćenje

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_updates_update_cache` | `true` | Osvežava listu paketa pre ažuriranja. |
| `role_updates_cache_valid_time` | `300` | Preskače osvežavanje ako je keš noviji (sekunde). |
| `role_updates_autoclean` | `false` | Briše preuzete `.deb` fajlove. |
| `role_updates_autoremove` | `false` | Uklanja nekorišćene zavisnosti. |

### Restart

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_updates_check_reboot` | `true` | Proverava `/var/run/reboot-required`. |
| `role_updates_fail_on_reboot` | `false` | Prekida rad ako je restart potreban. |

---

## Primeri

### Ceo sistem, sve hostove

```yaml
# group_vars/all.yml
role_updates_all: true
```

### Samo Zabbix komponente na monitoring serveru

```yaml
# host_vars/srv-mon-01.yml
role_updates_packages:
  - zabbix-server-mysql
  - zabbix-frontend-php
  - zabbix-sql-scripts
```

### Samo agent na svim ostalim

```yaml
# group_vars/all.yml
role_updates_packages:
  - zabbix-agent
```

### Agresivna nadogradnja sa čišćenjem

```yaml
role_updates_all: true
role_updates_upgrade_type: full
role_updates_autoclean: true
role_updates_autoremove: true
```

`full` odgovara `apt dist-upgrade` — rešava zavisnosti i **sme da ukloni pakete**. Uz `autoremove` to je najagresivnija kombinacija. Ne bih je koristio na produkciji bez prethodnog `--check --diff`.

### Prekid ako je restart potreban

```yaml
role_updates_all: true
role_updates_fail_on_reboot: true
```

Korisno u CI-ju ili kada želiš da ažuriranje ne prođe tiho. Uz `serial: 1` playbook staje na prvom hostu koji traži restart, pa ostatak grupe ostaje netaknut dok ne rešiš prvi.

---

## Napomene

**Rola nikada ne restartuje sistem.** To je svesna odluka. Restart produkcijskog servera zavisi od prozora održavanja, klastera, ljudi na smeni — ništa od toga rola ne zna. Umesto toga proverava `/var/run/reboot-required`, koji Ubuntu i Debian kreiraju kroz `postinst` skripte kernela, `glibc`-a i `libssl`-a, i ispisuje spisak paketa iz `/var/run/reboot-required.pkgs`.

Kada vidiš to upozorenje, restart pokreni sam:

```bash
ansible srv-web-01 -m reboot --become
```

**`safe` naspram `full`.** `safe` nadograđuje sve što može bez uklanjanja ijednog paketa. `full` sme da ukloni paket da bi razrešio zavisnost — što ume da bude upravo onaj od kojeg zavisi tvoj servis. Podrazumevano je `safe`.

**Zakovane verzije se ne nadograđuju.** Ako si u roli `packages` zadao `zabbix-agent=1:7.0.19-1+ubuntu24.04`, `updates` će ga preskočiti. To je očekivano ponašanje `apt`-a, ne greška.

**`cache_valid_time` je ovde nizak** (300 sekundi, naspram 3600 u roli `packages`). Ažuriranje na osnovu starog keša propušta upravo one nadogradnje zbog kojih se rola i pokreće.

**Idempotentnost.** Rola **nije** idempotentna u strogom smislu. Kada u repozitorijumu postoji nova verzija, pokretanje prijavljuje `changed` — to je svrha role. Nad potpuno ažuriranim sistemom prijavljuje `ok`.

**`autoremove` je isključen podrazumevano.** Isti razlog kao u roli `packages` — ume da ukloni više nego što očekuješ, posebno na serverima gde je nešto instalirano ručno.

---

## Struktura

```text
roles/updates/
├── README.md
├── defaults/
│   └── main.yml
└── tasks/
    └── main.yml
```

Rola nema `handlers/` — nadogradnja paketa restartuje sopstvene servise kroz `postinst` skripte.

---

## Provera

```bash
# Sta bi bilo nadogradjeno, bez izmena
./apply.sh --limit apply_updates --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Koliko paketa ceka nadogradnju
ansible srv-web-01 -m command -a "apt list --upgradable"

# Da li je restart potreban
ansible srv-web-01 -m command -a "cat /var/run/reboot-required.pkgs"
```

Poslednja komanda vraća grešku ako fajl ne postoji — to znači da restart nije potreban.
