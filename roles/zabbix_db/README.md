# Rola: zabbix_db

Instalira MySQL, priprema bazu za Zabbix server, **uvozi šemu** i kreira naloge.

> **Rola nepovratno menja bazu.** Uvoz šeme je jednokratna operacija. Rola proverava da li šema već postoji i preskače uvoz ako jeste, ali prvi uvoz nad pogrešnom bazom se ne može poništiti.

---

## Šta se promenilo u odnosu na prethodnu verziju

| Ranije | Sada | Zašto |
|---|---|---|
| `role_zabbix_db_engine: mysql\|mariadb` | uklonjeno, samo MySQL | Jedan kod je pokrivao oba samo prividno — imena paketa, foldera i ponašanje oko kolacija se dovoljno razlikuju. |
| Šemu uvozi rola `zabbix_server` | šemu uvozi **ova** rola | Uvoz kao korisnik `zabbix` nije mogao da uspe. Detalji ispod. |
| `role_zabbix_db_user` | `role_zabbix_db_server_user` | Simetrija sa nalogom frontenda. |
| `role_zabbix_db_server_user_hosts` | `role_zabbix_db_server_hosts` | Kraće, bez ponavljanja reči `user`. |
| `role_zabbix_db_frontend_user_hosts` | `role_zabbix_db_frontend_hosts` | Isto. |
| `role_zabbix_db_user_host` (jedna vrednost) | uklonjeno | Postojalo je samo kao zaostavština; `role_zabbix_db_server_hosts` sada podrazumevano ima `localhost`. |
| Lozinke kroz `!vault` | obične promenljive | Lozinke idu u `host_vars` na kontrolnom čvoru, van git-a. |
| `templates/99-zabbix.cnf.j2` | `templates/zz-zabbix.cnf.j2` | Ime sa ciframa se učitava **pre** `mysqld.cnf` i biva pregaženo. |

### Šta uraditi posle nadogradnje role

1. Obriši `roles/zabbix_db/templates/99-zabbix.cnf.j2` iz repozitorijuma.
2. Preimenuj varijable u `host_vars` i `group_vars/all.yml` prema tabeli iznad.
3. Isključi uvoz u roli `zabbix_server`, da dve role ne rade isti posao:
```yaml
   # host_vars/srv-mon-01.yml
   role_zabbix_server_db_import: false
```
4. Na hostovima gde je stara rola već radila, obriši zaostali fajl:
```bash
   sudo rm -f /etc/mysql/mysql.conf.d/99-zabbix.cnf
   sudo systemctl restart mysql
```

---

## Zašto je uvoz šeme prešao ovde

Zabbix šema sadrži `CREATE FUNCTION` naredbe. MySQL 8.0 sa uključenim binarnim logom — što je podrazumevano stanje — odbija kreiranje funkcija od korisnika bez `SUPER` privilegije, sa greškom **1419**. Zaobilaznica je globalna opcija `log_bin_trust_function_creators`, a za njenu izmenu treba `SYSTEM_VARIABLES_ADMIN`.

Rola `zabbix_server` je bazi pristupala kao korisnik `zabbix`, koji ima privilegije samo nad `zabbix.*`. Task koji je opciju pokušavao da uključi nije mogao da uspe, a uz `failed_when: false` je greška prolazila nezapaženo — task je prijavljivao `changed` i delovao je kao da je odradio posao.

Ova rola bazi pristupa **lokalno, kao root kroz unix socket**. Root na Ubuntu koristi `auth_socket` dodatak: lozinka nije potrebna, privilegija je puna, opcija se uključuje pre uvoza i vraća na zatečenu vrednost posle.

Sporedna korist: pošto lozinka nije u igri, task uvoza nema `no_log: true`, pa se prava poruka o grešci vidi u ispisu umesto reči `censored`.

**Cena:** rola mora raditi **na hostu baze**. Ako je baza na zasebnom serveru, taj server ide u grupu `[deploy_zabbix_db]`.

---

## Podela posla

```text
zabbix_db      →  MySQL, prazna baza, UVOZ ŠEME, nalozi
zabbix_server  →  instalira i konfiguriše servis
zabbix_web     →  frontend
```

---

## Kritično: kolacija

Zabbix zahteva `utf8mb4` sa **`utf8mb4_bin`** kolacijom.

Ovo je najčešća greška pri ručnom postavljanju. Sa podrazumevanom `utf8mb4_0900_ai_ci` uvoz šeme uredno prođe, servis se pokrene, a frontend tek kasnije prijavi grešku — do tada već imaš podatke u bazi.

Rola proverava dvaput: podešene vrednosti pre bilo čega, i **stvarno stanje baze** iz `information_schema` pre uvoza. Druga provera hvata i bazu koju je neko kreirao ručno.

---

## Preduslovi

| Zahtev | Razlog |
|---|---|
| Kolekcija `community.mysql` | moduli `mysql_db`, `mysql_user`, `mysql_query`, `mysql_variables` |
| `python3-pymysql` na ciljnom hostu | rola ga sama instalira |
| Zabbix repozitorijum | paket `zabbix-sql-scripts` |
| Debian ili Ubuntu | rola prekida rad nad ostalim distribucijama |
| Rola radi na hostu baze | uvoz šeme ide kroz lokalni unix socket |

```bash
ansible-galaxy collection install community.mysql
```

U `playbook.yml` grupa `apply_repos` mora ići **pre** `deploy_zabbix_db`, inače paket `zabbix-sql-scripts` nije dostupan.

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

Lozinka mora biti **ista** u ovoj roli i u `zabbix_server`. Definiši je jednom:

```yaml
# host_vars/srv-mon-01.yml
_zabbix_db_pass: "izaberi-dugacku-lozinku"

role_zabbix_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
```

`host_vars` živi u `/opt/ansible/production/`, van git repozitorijuma, pa lozinka nikada ne ulazi u istoriju verzija. Postavi dozvole:

```bash
chmod 600 /opt/ansible/production/inventory/host_vars/srv-mon-01.yml
```

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
| `role_zabbix_db_schema_import` | `true` | Uvozi šemu ako tabela `dbversion` ne postoji. |
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
| `role_zabbix_db_innodb_buffer_pool_size` | `1G` | Najvažnije podešavanje. |
| `role_zabbix_db_innodb_buffer_pool_instances` | `1` | Jedna po gigabajtu bafera. |
| `role_zabbix_db_innodb_log_file_size` | `256M` | Veće = brži upis, sporiji oporavak. |
| `role_zabbix_db_innodb_flush_log_at_trx_commit` | `2` | `1` sigurnije, `2` brže. |
| `role_zabbix_db_max_connections` | `200` | Mora pokriti sve Zabbix procese. |
| `role_zabbix_db_max_allowed_packet` | `64M` | Ispod 32M uvoz šeme može pući. |
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
_zabbix_db_pass: "izaberi-dugacku-lozinku"

role_zabbix_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_server_db_import: false
```

Ništa drugo nije potrebno — podrazumevani `bind-address` i `localhost` su tačni.

### Baza na zasebnom hostu

Na hostu baze — tu se uvozi i šema, pa host mora imati Zabbix repozitorijum:

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_bind_address: "0.0.0.0"

role_zabbix_db_server_hosts:
  - "10.0.0.50"

role_zabbix_db_password: "izaberi-dugacku-lozinku"

role_firewall_rules:
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> baza" }
```

```ini
# hosts.ini
[apply_repos]
srv-db-01
srv-mon-01

[deploy_zabbix_db]
srv-db-01
```

Na hostu servera:

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_host: "10.0.0.21"
role_zabbix_server_db_password: "izaberi-dugacku-lozinku"
role_zabbix_server_db_import: false
```

> `bind-address: 0.0.0.0` znači da baza sluša na svim interfejsima. Pravilo zaštitnog zida nije preporuka nego uslov.
>
> `role_zabbix_server_db_host` mora biti IP ili ime hosta, **nikada `localhost`** — MySQL klijent `localhost` tumači kao unix socket i ignoriše `DBPort`.

### Zaseban nalog za frontend

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_frontend_enabled: true
role_zabbix_db_frontend_password: "druga-lozinka"
role_zabbix_db_frontend_hosts:
  - "10.0.0.60"
```

```yaml
# host_vars/srv-web-01.yml
role_zabbix_web_db_user: zabbix_web
role_zabbix_web_db_password: "druga-lozinka"
```

### Veće okruženje

Server sa 16 GB RAM-a, namenjen samo bazi:

```yaml
role_zabbix_db_innodb_buffer_pool_size: 10G
role_zabbix_db_innodb_buffer_pool_instances: 10
role_zabbix_db_innodb_log_file_size: 1G
role_zabbix_db_max_connections: 500
```

Uskladi `max_connections` sa Zabbix procesima — zbir svih `Start*` vrednosti plus rezerva za frontend.

---

## Napomene

**Uvoz se dešava samo jednom.** Provera je pitanje da li postoji tabela `dbversion`.

**Prekinut uvoz rola ne prepoznaje.** `dbversion` se kreira tek pri kraju skripte. Ako uvoz pukne na pola, u bazi ostaje 150–200 tabela, ali provere nema, pa rola pri sledećem pokretanju pokušava ponovo i pada na prvom `CREATE TABLE` za već postojeću tabelu. Jedini ispravan oporavak je brisanje baze.

**Verzija šeme mora odgovarati verziji servera.** Ako je `role_zabbix_server_version` zakovana, zakuj i `role_zabbix_db_sql_scripts_version` na istu vrednost. Neusklađenost se vidi tek kada server pri startu odbije da radi sa bazom pogrešne verzije.

**`log_bin_trust_function_creators` se vraća na zatečenu vrednost**, ne bezuslovno na nulu. Ako si opciju trajno uključio u konfiguraciji baze, rola je neće ugasiti.

**Rola ne briše naloge sa drugih adresa.** Ako `role_zabbix_db_server_hosts` skratiš, stari nalozi ostaju. Automatsko brisanje bi moglo prekinuti vezu servera koji trenutno radi. Ukloni ih ručno.

**`--check` na svežem hostu ne radi.** Provere kolacije i šeme čitaju iz baze koja u tom trenutku još ne postoji. To je inherentno, ne greška u roli.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje bazu, osim kada se konfiguracija zaista promeni. Izuzetak je task uvoza šeme, koji ima `changed_when: true` — ali se izvršava samo kada šeme nema.

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
    └── zz-zabbix.cnf.j2
```

---

## Provera

```bash
# Primena
./apply.sh --limit srv-mon-01

# Da li baza radi
ansible srv-mon-01 -m command -a "systemctl status mysql"

# Kolacija baze
ansible srv-mon-01 -m shell -a \
  "mysql -e \"SELECT default_character_set_name, default_collation_name \
   FROM information_schema.schemata WHERE schema_name='zabbix';\"" --become

# Da li je šema uvezena i koja je verzija
ansible srv-mon-01 -m shell -a "mysql -e 'SELECT * FROM zabbix.dbversion;'" --become

# Broj tabela — očekuje se preko 170 za Zabbix 7.0
ansible srv-mon-01 -m shell -a \
  "mysql -e \"SELECT COUNT(*) FROM information_schema.tables \
   WHERE table_schema='zabbix';\"" --become

# Nalozi
ansible srv-mon-01 -m shell -a \
  "mysql -e \"SELECT user, host FROM mysql.user WHERE user LIKE 'zabbix%';\"" --become

# Šta baza stvarno vidi kao bind-address
ansible srv-mon-01 -m shell -a \
  "mysqld --verbose --help 2>/dev/null | grep -m1 '^bind-address'" --become

# Da li sluša na mreži
ansible srv-mon-01 -m command -a "ss -tln sport = :3306"
```

---

## Rešavanje problema

### `Instalacija paketa zabbix-sql-scripts nije uspela`

Zabbix repozitorijum nije dodat na host baze. Host mora biti i u grupi `[apply_repos]`, a `apply_repos` mora ići pre `deploy_zabbix_db`:

```bash
apt-cache policy zabbix-sql-scripts
```

### `ERROR 1419: You do not have the SUPER privilege`

Ne bi trebalo da se pojavi — uvoz ide kao root. Ako se ipak javi, znači da si isključio `role_zabbix_db_log_bin_trust`, ili da baza nije lokalna. Proveri:

```bash
sudo mysql -e "SELECT @@log_bin, @@log_bin_trust_function_creators;"
```

Ako je prva vrednost `0`, binarni log je isključen i opcija ti uopšte ne treba.

### `ERROR 1050: Table already exists`

Prethodni uvoz je prekinut na pola:

```bash
sudo mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix';"
sudo mysql -e "SELECT * FROM zabbix.dbversion;"
```

Ako `dbversion` ne postoji a tabela ima, baza je neupotrebljiva:

```bash
sudo mysql -e "DROP DATABASE zabbix;"
```

Zatim pusti rolu ponovo. Nalozi preživljavaju `DROP DATABASE`, ali gube privilegije nad obrisanom bazom; rola ih vraća.

### `MySQL server has gone away` tokom uvoza

`max_allowed_packet` je premali. Podrazumevanih `64M` je dovoljno; ako si vrednost smanjio, vrati je.

### `Baza postoji, ali ima utf8mb4_0900_ai_ci`

Baza je kreirana ručno ili starijom verzijom role, pre nego što je konfiguracija počela da važi. Rola prekida rad **pre** uvoza, što je namerno — sa pogrešnom kolacijom uvoz prolazi, a greška se pojavljuje tek u frontendu.

Konverzija postojeće šeme nije pouzdana. Ako u bazi nema podataka do kojih ti je stalo:

```bash
sudo mysql -e "DROP DATABASE zabbix;"
```

### `ERROR 1045: Access denied for user 'zabbix'` sa hosta servera

Tri moguća uzroka:

Lozinke se razilaze između `role_zabbix_db_password` i `role_zabbix_server_db_password`. Definiši ih preko jedne promenljive.

Nalog ne sme sa te adrese:

```bash
sudo mysql -e "SELECT user, host FROM mysql.user WHERE user='zabbix';"
```

Vrednost u koloni `host` mora pokrivati IP sa koje server dolazi — proveri je sa `ip -4 addr show` na hostu servera.

Nalog uopšte ne postoji, jer je rola pukla ranije u toku. Taskovi idu redom: provere → instalacija → servis → konfiguracija → baza → šema → nalozi. Prekid na bilo kom mestu ostavlja sve posle njega neurađeno.

### `ERROR 2003 (HY000): Can't connect ... (111)`

Greška 111 je *connection refused* — paket je stigao i odbijen, znači niko ne sluša na toj adresi. Da UFW blokira, veza bi visila do isteka vremena, ne pukla odmah.

Skoro uvek znači da baza sluša samo na `127.0.0.1`. Proveri šta baza stvarno vidi:

```bash
sudo mysqld --verbose --help 2>/dev/null | grep -m1 '^bind-address'
```

Ako je vrednost `127.0.0.1` a `zz-zabbix.cnf` kaže drugačije, u folderu je verovatno zaostao `99-zabbix.cnf` iz stare verzije role — obriši ga.
