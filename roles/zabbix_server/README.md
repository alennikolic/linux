# Rola: zabbix_server

Instalira i konfiguriše Zabbix server na Debian/Ubuntu sistemima.

> **Rola dira bazu podataka.** Uvoz šeme je jednokratna, nepovratna operacija. Rola proverava da li šema već postoji i preskače uvoz ako jeste, ali prvi uvoz nad pogrešnom bazom se ne može poništiti.

---

## Preduslovi

Tri stvari moraju biti gotove pre ove role:

| Preduslov | Ko ga rešava |
|---|---|
| Zabbix repozitorijum | rola `repos`, grupa `[apply_repos]` |
| Baza i korisnik | rola `zabbix_db`, grupa `[deploy_zabbix_db]` |
| Port 10051 otvoren | rola `firewall`, grupa `[apply_firewall]` |

### Podela posla sa rolom `zabbix_db`

```text
zabbix_db      →  instalira MySQL, kreira praznu bazu i korisnika
zabbix_server  →  uvozi šemu u tu bazu
```

Granica je tu jer `.sql` skripte dolaze uz paket `zabbix-sql-scripts`, koji se instalira zajedno sa serverom. Baza može biti i na drugom hostu — tada ovaj host mora imati mrežni pristup do nje.

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

Lozinka baze je jedina obavezna vrednost. Šifruj je:

```bash
ansible-vault encrypt_string 'tvoja-lozinka' --name 'role_zabbix_server_db_password'
```

Rezultat upiši u `host_vars/srv-mon-01.yml`:

```yaml
role_zabbix_server_db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...
```

Bez toga rola prekida rad na trećoj proveri.

---

## Varijable

### Aktivacija i backend

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_server_db_backend` | `mysql` | `mysql` ili `pgsql`. |
| `role_zabbix_server_version` | `""` | Zakovana verzija. Prazno = najnovija. |

### Baza

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_db_host` | `localhost` | Adresa baze. |
| `role_zabbix_server_db_port` | `3306` | Port. |
| `role_zabbix_server_db_name` | `zabbix` | Ime baze. |
| `role_zabbix_server_db_user` | `zabbix` | Korisnik. |
| `role_zabbix_server_db_password` | `""` | **Obavezno.** Ide u vault. |
| `role_zabbix_server_db_socket` | `""` | Putanja socket fajla. |
| `role_zabbix_server_db_import` | `true` | Uvozi šemu pri prvoj primeni. |
| `role_zabbix_server_db_set_log_bin_trust` | `true` | Privremeno menja MySQL globalnu opciju. |

### Mreža i logovanje

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_listen_port` | `10051` | Port servera. |
| `role_zabbix_server_listen_ip` | `""` | Prazno = sve adrese. |
| `role_zabbix_server_stats_allowed_ip` | `127.0.0.1` | Ko sme čitati interne statistike. |
| `role_zabbix_server_logfile` | `/var/log/zabbix/zabbix_server.log` | Log fajl. |
| `role_zabbix_server_logfile_size` | `10` | MB. |
| `role_zabbix_server_debug_level` | `3` | 0–5. |
| `role_zabbix_server_log_slow_queries` | `3000` | Milisekunde. Nula isključuje. |

### Procesi

| Varijabla | Podrazumevano |
|---|---|
| `role_zabbix_server_start_pollers` | `5` |
| `role_zabbix_server_start_pollers_unreachable` | `1` |
| `role_zabbix_server_start_trappers` | `5` |
| `role_zabbix_server_start_pingers` | `1` |
| `role_zabbix_server_start_discoverers` | `1` |
| `role_zabbix_server_start_http_pollers` | `1` |
| `role_zabbix_server_start_preprocessors` | `3` |
| `role_zabbix_server_start_alerters` | `3` |

### Keševi

| Varijabla | Podrazumevano |
|---|---|
| `role_zabbix_server_cache_size` | `32M` |
| `role_zabbix_server_history_cache_size` | `16M` |
| `role_zabbix_server_history_index_cache_size` | `4M` |
| `role_zabbix_server_trend_cache_size` | `4M` |
| `role_zabbix_server_value_cache_size` | `8M` |

### Ostalo

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
role_zabbix_server_db_host: localhost
role_zabbix_server_db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...
```

### Baza na zasebnom hostu

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_host: "10.0.0.21"
role_zabbix_server_db_port: 3306
role_zabbix_server_db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...
```

Na hostu baze mora postojati pravilo zaštitnog zida:

```yaml
# host_vars/srv-db-01.yml
role_firewall_rules:
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> baza" }
```

### Podešavanje za veće okruženje

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_start_pollers: 30
role_zabbix_server_start_preprocessors: 10
role_zabbix_server_start_trappers: 10
role_zabbix_server_cache_size: 256M
role_zabbix_server_history_cache_size: 128M
role_zabbix_server_value_cache_size: 128M
```

> Svaki proces troši memoriju i **jednu konekciju ka bazi**. Zbir svih `Start*` vrednosti ne sme preći `max_connections` na bazi. Sa gornjim vrednostima to je preko 60 konekcija — podrazumevanih 151 na MySQL-u je dovoljno, ali ostavlja manje prostora nego što izgleda.

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

Oba čvora koriste **istu bazu**. Šema se uvozi samo jednom — drugi čvor će je zateći i preskočiti uvoz.

---

## Napomene

**Uvoz šeme se dešava samo jednom.** Provera se radi upitom nad tabelom `dbversion`. Ako upit prođe, šema postoji i uvoz se preskače. Ako baza nije dostupna, upit takođe ne prolazi — pa rola pokušava uvoz i pada sa greškom veze. To je namerno: tiho preskakanje bi ostavilo server bez šeme.

**Lozinka ide kroz promenljivu okruženja.** Taskovi koriste `MYSQL_PWD` umesto `-p` argumenta, jer su argumenti komande vidljivi svakome ko pokrene `ps` na hostu tokom izvršavanja. Svi taskovi koji dodiruju lozinku imaju `no_log: true`.

**`log_bin_trust_function_creators`.** MySQL 8.0 sa uključenim binarnim logom odbija `CREATE FUNCTION` iz Zabbix šeme. Rola tu globalnu opciju uključuje pre uvoza i vraća na `0` posle. Za to je potrebna `SUPER` privilegija. Ako je nemaš, postavi `role_zabbix_server_db_set_log_bin_trust: false` i zamoli administratora baze da opciju podesi ručno pre pokretanja.

**PostgreSQL nije automatizovan.** Rola instalira ispravan paket i konfiguriše vezu, ali uvoz šeme za `pgsql` ostaje ručan — ispisuje tačnu komandu u izlazu. Razlog je što PostgreSQL traži drugačiji tok autentikacije (`peer` naspram lozinke) koji zavisi od `pg_hba.conf`, a to je konfiguracija koju ova rola ne kontroliše.

**Konfiguracioni fajl sadrži lozinku**, pa ima dozvole `0640` i grupu `zabbix`. Task koji ga upisuje ima `no_log: true`, što znači da `--diff` neće prikazati razliku — to je cena zaštite lozinke.

**Rola ne otvara port.** Agenti se javljaju na 10051; to pravilo pripada roli `firewall`.

**Prvi start može potrajati.** Posle uvoza šeme Zabbix server pri prvom pokretanju radi dodatne provere baze. Ako `systemctl status` pokaže da servis radi a frontend prijavljuje da server nije dostupan, sačekaj minut pa proveri log.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servis, osim kada se paket ili konfiguracija zaista promene.

---

## Struktura

```text
roles/zabbix_server/
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
    └── zabbix_server.conf.j2
```

---

## Provera

```bash
# Bez izmena
./apply.sh --limit deploy_zabbix_server --check --diff

# Primena
./apply.sh --limit srv-mon-01

# Stanje servisa
ansible srv-mon-01 -m command -a "systemctl status zabbix-server"

# Log — trazi "Zabbix Server started"
ansible srv-mon-01 -m command -a "tail -30 /var/log/zabbix/zabbix_server.log"

# Da li sema postoji i koja je verzija
ansible srv-mon-01 -m shell -a \
  "MYSQL_PWD=xxx mysql -u zabbix zabbix -e 'SELECT * FROM dbversion'"

# Da li server slusa
ansible srv-mon-01 -m command -a "ss -lntp sport = :10051"
```

---

## Rešavanje problema

**`Access denied for user 'zabbix'`**

Baza ili korisnik ne postoje, ili lozinka ne odgovara. Proveri da je rola `zabbix_db` prošla i da je ista lozinka u obe role.

**`Cannot connect to database` a baza je na drugom hostu**

MySQL podrazumevano sluša samo na `127.0.0.1`. Proveri `bind-address` u konfiguraciji baze i pravilo zaštitnog zida.

**Uvoz pada sa `You do not have the SUPER privilege`**

`log_bin_trust_function_creators` ne može biti postavljen. Postavi `role_zabbix_server_db_set_log_bin_trust: false` i neka administrator baze to reši.

**Servis se pokreće pa odmah gasi**

Skoro uvek greška u konfiguraciji ili nedostupna baza. Log je merodavan:

```bash
journalctl -u zabbix-server -n 50
```
