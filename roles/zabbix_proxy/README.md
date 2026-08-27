<!-- roles/zabbix_proxy/README.md -->

# Rola: `zabbix_proxy`

Instalira i konfiguriše Zabbix proxy sa **SQLite** bazom na Debian/Ubuntu
sistemima. Konfiguracija se upisuje kao **drop-in fajl** u
`/etc/zabbix/zabbix_proxy.d/`; glavni `zabbix_proxy.conf` ostaje fabrički.

Proxy prikuplja podatke sa hostova u svojoj mreži i prosleđuje ih Zabbix
serveru. Koristi se za udaljene lokacije, mreže iza NAT-a i za rasterećenje
servera.

---

## Samo SQLite

MySQL i PostgreSQL backend su namerno izbačeni. Tražili bi pripremljenu bazu,
uvoz šeme i lozinke — posao koji radi rola `zabbix_db` i koji za proxy retko
ima smisla.

SQLite bazu proxy kreira sam pri prvom pokretanju. Rola samo priprema folder
sa ispravnim vlasnikom. Nema šeme, nema lozinki, nema zavisnosti od druge
role.

Praktična granica je nekoliko stotina hostova po proxy-ju. Iznad toga upis u
SQLite postaje usko grlo — tada je ispravno rešenje **još jedan proxy**, ne
prelazak na MySQL.

---

## Zašto drop-in

`zabbix_proxy.conf` ima preko hiljadu linija i dpkg ga tretira kao *conffile*.
Rola koja ga prepisuje u celosti pravi konflikt pri svakoj nadogradnji paketa,
a parametri koje Zabbix uvede ili ukloni u novom izdanju nikada ne stignu na
sistem.

### Include linija

Kao i kod servera, paket proxy-ja **nema aktivnu `Include` direktivu** — sve su
zakomentarisane, sa upstream putanjom `/usr/local/etc/`. Rola zato na sam kraj
glavnog fajla dodaje blok:

```text
# BEGIN UPRAVLJA ANSIBLE ROLA: zabbix_proxy
Include=/etc/zabbix/zabbix_proxy.d/*.conf
# END UPRAVLJA ANSIBLE ROLA: zabbix_proxy
```

Pozicija na kraju nije kozmetička: Zabbix obrađuje `Include` u trenutku kada
ga pročita, pa samo tako drop-in nadjačava vrednosti iz glavnog fajla.

---

## Preduslovi

| Preduslov | Ko ga rešava |
|---|---|
| Zabbix repozitorijum | rola `repos`, grupa `[apply_repos]` |
| Mrežni pristup do servera | rola `firewall` |
| **Proxy dodat u Zabbix serveru** | ručno, kroz frontend |

> **Poslednja stavka nije opciona.** Proxy mora biti upisan u Zabbix serveru
> pod `Administration → Proxies`, sa **tačno istim imenom** kao
> `role_zabbix_proxy_hostname` i **istim režimom rada**. Bez toga server odbija
> podatke, a u logu proxy-ja se pojavljuje poruka o nepoznatom proxy-ju.
>
> To se može automatizovati kroz rolu `zabbix_provisioning`, koja radi preko
> Zabbix API-ja.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_proxy]
srv-proxy-ns-01
```

```yaml
# group_vars/deploy_zabbix_proxy.yml
role_zabbix_proxy_enabled: true
```

---

## Obavezna konfiguracija

```yaml
# host_vars/srv-proxy-ns-01.yml
role_zabbix_proxy_server: "10.0.0.50"
```

To je sve za osnovnu postavku. Ime proxy-ja se izvodi iz `inventory_hostname`.

---

## Režim rada

| Režim | Vrednost | Ko otvara vezu |
|---|---|---|
| Aktivan | `0` (podrazumevano) | Proxy zove server |
| Pasivan | `1` | Server zove proxy |

**Aktivan režim je uobičajen.** Proxy je često iza NAT-a ili zaštitnog zida
udaljene lokacije, pa je jednostavnije da on otvara vezu. Tada proxy ne prima
dolazne veze i ne treba mu otvoren port.

**Pasivan režim** koristi kada server mora da kontroliše trenutak
komunikacije. Tada proxy sluša na portu 10051 i server mora moći da dođe do
njega.

> Režim se mora poklapati sa podešavanjem u Zabbix serveru. Neusklađen režim
> znači da komunikacije nema — **bez jasne greške**, samo tišina.

---

## Varijable

### Aktivacija i paket

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_enabled` | `false` | Prekidač role |
| `role_zabbix_proxy_version` | `""` | Zakovana verzija; prazno = najnovija |

### Identitet i veza

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_hostname` | `{{ inventory_hostname }}` | **Mora se poklapati sa imenom u serveru** |
| `role_zabbix_proxy_server` | `""` | **Obavezno.** Adresa servera; string ili lista |
| `role_zabbix_proxy_mode` | `0` | `0` aktivan, `1` pasivan |

### Baza

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_db_name` | `/var/lib/zabbix/zabbix_proxy.sqlite3` | Puna putanja SQLite fajla |

### Konfiguracija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_config` | `{}` | Slobodan rečnik svih ostalih parametara |
| `role_zabbix_proxy_extra_config` | `""` | Doslovan tekst na kraju fajla |

### TLS

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_tls_psk` | `""` | PSK heksadecimalno; prazno = bez TLS-a |
| `role_zabbix_proxy_tls_psk_identity` | `PSK {{ inventory_hostname }}` | Identitet PSK-a |
| `role_zabbix_proxy_tls_psk_file` | `/etc/zabbix/zabbix_proxy.psk` | Putanja PSK fajla |

### Drop-in mehanizam

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_include_dir` | `/etc/zabbix/zabbix_proxy.d` | Direktorijum drop-ina |
| `role_zabbix_proxy_dropin_name` | `zz-ansible.conf` | Ime drop-in fajla |
| `role_zabbix_proxy_manage_include` | `true` | Rola sama dodaje `Include` liniju |

### Servis

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_service_enabled` | `true` | Servis omogućen pri podizanju |
| `role_zabbix_proxy_service_state` | `started` | Ciljno stanje servisa |

Ključevi `Hostname`, `Server`, `ProxyMode`, `DBName`, `TLS*` i `Include` su
rezervisani i ne smeju se pojaviti u `role_zabbix_proxy_config` — `assert`
prekida izvršavanje.

---

## Primeri

Minimalno, aktivni režim:

```yaml
role_zabbix_proxy_server: "10.0.0.50"
```

Pasivni režim, server sam zove proxy:

```yaml
role_zabbix_proxy_server: "10.0.0.50"
role_zabbix_proxy_mode: 1
role_zabbix_proxy_config:
  ListenPort: 10051
```

HA klaster servera — čvorovi se razdvajaju **tačkom-zarezom**:

```yaml
role_zabbix_proxy_server: "zbx-node1;zbx-node2"
```

Udaljena lokacija sa nepouzdanom vezom — duži bafer:

```yaml
role_zabbix_proxy_server: "10.0.0.50"
role_zabbix_proxy_config:
  ProxyOfflineBuffer: 24
  CacheSize: 64M
  HistoryCacheSize: 32M
  StartPollers: 15
  Timeout: 10
```

Šifrovana veza ka serveru:

```yaml
role_zabbix_proxy_server: "10.0.0.50"
role_zabbix_proxy_tls_psk: "{{ vault_proxy_psk }}"
role_zabbix_proxy_tls_psk_identity: "PSK srv-proxy-ns-01"
```

Isti identitet i ključ moraju biti upisani i u podešavanjima ovog proxy-ja u
Zabbix serveru.

---

## Zamke

**Proxy mora biti dodat u serveru.** Ime i režim moraju se poklapati tačno.
Neusklađenost ne daje jasnu grešku — podaci jednostavno ne stižu.

**Nadogradnja paketa može ukloniti `Include` liniju.** Ako pri `apt upgrade`
odabereš „install the package maintainer's version", blok sa `Include`
nestaje i konfiguracija prestaje da važi. Proxy tada startuje sa fabričkim
vrednostima (`Server=127.0.0.1`) i tiho ne radi ništa korisno. Preporuka: na
upit odgovori `N`, pa pusti rolu.

**Vlasništvo nad folderom SQLite baze.** Nije dovoljno da fajl bude upisiv —
SQLite pored baze pravi `-journal` i `-wal` fajlove, pa upis mora biti
dozvoljen nad folderom.

**Rola ne kreira SQLite fajl.** Prazan fajl bi proxy protumačio kao oštećenu
bazu. Fajl nastaje pri prvom pokretanju servisa, sa punom šemom.

**Parametri se menjaju između Zabbix izdanja.** Rečnik znači da rola ne mora
da zna koji parametar postoji u kojoj verziji — ali i da za ispravnost
odgovaraš ti. Neispravan parametar sprečava pokretanje; log kaže koji.

**Boolean vrednosti.** `true`/`false` iz YAML-a Jinja ispisuje kao
`True`/`False`, što Zabbix ne razume. Koristi `0` i `1`.

**Prelazak sa stare verzije role.** Proksiji koji su već dobili potpuno
prepisan `zabbix_proxy.conf` neće biti vraćeni na fabrički automatski:

```bash
apt-get install --reinstall -o Dpkg::Options::="--force-confask,confnew" \
  zabbix-proxy-sqlite3
```

Ako si ranije koristio MySQL backend, prelazak na SQLite znači i **novu praznu
bazu** — podaci koje proxy još nije poslao serveru se gube.

---

## Struktura

```text
roles/zabbix_proxy/
├── defaults/main.yml
├── handlers/main.yml
├── tasks/main.yml
├── templates/dropin.conf.j2
├── vars/main.yml
└── README.md
```

---

## Idempotentnost

Sve izmene idu kroz `apt`, `file`, `blockinfile`, `copy`, `template` i
`service`. `grep` provera ima `changed_when: false`. Drugi prolaz bez izmene
varijabli ne prijavljuje nijednu promenu i ne pokreće handler.

---

## Provera

```bash
# Include linija na kraju glavnog fajla
tail -5 /etc/zabbix/zabbix_proxy.conf

# šta je rola upisala
cat /etc/zabbix/zabbix_proxy.d/zz-ansible.conf

# SQLite baza — nastaje pri prvom pokretanju
ls -alh /var/lib/zabbix/

# stanje servisa i poslednje greške
systemctl status zabbix-proxy
tail -50 /var/log/zabbix/zabbix_proxy.log

# potvrda da server prihvata proxy
grep -Ei 'proxy|connect' /var/log/zabbix/zabbix_proxy.log | tail -20
```

Na strani servera, u logu, proxy koji nije registrovan javlja se kao odbijena
veza sa nepoznatim imenom.

---

## Rešavanje problema

**`cannot parse list of active checks` / podaci ne stižu.** Ime proxy-ja se ne
poklapa sa imenom u serveru, ili se režim rada razlikuje.

**Proxy startuje pa se odmah gasi.** Pogledaj
`/var/log/zabbix/zabbix_proxy.log` — najčešće je neispravan parametar iz
`role_zabbix_proxy_config` ili nedostupan folder SQLite baze.

**`database is locked` ili spor upis.** SQLite je dostigao granicu za broj
hostova koje proxy opslužuje. Podeli hostove na još jedan proxy.

**Konfiguracija se ne primenjuje.** Proveri da `Include` linija stoji na kraju
glavnog fajla:

```bash
grep -n '^Include' /etc/zabbix/zabbix_proxy.conf
wc -l /etc/zabbix/zabbix_proxy.conf
```

**Veza ka serveru odbijena uz PSK.** Identitet ili ključ se ne poklapaju sa
onim što je upisano u podešavanjima proxy-ja u Zabbix serveru.
