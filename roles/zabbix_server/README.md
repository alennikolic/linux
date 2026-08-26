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

## Baza na drugom hostu — ručni koraci

Kada baza nije na istom hostu kao server, četiri stvari rola **ne rešava sama**. Sve četiri se izvode jednom, pre prvog pokretanja role.

### 1. Baza mora slušati na mreži

Rola `zabbix_db` upisuje `bind-address` iz varijable `role_zabbix_db_bind_address`, koja je podrazumevano `127.0.0.1`. Na hostu baze:

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_bind_address: "0.0.0.0"
role_zabbix_db_user_host: "10.0.0.50"   # adresa Zabbix SERVERA
```

`bind_address` i `user_host` su dve odvojene stvari: prva je adresa na kojoj proces sluša, druga je dozvola u bazi. Bez prve, druga nema efekta.

Provera na hostu baze:

```bash
ss -tln | grep 3306          # ocekuje se 0.0.0.0:3306, ne 127.0.0.1:3306
```

> **Zamka sa imenom konfiguracionog fajla.** Rola upisuje `99-zabbix.cnf` u `/etc/mysql/mysql.conf.d/`. MySQL učitava fajlove iz tog foldera **azbučnim redom** i primenjuje **poslednju** pročitanu vrednost svake opcije. Pošto cifra `9` dolazi pre slova `m`, `99-zabbix.cnf` se učitava **pre** `mysqld.cnf`, pa `bind-address` iz njega biva pregažen. Prefiks sa brojem ovde radi suprotno nego kod `systemd`-a, `sysctl`-a ili `logrotate`-a.
>
> Dok se rola ne izmeni, rešenje je ručno preimenovanje na hostu baze:
> ```bash
> sudo mv /etc/mysql/mysql.conf.d/99-zabbix.cnf /etc/mysql/mysql.conf.d/zz-zabbix.cnf
> sudo systemctl restart mysql
> ```
> Rola će pri sledećem pokretanju ponovo napraviti `99-zabbix.cnf`. Ako oba fajla postoje, `zz-` pobeđuje, pa je stanje ispravno — ali je zbunjujuće. Proveri šta baza stvarno vidi:
> ```bash
> sudo mysqld --verbose --help 2>/dev/null | grep -m1 '^bind-address'
> ```

### 2. Port mora biti otvoren

```yaml
# host_vars/srv-db-01.yml
role_firewall_rules:
  - rule: allow
    port: 3306
    proto: tcp
    from: "10.0.0.50"
    comment: "Zabbix server -> baza"
```

Pravilo nije preporuka nego uslov — uz `bind-address: 0.0.0.0` baza je inače otvorena prema celoj mreži.

### 3. Server mora znati adresu baze

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_host: "10.0.0.21"
role_zabbix_server_db_port: 3306
role_zabbix_server_db_socket: ""
```

Mora biti IP ili ime hosta, **nikada `localhost`** — MySQL klijent tumači `localhost` kao unix socket i ignoriše `DBPort`.

### 4. `log_bin_trust_function_creators` mora biti uključen ručno

Ovo je najvažniji ručni korak i najčešći uzrok neuspelog uvoza šeme.

Zabbix šema sadrži `CREATE FUNCTION` naredbe. MySQL 8.0 sa uključenim binarnim logom — što je podrazumevano stanje — odbija kreiranje funkcija od korisnika bez `SUPER` privilegije. Uvoz pukne sa greškom **1419**.

Rola ima task koji tu opciju pokušava da uključi kroz `SET GLOBAL`, ali **taj task ne može da uspe**: bazi pristupa kao korisnik `zabbix`, koji ima privilegije samo nad `zabbix.*`, a za promenu globalne promenljive treba `SYSTEM_VARIABLES_ADMIN`. Uz `failed_when: false` greška prolazi nezapaženo i task prijavljuje `changed`, pa deluje kao da je odradio posao.

Na hostu baze, pre pokretanja role:

```bash
sudo mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"
```

Provera:

```bash
sudo mysql -e "SELECT @@log_bin, @@log_bin_trust_function_creators;"
```

Ako je prva vrednost `0`, binarni log je isključen i opcija ti uopšte ne treba.

> `SET GLOBAL` važi **samo do restarta baze**. Opcija je potrebna i pri svakoj kasnijoj nadogradnji Zabbix verzije, jer i nadogradnja šeme kreira funkcije — zapamti da je pred nadogradnju ponovo uključiš. Za trajno rešenje dodaj liniju u konfiguraciju baze na hostu baze:
>
> ```ini
> # /etc/mysql/mysql.conf.d/zz-zabbix.cnf, sekcija [mysqld]
> log_bin_trust_function_creators = 1
> ```
>
> Cena je bezbednosna: svaki korisnik sa `CREATE ROUTINE` privilegijom može kreirati funkciju koja se upisuje u binarni log, što u replikaciji može razići podatke između čvorova. Na bazi namenjenoj isključivo Zabbix-u rizik je zanemarljiv.

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
| `role_zabbix_server_db_host` | `localhost` | Adresa baze. Za udaljenu bazu IP, ne `localhost`. |
| `role_zabbix_server_db_port` | `3306` | Port. Piše se u konfiguraciju samo kada `db_host` nije `localhost`. |
| `role_zabbix_server_db_name` | `zabbix` | Ime baze. |
| `role_zabbix_server_db_user` | `zabbix` | Korisnik. |
| `role_zabbix_server_db_password` | `""` | **Obavezno.** Ide u vault. |
| `role_zabbix_server_db_socket` | `""` | Putanja socket fajla. Samo za lokalnu bazu. |
| `role_zabbix_server_db_import` | `true` | Uvozi šemu pri prvoj primeni. |
| `role_zabbix_server_db_set_log_bin_trust` | `true` | Pokušava `SET GLOBAL`. **Ne uspeva** bez `SYSTEM_VARIABLES_ADMIN` — vidi sekciju o ručnim koracima. |

### Mreža i logovanje

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_listen_port` | `10051` | Port servera. |
| `role_zabbix_server_listen_ip` | `""` | Prazno = sve adrese. |
| `role_zabbix_server_stats_allowed_ip` | `127.0.0.1` | Ko sme čitati interne statistike. |
| `role_zabbix_server_logfile` | `/var/log/zabbix/zabbix_server.log` | Log fajl. |
| `role_zabbix_server_logfile_size` | `10` | MB. |
| `role_zabbix_server_debug_level` | `3` | 0–5. Nivoi 4 i 5 brzo pune disk. |
| `role_zabbix_server_log_slow_queries` | `3000` | Milisekunde. Nula isključuje. |

### Procesi

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_start_pollers` | `5` | Aktivne provere. |
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
role_zabbix_server_db_host: localhost
role_zabbix_server_db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...
```

### Baza na zasebnom hostu

Na hostu servera:

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_host: "10.0.0.21"
role_zabbix_server_db_port: 3306
role_zabbix_server_db_socket: ""
role_zabbix_server_db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...
```

Na hostu baze:

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_bind_address: "0.0.0.0"
role_zabbix_db_user_host: "10.0.0.50"

role_firewall_rules:
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> baza" }
```

Uz to obavezno prođi kroz sva četiri koraka iz sekcije **Baza na drugom hostu**, naročito četvrti.

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

**Prekinut uvoz rola ne prepoznaje.** Tabela `dbversion` se kreira tek pri kraju skripte. Ako uvoz pukne na pola, u bazi ostaje 150–200 tabela, ali provere nema, pa rola pri sledećem pokretanju pokušava ponovo i pada na prvom `CREATE TABLE` za već postojeću tabelu. Jedini ispravan oporavak je brisanje baze — vidi rešavanje problema.

**Lozinka ide kroz promenljivu okruženja.** Taskovi koriste `MYSQL_PWD` umesto `-p` argumenta, jer su argumenti komande vidljivi svakome ko pokrene `ps` na hostu tokom izvršavanja. Svi taskovi koji dodiruju lozinku imaju `no_log: true`.

**`no_log` sakriva i poruke o grešci.** Kada uvoz šeme pukne, u izlazu playbook-a piše samo `censored`. To je cena zaštite lozinke — pravu grešku moraš izvući ručnim pokretanjem komande. Uputstvo je u rešavanju problema.

**`log_bin_trust_function_creators` rola ne postavlja stvarno.** Task postoji, ali ne može da uspe jer korisnik `zabbix` nema potrebnu privilegiju. Opciju uključi ručno na hostu baze — vidi sekciju o ručnim koracima.

**PostgreSQL nije automatizovan.** Rola instalira ispravan paket i konfiguriše vezu, ali uvoz šeme za `pgsql` ostaje ručan — ispisuje tačnu komandu u izlazu. Razlog je što PostgreSQL traži drugačiji tok autentikacije (`peer` naspram lozinke) koji zavisi od `pg_hba.conf`, a to je konfiguracija koju ova rola ne kontroliše.

**Konfiguracioni fajl sadrži lozinku**, pa ima dozvole `0640` i grupu `zabbix`. Task koji ga upisuje ima `no_log: true`, što znači da `--diff` neće prikazati razliku — to je cena zaštite lozinke.

**Rola ne otvara port.** Agenti se javljaju na 10051; to pravilo pripada roli `firewall`.

**Prvi start može potrajati.** Posle uvoza šeme Zabbix server pri prvom pokretanju radi dodatne provere baze. Ako `systemctl status` pokaže da servis radi a frontend prijavljuje da server nije dostupan, sačekaj minut pa proveri log.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servis, osim kada se paket ili konfiguracija zaista promene. Izuzetak su taskovi oko `log_bin_trust_function_creators`, koji imaju `changed_when: true` i uvek prijavljuju izmenu.

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

Kada je baza na drugom hostu, dodatno:

```bash
# Da li baza slusa na mrezi — na hostu BAZE
ss -tln | grep 3306

# Da li server dopire do baze — na hostu SERVERA
mysql -h 10.0.0.21 -u zabbix -p zabbix -e "SELECT 1;"

# Stanje binarnog loga — na hostu BAZE
sudo mysql -e "SELECT @@log_bin, @@log_bin_trust_function_creators;"

# Kolacija baze
sudo mysql -e "SELECT default_character_set_name, default_collation_name
               FROM information_schema.schemata WHERE schema_name='zabbix';"
```

---

## Rešavanje problema

### Uvoz šeme pukne, a izlaz je `censored`

`no_log: true` sakriva poruku. Pokreni uvoz ručno, sa hosta servera:

```bash
ls /usr/share/zabbix-sql-scripts/mysql/

zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz \
  | MYSQL_PWD='lozinka' mysql -h 10.0.0.21 -u zabbix zabbix
```

Ako je skripta nekompresovana, izostavi `zcat` i koristi `< server.sql`.

### `ERROR 1419: You do not have the SUPER privilege`

`log_bin_trust_function_creators` nije uključen. Na hostu baze:

```bash
sudo mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"
```

pa ponovi. Task u roli koji to naizgled radi ne uspeva — vidi sekciju o ručnim koracima.

### `ERROR 1050: Table already exists`

Prethodni uvoz je prekinut na pola. Broj tabela pokazuje stanje:

```bash
sudo mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix';"
sudo mysql -e "SELECT * FROM zabbix.dbversion;"
```

Ako `dbversion` ne postoji a tabela ima, baza je neupotrebljiva. Na hostu baze:

```bash
sudo mysql -e "DROP DATABASE zabbix;"
```

Zatim pusti prvo `zabbix_db` pa `zabbix_server` — prva će kreirati praznu bazu sa ispravnom kolacijom.

Korisnik preživljava `DROP DATABASE`, ali gubi privilegije nad obrisanom bazom; rola ih vraća.

### `ERROR 2003 (HY000): Can't connect ... (111)`

Greška 111 je *connection refused* — paket je stigao i odbijen, znači niko ne sluša na toj adresi. Da UFW blokira, veza bi visila do isteka vremena, ne pukla odmah.

Skoro uvek znači da baza sluša samo na `127.0.0.1`. Proveri `bind-address` i zamku sa imenom konfiguracionog fajla iz sekcije o ručnim koracima.

Greška `2005` umesto `2003` znači da se ime hosta ne razrešava — problem je u DNS-u ili `/etc/hosts`.

### `ERROR 1045: Access denied for user 'zabbix'`

Tri moguća uzroka:

Lozinke se razilaze između role `zabbix_db` i `zabbix_server`. Definiši je jednom u `host_vars` pa referenciraj iz obe.

Korisnik ne sme sa te adrese. Na hostu baze:

```bash
sudo mysql -e "SELECT user, host FROM mysql.user WHERE user='zabbix';"
```

Vrednost u koloni `host` mora pokrivati IP sa koje server dolazi — proveri je sa `ip -4 addr show` na hostu servera.

Korisnik uopšte ne postoji, jer je rola `zabbix_db` pukla ranije u toku i nije stigla do kreiranja korisnika. Taskovi idu redom: provere → instalacija → servis → konfiguracija → baza → korisnik, i prekid na bilo kom mestu ostavlja sve posle njega neurađeno.

### Frontend prijavljuje pogrešnu kolaciju

Baza je kreirana sa `utf8mb4_0900_ai_ci` umesto `utf8mb4_bin`. To se dešava kada je baza napravljena ručno ili pre nego što je konfiguracija role počela da važi. Jedino rešenje je brisanje baze i ponovni uvoz — konverzija postojeće šeme nije pouzdana.

### Servis se pokreće pa odmah gasi

Skoro uvek greška u konfiguraciji ili nedostupna baza. Log je merodavan:

```bash
journalctl -u zabbix-server -n 50
```
