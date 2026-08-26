# Rola: zabbix_server

Instalira i konfiguriše Zabbix server na Debian/Ubuntu sistemima.

Rola **bazu ne dira** — ne kreira je, ne uvozi šemu, ne menja privilegije. Samo se na nju povezuje.

---

## Podela posla

```text
zabbix_db      →  MySQL, baza, šema, nalozi   (na hostu baze)
zabbix_server  →  instalira i konfiguriše servis
zabbix_web     →  frontend
```

Uvoz šeme je posao role `zabbix_db`, jer zahteva root pristup bazi kroz lokalni unix socket. Nalog `zabbix` nema privilegije potrebne za `CREATE FUNCTION` na MySQL-u sa uključenim binarnim logom.

---

## Preduslovi

| Preduslov | Ko ga rešava |
|---|---|
| Zabbix repozitorijum | rola `repos`, grupa `[apply_repos]` |
| Baza sa uvezenom šemom | rola `zabbix_db`, grupa `[deploy_zabbix_db]` |
| Port 10051 otvoren | rola `firewall`, grupa `[apply_firewall]` |

U `playbook.yml` redosled je `apply_repos` → `deploy_zabbix_db` → `deploy_zabbix_server`.

> Rola `zabbix_db` pokriva samo **MySQL**. Uz `role_zabbix_server_db_backend: pgsql` bazu, šemu i naloge moraš pripremiti sam.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_server]
srv-mon-01
```

Grupi pripada `group_vars/deploy_zabbix_server.yml`, koji postavlja `role_zabbix_server_enabled: true`.

---

## Obavezna konfiguracija

Lozinka baze je jedina obavezna vrednost i mora biti **ista** kao `role_zabbix_db_password` na hostu baze:

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_password: "izaberi-dugacku-lozinku"
```

`host_vars` živi u `/opt/ansible/production/`, van git repozitorijuma. Postavi dozvole `0600`.

---

## Varijable

### Aktivacija i paket

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_server_db_backend` | `mysql` | `mysql` ili `pgsql`. Određuje samo ime paketa. |
| `role_zabbix_server_version` | `""` | Zakovana verzija. Prazno = najnovija. |

### Veza sa bazom

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_db_host` | `localhost` | IP ili ime hosta. Prazno = lokalni socket. |
| `role_zabbix_server_db_port` | `3306` | Piše se u konfiguraciju samo kada host nije `localhost`. |
| `role_zabbix_server_db_name` | `zabbix` | Ime baze. |
| `role_zabbix_server_db_user` | `zabbix` | Nalog. Isti kao `role_zabbix_db_server_user`. |
| `role_zabbix_server_db_password` | `""` | **Obavezno.** Isti kao `role_zabbix_db_password`. |
| `role_zabbix_server_db_socket` | `""` | Samo uz lokalnu bazu. |

### Mreža i logovanje

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_listen_port` | `10051` | Port na kojem server sluša. |
| `role_zabbix_server_listen_ip` | `""` | Prazno = sve adrese. |
| `role_zabbix_server_stats_allowed_ip` | `127.0.0.1` | Adrese koje smeju čitati `zabbix[stats]`. |
| `role_zabbix_server_logfile` | `/var/log/zabbix/zabbix_server.log` | Putanja loga. |
| `role_zabbix_server_logfile_size` | `10` | MB pre rotacije. |
| `role_zabbix_server_debug_level` | `3` | 0–5. Nivoi 4 i 5 brzo pune disk. |
| `role_zabbix_server_log_slow_queries` | `3000` | Milisekunde. Nula isključuje. |

### Procesi

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_start_pollers` | `5` | Pasivne provere. |
| `role_zabbix_server_start_pollers_unreachable` | `1` | Nedostupni hostovi. |
| `role_zabbix_server_start_trappers` | `5` | Prima podatke od agenata i proksija. |
| `role_zabbix_server_start_pingers` | `1` | ICMP provere. |
| `role_zabbix_server_start_discoverers` | `1` | Mrežno otkrivanje. |
| `role_zabbix_server_start_http_pollers` | `1` | Web scenariji. |
| `role_zabbix_server_start_preprocessors` | `3` | Obrada vrednosti pre upisa. |
| `role_zabbix_server_start_alerters` | `3` | Slanje obaveštenja. |

### Keševi

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_cache_size` | `32M` | Konfiguracija hostova i stavki. |
| `role_zabbix_server_history_cache_size` | `16M` | Podaci pre upisa u bazu. |
| `role_zabbix_server_history_index_cache_size` | `4M` | Indeks istorije. |
| `role_zabbix_server_trend_cache_size` | `4M` | Trendovi. |
| `role_zabbix_server_value_cache_size` | `8M` | Istorijske vrednosti za trigere. |

### Putanje i ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_alert_scripts_path` | `/usr/lib/zabbix/alertscripts` | Skripte za obaveštenja. |
| `role_zabbix_server_external_scripts` | `/usr/lib/zabbix/externalscripts` | Eksterne provere. |
| `role_zabbix_server_fping_location` | `/usr/bin/fping` | Putanja do `fping`. |
| `role_zabbix_server_timeout` | `4` | Sekunde. Do 30. |
| `role_zabbix_server_ha_node_name` | `""` | Ime čvora u HA klasteru. |
| `role_zabbix_server_ha_node_address` | `""` | Adresa čvora. |
| `role_zabbix_server_extra_config` | `""` | Proizvoljne linije. |
| `role_zabbix_server_service_enabled` | `true` | Startuje uz sistem. |
| `role_zabbix_server_service_state` | `started` | `started`, `stopped`. |

---

## Primeri

### Server i baza na istom hostu

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_db_password: "izaberi-dugacku-lozinku"
role_zabbix_server_db_host: localhost
role_zabbix_server_db_password: "izaberi-dugacku-lozinku"
```

Host ide u obe grupe, `[deploy_zabbix_db]` i `[deploy_zabbix_server]`.

### Baza na zasebnom hostu

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_host: "10.0.0.21"
role_zabbix_server_db_port: 3306
role_zabbix_server_db_socket: ""
role_zabbix_server_db_password: "izaberi-dugacku-lozinku"
```

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_password: "izaberi-dugacku-lozinku"
role_zabbix_db_bind_address: "0.0.0.0"
role_zabbix_db_server_hosts:
  - "10.0.0.50"

role_firewall_rules:
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> baza" }
```

> `role_zabbix_server_db_host` mora biti IP ili ime hosta, **nikada `localhost`** — MySQL klijent `localhost` tumači kao unix socket i ignoriše `DBPort`.

### Veće okruženje

```yaml
role_zabbix_server_start_pollers: 30
role_zabbix_server_start_preprocessors: 10
role_zabbix_server_start_trappers: 10
role_zabbix_server_cache_size: 256M
role_zabbix_server_history_cache_size: 128M
role_zabbix_server_value_cache_size: 128M
```

> Svaki proces troši memoriju i **jednu konekciju ka bazi**. Zbir svih `Start*` vrednosti mora stati u `role_zabbix_db_max_connections` na hostu baze.

### SNMP trapovi

```yaml
role_zabbix_server_extra_config: |
  SNMPTrapperFile=/var/log/snmptrap/snmptrap.log
  StartSNMPTrapper=1
```

### HA klaster

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_ha_node_name: "node-01"
role_zabbix_server_ha_node_address: "10.0.0.50:10051"
```

```yaml
# host_vars/srv-mon-02.yml
role_zabbix_server_ha_node_name: "node-02"
role_zabbix_server_ha_node_address: "10.0.0.51:10051"
```

Oba čvora koriste **istu bazu**, koju priprema jedan prolaz role `zabbix_db`.

---

## Napomene

**Verzija paketa mora odgovarati verziji šeme.** Ako zakuješ `role_zabbix_server_version`, zakuj i `role_zabbix_db_sql_scripts_version` na hostu baze. Neusklađenost se vidi tek kada server pri startu odbije da radi sa bazom pogrešne verzije.

**Konfiguracioni fajl sadrži lozinku**, pa ima dozvole `0640` i grupu `zabbix`. Task koji ga upisuje ima `no_log: true`, što znači da `--diff` neće prikazati razliku — to je cena zaštite lozinke.

**Rola ne otvara port.** Agenti i proksiji se javljaju na 10051; to pravilo pripada roli `firewall`.

**Prvi start može potrajati.** Posle uvoza šeme Zabbix server pri prvom pokretanju radi dodatne provere baze. Ako `systemctl status` pokaže da servis radi a frontend prijavljuje da server nije dostupan, sačekaj minut pa proveri log.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servis, osim kada se paket ili konfiguracija zaista promene.

---

## Struktura

```text
roles/zabbix_server/
├── README.md
├── defaults/main.yml
├── vars/main.yml
├── handlers/main.yml
├── tasks/main.yml
└── templates/zabbix_server.conf.j2
```

---

## Provera

```bash
./apply.sh --limit srv-mon-01

# Stanje servisa
ansible srv-mon-01 -m command -a "systemctl status zabbix-server"

# Log — traži "Zabbix Server started"
ansible srv-mon-01 -m command -a "tail -30 /var/log/zabbix/zabbix_server.log"

# Da li server sluša
ansible srv-mon-01 -m command -a "ss -lntp sport = :10051"
```

Na hostu baze:

```bash
# Da li je šema uvezena i koja je verzija
ansible srv-db-01 -m shell -a "mysql -e 'SELECT * FROM zabbix.dbversion;'" --become

# Da li baza sluša na mreži
ansible srv-db-01 -m command -a "ss -tln sport = :3306"
```

Sa hosta servera, provera da baza uopšte odgovara:

```bash
mysql -h 10.0.0.21 -u zabbix -p zabbix -e "SELECT 1;"
```

---

## Rešavanje problema

### Servis se pokrene pa odmah ugasi

Log je merodavan:

```bash
journalctl -u zabbix-server -n 50
tail -50 /var/log/zabbix/zabbix_server.log
```

Skoro uvek greška u konfiguraciji ili nedostupna baza.

### `Cannot connect to database` ili `database is not created`

Šema nije uvezena. To je posao role `zabbix_db` — pusti je na hostu baze:

```bash
./apply.sh --limit srv-db-01
```

Provera:

```bash
sudo mysql -e "SELECT * FROM zabbix.dbversion;"
```

### `ERROR 1045: Access denied for user 'zabbix'`

Tri moguća uzroka.

Lozinke se razilaze između `role_zabbix_db_password` i `role_zabbix_server_db_password`.

Nalog ne sme sa te adrese. Na hostu baze:

```bash
sudo mysql -e "SELECT user, host FROM mysql.user WHERE user='zabbix';"
```

Kolona `host` mora pokrivati IP sa koje server dolazi — proveri je sa `ip -4 addr show` na hostu servera i uskladi `role_zabbix_db_server_hosts`.

Nalog uopšte ne postoji, jer je rola `zabbix_db` pukla pre koraka u kojem se pravi.

### `ERROR 2003 ... (111)`

*Connection refused* — niko ne sluša na toj adresi. Da UFW blokira, veza bi visila do isteka vremena, ne pukla odmah. Skoro uvek znači da baza sluša samo na `127.0.0.1`. Na hostu baze:

```bash
sudo mysqld --verbose --help 2>/dev/null | grep -m1 '^bind-address'
```

Greška `2005` umesto `2003` znači da se ime hosta ne razrešava — problem je u DNS-u ili `/etc/hosts`.

### Verzija baze ne odgovara verziji servera

U logu servera piše da je potrebna nadogradnja baze, ili da je verzija previsoka. Uskladi `role_zabbix_server_version` i `role_zabbix_db_sql_scripts_version`.
