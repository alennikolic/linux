# Rola: zabbix_db

Instalira MySQL, kreira bazu za Zabbix, uvozi šemu i pravi naloge.

> **Uvoz šeme je nepovratan.** Rola ga preskače ako šema već postoji, ali prvi uvoz nad pogrešnom bazom se ne može poništiti.

Rola mora raditi **na hostu baze** — bazi pristupa lokalno, kao root kroz unix socket. Ako je baza na zasebnom serveru, taj server ide u grupu `[deploy_zabbix_db]`.

---

## Podela posla

```text
zabbix_db      →  MySQL, baza, šema, nalozi
zabbix_server  →  instalira i konfiguriše servis
zabbix_web     →  frontend
```

Pošto ova rola uvozi šemu, na hostu servera isključi njegov uvoz:

```yaml
role_zabbix_server_db_import: false
```

---

## Kritično: kolacija

Zabbix zahteva `utf8mb4` sa **`utf8mb4_bin`**. Sa podrazumevanom `utf8mb4_0900_ai_ci` uvoz uredno prođe, a frontend tek kasnije prijavi grešku — do tada već imaš podatke u bazi.

Rola proverava i podešene vrednosti i stvarno stanje baze, pre uvoza.

---

## Preduslovi

| Zahtev | Razlog |
|---|---|
| Kolekcija `community.mysql` | moduli `mysql_db`, `mysql_user`, `mysql_query`, `mysql_variables` |
| Zabbix repozitorijum na hostu baze | paket `zabbix-sql-scripts` |
| Debian ili Ubuntu | rola prekida rad nad ostalim distribucijama |
| Rola radi na hostu baze | uvoz ide kroz lokalni unix socket |

```bash
ansible-galaxy collection install community.mysql
```

U `playbook.yml` `apply_repos` mora ići **pre** `deploy_zabbix_db`.

---

## Aktivacija

```ini
# inventory/hosts.ini
[apply_repos]
srv-db-01

[deploy_zabbix_db]
srv-db-01
```

Grupi pripada `group_vars/deploy_zabbix_db.yml`, koji postavlja `role_zabbix_db_enabled: true`.

---

## Obavezna konfiguracija

Lozinka mora biti ista ovde i u roli `zabbix_server`:

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_password: "izaberi-dugacku-lozinku"
```

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_password: "izaberi-dugacku-lozinku"
role_zabbix_server_db_import: false
```

`host_vars` živi van git repozitorijuma, na kontrolnom čvoru. Postavi dozvole `0600`.

---

## Varijable

### Aktivacija i instalacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_db_install_server` | `true` | Preskoči instalaciju ako MySQL već postoji. |

### Baza i nalog Zabbix servera

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_name` | `zabbix` | Ime baze. |
| `role_zabbix_db_server_user` | `zabbix` | Nalog koji koristi Zabbix server. |
| `role_zabbix_db_password` | `""` | **Obavezno.** Lozinka gornjeg naloga. |
| `role_zabbix_db_server_hosts` | `[localhost]` | Lista adresa sa kojih se nalog sme prijaviti. |
| `role_zabbix_db_encoding` | `utf8mb4` | Ne menjati. |
| `role_zabbix_db_collation` | `utf8mb4_bin` | Ne menjati. |

> U MySQL-u nalog je par korisnik@host. Isto ime sa dve adrese su **dva naloga**, sa zasebnim privilegijama i zasebnim hešom lozinke. Rola pravi po jedan za svaku stavku liste.

### Nalog frontenda

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_frontend_enabled` | `false` | Uključuje zaseban nalog za frontend. |
| `role_zabbix_db_frontend_user` | `zabbix_web` | Mora se razlikovati od naloga servera. |
| `role_zabbix_db_frontend_password` | `""` | Obavezno kada je nalog uključen. |
| `role_zabbix_db_frontend_hosts` | `[]` | Obavezno kada je nalog uključen. |
| `role_zabbix_db_frontend_priv` | `SELECT,INSERT,UPDATE,DELETE` | Privilegije nad bazom. |

### Uvoz šeme

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_schema_import` | `true` | Uvozi ako tabela `dbversion` ne postoji. |
| `role_zabbix_db_sql_scripts_version` | `""` | Zakovana verzija paketa `zabbix-sql-scripts`. |
| `role_zabbix_db_log_bin_trust` | `true` | Privremeno uključuje `log_bin_trust_function_creators`. |

### Mreža

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_bind_address` | `127.0.0.1` | `0.0.0.0` za pristup sa drugih hostova. |
| `role_zabbix_db_port` | `3306` | Port. |

### Performanse

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_db_innodb_buffer_pool_size` | `1G` | Najvažnije podešavanje. 50–70% RAM-a na namenskom serveru. |
| `role_zabbix_db_innodb_buffer_pool_instances` | `1` | Jedna po gigabajtu bafera. |
| `role_zabbix_db_innodb_log_file_size` | `256M` | Veće = brži upis, sporiji oporavak. |
| `role_zabbix_db_innodb_flush_log_at_trx_commit` | `2` | `1` sigurnije, `2` brže. |
| `role_zabbix_db_max_connections` | `200` | Mora pokriti sve Zabbix procese. |
| `role_zabbix_db_max_allowed_packet` | `64M` | Ispod 32M uvoz šeme može pući. |
| `role_zabbix_db_extra_config` | `""` | Proizvoljne linije u `zz-zabbix.cnf`. |

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
role_zabbix_db_password: "izaberi-dugacku-lozinku"
role_zabbix_server_db_password: "izaberi-dugacku-lozinku"
role_zabbix_server_db_import: false
```

Podrazumevani `bind-address` i `localhost` su tačni, ništa drugo nije potrebno.

### Baza, server i frontend na tri hosta

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_password: "prva-lozinka"
role_zabbix_db_bind_address: "0.0.0.0"

role_zabbix_db_server_hosts:
  - "10.0.0.50"

role_zabbix_db_frontend_enabled: true
role_zabbix_db_frontend_password: "druga-lozinka"
role_zabbix_db_frontend_hosts:
  - "10.0.0.60"

role_firewall_rules:
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> baza" }
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.60", comment: "Zabbix frontend -> baza" }
```

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_host: "10.0.0.21"
role_zabbix_server_db_password: "prva-lozinka"
role_zabbix_server_db_import: false
```

```yaml
# host_vars/srv-web-01.yml
role_zabbix_web_db_host: "10.0.0.21"
role_zabbix_web_db_user: "zabbix_web"
role_zabbix_web_db_password: "druga-lozinka"
```

> `bind-address: 0.0.0.0` znači da baza sluša na svim interfejsima — pravilo zaštitnog zida nije preporuka nego uslov.
>
> `role_zabbix_server_db_host` mora biti IP ili ime hosta, **nikada `localhost`** — MySQL klijent `localhost` tumači kao unix socket i ignoriše port.

### Veće okruženje

```yaml
role_zabbix_db_innodb_buffer_pool_size: 10G
role_zabbix_db_innodb_buffer_pool_instances: 10
role_zabbix_db_innodb_log_file_size: 1G
role_zabbix_db_max_connections: 500
```

Uskladi `max_connections` sa Zabbix procesima — zbir svih `Start*` vrednosti plus rezerva za frontend.

---

## Napomene

**Konfiguracija ide u `zz-zabbix.cnf`.** Prefiks nije kozmetički: MySQL čita fajlove iz `/etc/mysql/mysql.conf.d/` azbučnim redom i primenjuje poslednju pročitanu vrednost. Ime koje počinje ciframa (`99-`) učitalo bi se **pre** `mysqld.cnf` i bilo pregaženo — suprotno od ponašanja `systemd`-a i `logrotate`-a.

**Prekinut uvoz rola ne prepoznaje.** Tabela `dbversion` se kreira tek pri kraju skripte. Ako uvoz pukne na pola, u bazi ostane 150–200 tabela, ali provere nema, pa sledeće pokretanje pada na prvom `CREATE TABLE`. Jedini oporavak je brisanje baze.

**Verzija šeme mora odgovarati verziji servera.** Ako je `role_zabbix_server_version` zakovana, zakuj i `role_zabbix_db_sql_scripts_version` na istu vrednost.

**Rola ne briše naloge sa drugih adresa.** Ako skratiš `role_zabbix_db_server_hosts`, stari nalozi ostaju — automatsko brisanje bi moglo prekinuti vezu servera koji radi. Ukloni ih ručno.

**`--check` na svežem hostu ne radi.** Provere kolacije i šeme čitaju iz baze koja u tom trenutku još ne postoji.

**Idempotentnost.** Ponovljeno pokretanje prijavljuje `ok` i ne restartuje bazu, osim kada se konfiguracija zaista promeni. Izuzetak je task uvoza, koji ima `changed_when: true` — ali se izvršava samo kada šeme nema.

---

## Struktura

```text
roles/zabbix_db/
├── README.md
├── defaults/main.yml
├── vars/main.yml
├── handlers/main.yml
├── tasks/main.yml
└── templates/zz-zabbix.cnf.j2
```

---

## Provera

```bash
./apply.sh --limit srv-db-01

# Da li je šema uvezena i koja je verzija
ansible srv-db-01 -m shell -a "mysql -e 'SELECT * FROM zabbix.dbversion;'" --become

# Kolacija baze
ansible srv-db-01 -m shell -a \
  "mysql -e \"SELECT default_character_set_name, default_collation_name \
   FROM information_schema.schemata WHERE schema_name='zabbix';\"" --become

# Nalozi
ansible srv-db-01 -m shell -a \
  "mysql -e \"SELECT user, host FROM mysql.user WHERE user LIKE 'zabbix%';\"" --become

# Šta baza stvarno vidi kao bind-address
ansible srv-db-01 -m shell -a \
  "mysqld --verbose --help 2>/dev/null | grep -m1 '^bind-address'" --become
```

---

## Rešavanje problema

### `Instalacija paketa zabbix-sql-scripts nije uspela`

Zabbix repozitorijum nije dodat na host baze. Host mora biti i u `[apply_repos]`:

```bash
apt-cache policy zabbix-sql-scripts
```

### `Unable to start service mysql`

Poruka `service` modula ne kaže uzrok. Pravu grešku daje:

```bash
sudo journalctl -xeu mysql.service --no-pager | tail -40
sudo tail -50 /var/log/mysql/error.log
sudo mysqld --user=mysql --verbose --help >/dev/null
```

Najčešće: `/var/lib/mysql` je obrisan a paket nije bio purge-ovan, pa `apt` javlja da je sve na mestu i mysqld startuje nad praznim folderom.

```bash
sudo apt-get purge -y 'mysql-server*'
sudo rm -rf /var/lib/mysql
sudo apt-get install -y mysql-server
```

### `ERROR 1050: Table already exists`

Prethodni uvoz je prekinut. Proveri stanje:

```bash
sudo mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix';"
sudo mysql -e "SELECT * FROM zabbix.dbversion;"
```

Ako `dbversion` ne postoji a tabela ima, baza je neupotrebljiva:

```bash
sudo mysql -e "DROP DATABASE zabbix;"
```

Zatim pusti rolu ponovo. Nalozi preživljavaju `DROP DATABASE`, ali gube privilegije nad obrisanom bazom; rola ih vraća.

### `Baza postoji, ali ima utf8mb4_0900_ai_ci`

Baza je kreirana ručno ili pre nego što je konfiguracija role počela da važi. Rola prekida rad **pre** uvoza — namerno, jer bi sa pogrešnom kolacijom uvoz prošao a greška se pojavila tek u frontendu. Konverzija postojeće šeme nije pouzdana; obriši bazu i pusti rolu ponovo.

### `MySQL server has gone away` tokom uvoza

`max_allowed_packet` je premali. Vrati na `64M`.

### `ERROR 1045: Access denied for user 'zabbix'` sa hosta servera

Lozinke se razilaze između role, ili nalog ne sme sa te adrese:

```bash
sudo mysql -e "SELECT user, host FROM mysql.user WHERE user='zabbix';"
```

Kolona `host` mora pokrivati IP sa koje server dolazi — proveri je sa `ip -4 addr show` na hostu servera.

### `ERROR 2003 ... (111)`

*Connection refused* — niko ne sluša na toj adresi. Da UFW blokira, veza bi visila do isteka vremena. Skoro uvek znači da baza sluša samo na `127.0.0.1`:

```bash
sudo mysqld --verbose --help 2>/dev/null | grep -m1 '^bind-address'
```
