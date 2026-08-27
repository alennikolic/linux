<!-- roles/zabbix_server/README.md -->

# Rola: `zabbix_server`

Instalira i konfiguriše Zabbix server na Debian/Ubuntu sistemima.
Konfiguracija se upisuje kao **drop-in fajl** u `/etc/zabbix/zabbix_server.d/`;
glavni `zabbix_server.conf` ostaje fabrički.

Rola **bazu ne dira** — ne kreira je, ne uvozi šemu, ne menja privilegije.
Samo se na nju povezuje.

---

## Podela posla

```text
zabbix_db      →  MySQL, baza, šema, nalozi   (na hostu baze)
zabbix_server  →  instalira i konfiguriše servis
zabbix_web     →  frontend
```

Uvoz šeme je posao role `zabbix_db`, jer zahteva root pristup bazi kroz
lokalni unix socket. Nalog `zabbix` nema privilegije potrebne za
`CREATE FUNCTION` na MySQL-u sa uključenim binarnim logom.

---

## Zašto drop-in

`zabbix_server.conf` ima preko hiljadu linija i dpkg ga tretira kao
*conffile*. Rola koja ga prepisuje u celosti:

- pravi konflikt pri svakoj nadogradnji paketa, sa razlikom od stotina linija;
- mora se dopunjavati za svaki parametar koji Zabbix uvede u novom izdanju
  (`StartBrowserPollers` u 7.0, `StartHANodes`…), inače ti parametri nikada
  ne stignu na sistem.

Drop-in rešava oboje. Cena je jedna linija u glavnom fajlu.

### Include linija

Za razliku od agenta, paket servera **nema aktivnu `Include` direktivu** — sve
su zakomentarisane, i to sa upstream putanjom `/usr/local/etc/`. Rola zato na
sam kraj fajla dodaje blok:

```text
# BEGIN UPRAVLJA ANSIBLE ROLA: zabbix_server
Include=/etc/zabbix/zabbix_server.d/*.conf
# END UPRAVLJA ANSIBLE ROLA: zabbix_server
```

Pozicija na kraju nije kozmetička: Zabbix obrađuje `Include` u trenutku kada
ga pročita, pa samo tako drop-in nadjačava vrednosti iz glavnog fajla.

---

## Preduslovi

| Preduslov | Ko ga rešava |
|---|---|
| Zabbix repozitorijum | rola `repos`, grupa `[apply_repos]` |
| Baza sa uvezenom šemom | rola `zabbix_db`, grupa `[deploy_zabbix_db]` |
| Port 10051 otvoren | rola `firewall`, grupa `[apply_firewall]` |

U `playbook.yml` redosled je `apply_repos` → `deploy_zabbix_db` →
`deploy_zabbix_server`.

> Rola `zabbix_db` pokriva samo **MySQL**. Uz
> `role_zabbix_server_db_backend: pgsql` bazu, šemu i naloge moraš pripremiti
> sam.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_server]
srv-mon-01
```

```yaml
# group_vars/deploy_zabbix_server.yml
role_zabbix_server_enabled: true
```

---

## Obavezna konfiguracija

Lozinka baze je jedina obavezna vrednost i mora biti **ista** kao
`role_zabbix_db_password` na hostu baze:

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_password: "izaberi-dugacku-lozinku"
```

`host_vars` živi u `/opt/ansible/production/`, van git repozitorijuma.
Postavi dozvole `0600`.

---

## Varijable

### Aktivacija i paket

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_enabled` | `false` | Prekidač role |
| `role_zabbix_server_db_backend` | `mysql` | `mysql` ili `pgsql`; određuje ime paketa |
| `role_zabbix_server_version` | `""` | Zakovana verzija; prazno = najnovija |

### Veza sa bazom

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_db_host` | `localhost` | IP ili ime hosta; prazno = lokalni socket |
| `role_zabbix_server_db_port` | `3306` | Piše se samo kada host nije `localhost` |
| `role_zabbix_server_db_name` | `zabbix` | Ime baze |
| `role_zabbix_server_db_user` | `zabbix` | Nalog |
| `role_zabbix_server_db_password` | `""` | **Obavezno** |
| `role_zabbix_server_db_socket` | `""` | Samo uz lokalnu bazu |

### Konfiguracija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_config` | `{}` | Slobodan rečnik svih ostalih parametara |
| `role_zabbix_server_extra_config` | `""` | Doslovan tekst na kraju fajla |

### Drop-in mehanizam

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_include_dir` | `/etc/zabbix/zabbix_server.d` | Direktorijum drop-ina |
| `role_zabbix_server_dropin_name` | `zz-ansible.conf` | Ime drop-in fajla |
| `role_zabbix_server_manage_include` | `true` | Rola sama dodaje `Include` liniju |

### Servis

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_server_service_enabled` | `true` | Servis omogućen pri podizanju |
| `role_zabbix_server_service_state` | `started` | Ciljno stanje servisa |

Ključevi `DBHost`, `DBName`, `DBUser`, `DBPassword`, `DBSocket`, `DBPort` i
`Include` su rezervisani i ne smeju se pojaviti u `role_zabbix_server_config`
— `assert` prekida izvršavanje.

---

## Primeri

Malo okruženje, baza lokalno — ništa osim lozinke:

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
```

Baza na drugom hostu:

```yaml
role_zabbix_server_db_host: "10.0.0.60"
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
```

Okruženje srednje veličine (do ~1000 hostova):

```yaml
role_zabbix_server_config:
  CacheSize: 128M
  HistoryCacheSize: 64M
  HistoryIndexCacheSize: 32M
  TrendCacheSize: 32M
  ValueCacheSize: 128M
  StartPollers: 20
  StartPollersUnreachable: 5
  StartTrappers: 10
  StartPreprocessors: 10
  StartPingers: 5
  Timeout: 10
  LogSlowQueries: 3000
```

Visoka dostupnost — svaki čvor dobija jedinstveno ime, svi dele istu bazu:

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_server_config:
  HANodeName: node-01
  NodeAddress: "10.0.0.50:10051"
```

Statistika dostupna frontendu i proxy-jima:

```yaml
role_zabbix_server_config:
  StatsAllowedIP: "127.0.0.1,10.0.0.0/8"
```

---

## Zamke

**Nadogradnja paketa može ukloniti `Include` liniju.** Ako pri `apt upgrade`
odabereš „install the package maintainer's version", blok sa `Include`
nestaje i cela konfiguracija prestaje da važi. Kod servera to nije tiho —
bez `DBPassword` servis ne startuje. Rola vraća liniju pri sledećem prolazu.
Preporuka: na upit odgovori `N` (zadrži postojeću verziju), pa pusti rolu.

**Broj procesa naspram `max_connections`.** Svaki poller, trapper i
preprocessor drži konekciju ka bazi. Zbir ne sme preći
`role_zabbix_db_max_connections` (podrazumevano 200), inače server pada uz
`Too many connections`.

**`localhost` ignoriše `DBPort`.** MySQL klijent to ime tumači kao unix
socket. Za bazu na drugom hostu obavezno upiši IP adresu.

**Boolean vrednosti.** `true`/`false` iz YAML-a Jinja ispisuje kao
`True`/`False`, što Zabbix ne razume. Koristi `0` i `1`.

**Sintaksna greška ruši servis.** Neispravan ili nečitljiv include fajl
sprečava pokretanje. Handler radi `restart`, ne `reload`, da bi to bilo odmah
vidljivo.

**Prelazak sa stare verzije role.** Serveri koji su već dobili potpuno
prepisan `zabbix_server.conf` neće biti vraćeni na fabrički automatski. Stare
vrednosti bi ostale u glavnom fajlu kao drugi izvor istine:

```bash
apt-get install --reinstall -o Dpkg::Options::="--force-confask,confnew" \
  zabbix-server-mysql
```

**Rola ne pravi rezervnu kopiju drop-ina.** Fajl sadrži lozinku u čitljivom
obliku; kopija u istom direktorijumu bila bi drugi primerak tajne. Izvor
istine su varijable u `host_vars`.

---

## Struktura

```text
roles/zabbix_server/
├── defaults/main.yml
├── handlers/main.yml
├── tasks/main.yml
├── templates/dropin.conf.j2
├── vars/main.yml
└── README.md
```

---

## Idempotentnost

Sve izmene idu kroz `apt`, `file`, `blockinfile`, `template` i `service`.
`grep` provera ima `changed_when: false`. Drugi prolaz bez izmene varijabli
ne prijavljuje nijednu promenu i ne pokreće handler.

---

## Provera

```bash
# Include linija na kraju glavnog fajla
tail -5 /etc/zabbix/zabbix_server.conf

# šta je rola upisala (sadrži lozinku)
sudo cat /etc/zabbix/zabbix_server.d/zz-ansible.conf

# stanje servisa i poslednje greške
systemctl status zabbix-server
journalctl -u zabbix-server -n 50 --no-pager
tail -50 /var/log/zabbix/zabbix_server.log

# da li sluša
ss -ltnp | grep 10051

# verzija i veza sa bazom u logu
grep -E 'Starting Zabbix Server|database' /var/log/zabbix/zabbix_server.log | tail
```

---

## Rešavanje problema

**Servis se ne pokreće posle prolaza role.** Pogledaj
`/var/log/zabbix/zabbix_server.log` — poruka navodi tačan parametar ili fajl.
Najčešće je greška u vrednosti iz `role_zabbix_server_config`.

**`cannot use database ... its "users" table is empty`.** Šema nije uvezena.
Host mora biti u grupi `[deploy_zabbix_db]`, a `deploy_zabbix_db` ide pre
`deploy_zabbix_server` u `playbook.yml`.

**`Access denied for user 'zabbix'`.** `role_zabbix_server_db_password` se ne
poklapa sa `role_zabbix_db_password` na hostu baze.

**Parametar iz drop-ina nema efekta.** Proveri da `Include` linija stoji na
kraju glavnog fajla, posle tog parametra:

```bash
grep -n '^Include' /etc/zabbix/zabbix_server.conf
wc -l /etc/zabbix/zabbix_server.conf
```

**`Too many connections`.** Zbir procesa iz `role_zabbix_server_config`
prelazi `max_connections` na bazi.
