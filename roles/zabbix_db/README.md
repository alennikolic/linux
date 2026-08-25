# Rola: zabbix_db

Instalira bazu podataka i priprema je za Zabbix server.

Rola kreira **praznu** bazu sa ispravnim kodnim rasporedom i korisnika sa potrebnim privilegijama. Šemu uvozi rola `zabbix_server`.

---

## Podela posla

```text
zabbix_db      →  instalira MySQL/MariaDB, kreira praznu bazu i korisnika
zabbix_server  →  uvozi šemu u tu bazu
```

Granica je tu jer `.sql` skripte dolaze uz paket `zabbix-sql-scripts`, koji se instalira zajedno sa serverom.

Rola **ne dira postojeće podatke**. Bezbedno je pokrenuti je ponovo nad već podešenom bazom.

---

## Kritično: kolacija

Zabbix zahteva `utf8mb4` sa **`utf8mb4_bin`** kolacijom.

Ovo je najčešća greška pri ručnom postavljanju. Sa podrazumevanom `utf8mb4_0900_ai_ci` uvoz šeme uredno prođe, servis se pokrene, a frontend tek kasnije prijavi grešku o pogrešnoj kolaciji — do tada već imaš podatke u bazi.

Rola to proverava unapred i prekida rad ako je zadato nešto drugo.

---

## Preduslovi

| Zahtev | Razlog |
|---|---|
| Kolekcija `community.mysql` | moduli `mysql_db` i `mysql_user` |
| `python3-pymysql` na ciljnom hostu | rola ga sama instalira |
| Debian ili Ubuntu | rola prekida rad nad ostalim distribucijama |

```bash
ansible-galaxy collection install community.mysql
```

Ovo je **treća kolekcija** u projektu, pored `ansible.posix` i `community.general`.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_db]
srv-mon-01
```

Grupi pripada `group_vars/deploy_zabbix_db.yml`, koji postavlja `role_zabbix_db_enabled: true`.

Ako su baza i server na istom hostu, host ide u obe grupe. U `playbook.yml` `deploy_zabbix_db` ide pre `deploy_zabbix_server`, pa je redosled ispravan i pri jednom pokretanju.

---

## Obavezna konfiguracija

Lozinka mora biti **ista** u ovoj roli i u `zabbix_server`. Najlakše je definisati je jednom:

```bash
ansible-vault encrypt_string 'tvoja-lozinka' --name '_zabbix_db_pass'
```

```yaml
# host_vars/srv-mon-01.yml
_zabbix_db_pass: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...

role_zabbix_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
```

Tako se lozinka menja na jednom mestu i dve role ne mogu da se raziđu.

---

## Varijable

### Aktivacija i motor

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_db_engine` | `mysql` | `mysql` ili `mariadb`. |
| `role_zabbix_db_install_server` | `true` | Preskoči instalaciju ako baza već postoji. |

### Baza i korisnik

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_name` | `zabbix` | Ime baze. |
| `role_zabbix_db_user` | `zabbix` | Ime korisnika. |
| `role_zabbix_db_password` | `""` | **Obavezno.** Ide u vault. |
| `role_zabbix_db_user_host` | `localhost` | Odakle se korisnik sme prijaviti. |
| `role_zabbix_db_encoding` | `utf8mb4` | Ne menjati. |
| `role_zabbix_db_collation` | `utf8mb4_bin` | Ne menjati. |

### Mreža

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_bind_address` | `127.0.0.1` | `0.0.0.0` za pristup sa drugih hostova. |
| `role_zabbix_db_port` | `3306` | Port. |

### Performanse

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_innodb_buffer_pool_size` | `1G` | Najvažnije podešavanje. |
| `role_zabbix_db_innodb_buffer_pool_instances` | `1` | Jedna po gigabajtu bafera. |
| `role_zabbix_db_innodb_log_file_size` | `256M` | Veće = brži upis, sporiji oporavak. |
| `role_zabbix_db_innodb_flush_log_at_trx_commit` | `2` | `1` sigurnije, `2` brže. |
| `role_zabbix_db_max_connections` | `200` | Mora pokriti sve Zabbix procese. |
| `role_zabbix_db_max_allowed_packet` | `64M` | Najveći upit. |
| `role_zabbix_db_extra_config` | `""` | Proizvoljne linije. |

### Servis

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_service_enabled` | `true` | Startuje uz sistem. |
| `role_zabbix_db_service_state` | `started` | `started`, `stopped`. |

---

## Primeri

### Baza i server na istom hostu

```yaml
# host_vars/srv-mon-01.yml
_zabbix_db_pass: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...

role_zabbix_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
```

Ništa drugo nije potrebno — podrazumevani `bind-address` i `localhost` su tačni.

### Baza na zasebnom hostu

Na hostu baze:

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_bind_address: "0.0.0.0"
role_zabbix_db_user_host: "10.0.0.50"

role_firewall_rules:
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> baza" }
```

Na hostu servera:

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_host: "10.0.0.21"
```

> `bind-address: 0.0.0.0` znači da baza sluša na svim interfejsima. Pravilo zaštitnog zida nije preporuka nego uslov — baza otvorena prema celoj mreži je ozbiljan rizik.

### Podešavanje za veće okruženje

Server sa 16 GB RAM-a, namenjen samo bazi:

```yaml
role_zabbix_db_innodb_buffer_pool_size: 10G
role_zabbix_db_innodb_buffer_pool_instances: 10
role_zabbix_db_innodb_log_file_size: 1G
role_zabbix_db_max_connections: 500
```

Uskladi `max_connections` sa Zabbix procesima — zbir svih `Start*` vrednosti plus rezerva za frontend.

### Dodatna podešavanja

```yaml
role_zabbix_db_extra_config: |
  innodb_io_capacity = 2000
  innodb_io_capacity_max = 4000
  innodb_flush_method = O_DIRECT
```

`O_DIRECT` zaobilazi keš operativnog sistema i preporučuje se kada je `buffer_pool` velik.

### MariaDB umesto MySQL-a

```yaml
role_zabbix_db_engine: mariadb
```

Rola sama menja ime paketa, servisa i folder konfiguracije.

### Baza kojom upravlja neko drugi

```yaml
role_zabbix_db_install_server: false
```

Rola tada preskače instalaciju i konfiguraciju servera, a kreira samo bazu i korisnika. Korisno kod upravljanih baza u oblaku — mada tada ni `login_unix_socket` neće raditi, pa je verovatno lakše kreirati bazu ručno.

---

## Napomene

**Prijava kao root ide kroz unix socket.** Na Ubuntu i Debianu MySQL root koristi `auth_socket` dodatak — ko je root na sistemu, root je i u bazi, bez lozinke. Zato rola koristi `login_unix_socket` i ne traži lozinku root korisnika. Ako je na hostu root prebačen na prijavu lozinkom, rola neće raditi bez izmene.

**Konfiguracija ide u zaseban fajl.** `99-zabbix.cnf` u `mysql.conf.d/` (ili `mariadb.conf.d/`), ne u glavni `my.cnf`. Nadogradnja paketa tako ne prepisuje izmene, a prefiks `99-` osigurava da se učita poslednji i ima prednost.

**`flush_handlers` pre kreiranja baze.** Rola namerno primenjuje restart baze pre nego što kreira bazu, jer podešavanja kodnog rasporeda utiču na način kreiranja tabela. Bez toga bi restart došao na kraj play-a, posle kreiranja.

**Korisnik dobija `ALL` na svojoj bazi.** To je više nego što Zabbix serveru treba u svakodnevnom radu, ali je neophodno za uvoz šeme i za nadogradnju baze pri prelasku na noviju verziju Zabbix-a. Privilegije su ograničene na jednu bazu, ne na ceo server.

**`innodb_log_file_size` i postojeća baza.** Promena ove vrednosti nad bazom koja već ima podatke zahteva uredno gašenje servisa. MySQL 8.0 to rešava sam, ali stariji MariaDB ume da odbije start ako se veličina ne poklapa sa postojećim log fajlovima. Ako se to desi, poruka u `journalctl` je jasna.

**Rola ne pravi rezervne kopije.** Sigurnosno kopiranje baze je zaseban posao i ne pripada roli koja je postavlja.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok`. Modul `mysql_user` će prijaviti `changed` pri svakom pokretanju samo ako se lozinka menja — inače poredi heš i ne dira korisnika.

---

## Struktura

```text
roles/zabbix_db/
├── README.md
├── defaults/
│   └── main.yml
├── vars/
│   └── main.yml
├── handlers/
│   └── main.yml
├── tasks/
│   └── main.yml
└── templates/
    └── 99-zabbix.cnf.j2
```

---

## Provera

```bash
# Bez izmena
./apply.sh --limit deploy_zabbix_db --check --diff

# Primena
./apply.sh --limit srv-mon-01

# Stanje servisa
ansible srv-mon-01 -m command -a "systemctl status mysql"

# Da li baza postoji i sa kojom kolacijom
ansible srv-mon-01 -m shell -a \
  "mysql -e \"SELECT SCHEMA_NAME, DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='zabbix'\"" \
  --become

# Da li se korisnik moze prijaviti
ansible srv-mon-01 -m shell -a \
  "MYSQL_PWD=xxx mysql -u zabbix zabbix -e 'SELECT 1'"

# Primenjena podesavanja
ansible srv-mon-01 -m shell -a \
  "mysql -e \"SHOW VARIABLES LIKE 'innodb_buffer_pool_size'\"" --become
```

Očekivani rezultat provere kolacije:

```text
SCHEMA_NAME  DEFAULT_CHARACTER_SET_NAME  DEFAULT_COLLATION_NAME
zabbix       utf8mb4                     utf8mb4_bin
```

Ako je kolacija drugačija, baza je kreirana ručno ili pre ove role. Ispravka nad praznom bazom:

```sql
ALTER DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
```

Nad bazom sa podacima to nije dovoljno — postojeće tabele zadržavaju staru kolaciju.
