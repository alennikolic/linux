# Rola: zabbix_proxy

Instalira i konfiguriše Zabbix proxy na Debian/Ubuntu sistemima.

Proxy prikuplja podatke sa hostova u svojoj mreži i prosleđuje ih Zabbix serveru. Koristi se za udaljene lokacije, mreže iza NAT-a i za rasterećenje servera.

---

## Razlika u odnosu na `zabbix_server`

**Proxy podrazumevano koristi SQLite** — lokalnu bazu koju sam kreira pri prvom pokretanju. Nije potrebna rola `zabbix_db`, nema uvoza šeme, nema lozinki.

To čini ovu rolu znatno jednostavnijom za primenu: dovoljno je zadati adresu servera.

MySQL backend postoji kao opcija za proxy koji opslužuje veliki broj hostova.

---

## Preduslovi

| Preduslov | Ko ga rešava |
|---|---|
| Zabbix repozitorijum | rola `repos`, grupa `[apply_repos]` |
| Mrežni pristup do servera | rola `firewall` |
| **Proxy dodat u Zabbix serveru** | ručno, kroz frontend |

> **Poslednja stavka nije opciona.** Proxy mora biti upisan u Zabbix serveru pod `Administration → Proxies`, sa **tačno istim imenom** kao `role_zabbix_proxy_hostname` i **istim režimom rada**. Bez toga server odbija podatke, a u logu proxy-ja se pojavljuje poruka o nepoznatom proxy-ju.
>
> To se može automatizovati kroz rolu `zabbix_provisioning`, koja radi preko Zabbix API-ja.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_proxy]
srv-proxy-ns-01
```

Grupi pripada `group_vars/deploy_zabbix_proxy.yml`, koji postavlja `role_zabbix_proxy_enabled: true`.

---

## Obavezna konfiguracija

```yaml
# host_vars/srv-proxy-ns-01.yml
role_zabbix_proxy_server: "10.0.0.50"
```

To je sve za osnovnu postavku sa SQLite bazom. Ime proxy-ja se izvodi iz `inventory_hostname`.

---

## Režim rada

| Režim | Vrednost | Ko otvara vezu |
|---|---|---|
| Aktivan | `0` (podrazumevano) | Proxy zove server |
| Pasivan | `1` | Server zove proxy |

**Aktivan režim je uobičajen.** Proxy je često iza NAT-a ili zaštitnog zida udaljene lokacije, pa je jednostavnije da on otvara vezu ka serveru. Tada proxy ne prima dolazne veze i ne treba mu otvoren port.

**Pasivan režim** koristi kada server mora da kontroliše trenutak komunikacije. Tada proxy sluša na portu 10051 i server mora moći da dođe do njega.

> Režim se mora poklapati sa podešavanjem u Zabbix serveru. Neusklađen režim znači da komunikacije nema — **bez jasne greške**, samo tišina.

---

## Varijable

### Aktivacija i backend

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_proxy_db_backend` | `sqlite3` | `sqlite3`, `mysql`, `pgsql`. |
| `role_zabbix_proxy_version` | `""` | Zakovana verzija. Prazno = najnovija. |

### Identitet i veza

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_hostname` | `{{ inventory_hostname }}` | **Mora se poklapati sa imenom u serveru.** |
| `role_zabbix_proxy_server` | `""` | **Obavezno.** Adresa Zabbix servera. |
| `role_zabbix_proxy_mode` | `0` | `0` aktivan, `1` pasivan. |

### Mreža

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_listen_port` | `10051` | Port. Koristi se u pasivnom režimu. |
| `role_zabbix_proxy_listen_ip` | `""` | Prazno = sve adrese. |
| `role_zabbix_proxy_stats_allowed_ip` | `127.0.0.1` | Ko sme čitati interne statistike. |

### Baza

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_db_name` | `/var/lib/zabbix/zabbix_proxy.sqlite3` | Putanja fajla ili ime baze. |
| `role_zabbix_proxy_db_host` | `localhost` | Samo za mysql/pgsql. |
| `role_zabbix_proxy_db_port` | `3306` | Samo za mysql/pgsql. |
| `role_zabbix_proxy_db_user` | `zabbix` | Samo za mysql/pgsql. |
| `role_zabbix_proxy_db_password` | `""` | Obavezno za mysql/pgsql. |

### Čuvanje i slanje podataka

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_offline_buffer` | `1` | Sati čuvanja neposlatih podataka. |
| `role_zabbix_proxy_local_buffer` | `0` | Sati čuvanja posle slanja. |
| `role_zabbix_proxy_data_sender_frequency` | `1` | Sekunde između slanja. |
| `role_zabbix_proxy_config_frequency` | `10` | Sekunde između preuzimanja konfiguracije. |

### Logovanje i procesi

| Varijabla | Podrazumevano |
|---|---|
| `role_zabbix_proxy_logfile` | `/var/log/zabbix/zabbix_proxy.log` |
| `role_zabbix_proxy_logfile_size` | `10` |
| `role_zabbix_proxy_debug_level` | `3` |
| `role_zabbix_proxy_start_pollers` | `5` |
| `role_zabbix_proxy_start_pollers_unreachable` | `1` |
| `role_zabbix_proxy_start_trappers` | `5` |
| `role_zabbix_proxy_start_pingers` | `1` |
| `role_zabbix_proxy_start_discoverers` | `1` |
| `role_zabbix_proxy_start_http_pollers` | `1` |
| `role_zabbix_proxy_start_preprocessors` | `3` |

### Keševi i putanje

| Varijabla | Podrazumevano |
|---|---|
| `role_zabbix_proxy_cache_size` | `32M` |
| `role_zabbix_proxy_history_cache_size` | `16M` |
| `role_zabbix_proxy_history_index_cache_size` | `4M` |
| `role_zabbix_proxy_external_scripts` | `/usr/lib/zabbix/externalscripts` |
| `role_zabbix_proxy_fping_location` | `/usr/bin/fping` |
| `role_zabbix_proxy_timeout` | `4` |

### TLS

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_tls_connect` | `unencrypted` | `unencrypted`, `psk`, `cert`. |
| `role_zabbix_proxy_tls_accept` | `unencrypted` | Isto. |
| `role_zabbix_proxy_tls_psk_identity` | `""` | Identitet PSK ključa. |
| `role_zabbix_proxy_tls_psk` | `""` | **Tajna** — ide u vault. |
| `role_zabbix_proxy_tls_psk_file` | `/etc/zabbix/zabbix_proxy.psk` | Gde se upisuje. |

### Ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_proxy_extra_config` | `""` | Proizvoljne linije. |
| `role_zabbix_proxy_service_enabled` | `true` | Startuje uz sistem. |
| `role_zabbix_proxy_service_state` | `started` | `started`, `stopped`. |

---

## Primeri

### Osnovna postavka, aktivan režim

```yaml
# host_vars/srv-proxy-ns-01.yml
role_zabbix_proxy_server: "10.0.0.50"
```

Proxy sam otvara vezu ka serveru. Nije potrebno otvarati port na proxy strani.

Na serverskoj strani mora biti dozvoljen dolazni saobraćaj:

```yaml
# host_vars/srv-mon-01.yml
role_firewall_rules:
  - { rule: allow, port: 10051, proto: tcp, from: "10.10.0.0/16", comment: "Proxy -> server" }
```

### Pasivan režim

```yaml
# host_vars/srv-proxy-ns-01.yml
role_zabbix_proxy_server: "10.0.0.50"
role_zabbix_proxy_mode: 1

role_firewall_rules:
  - { rule: allow, port: 10051, proto: tcp, from: "10.0.0.50", comment: "Server -> proxy" }
```

Ne zaboravi da isti režim podesiš i u Zabbix serveru.

### Duži bafer za nepouzdanu vezu

```yaml
role_zabbix_proxy_offline_buffer: 24
```

Proxy tada čuva podatke 24 sata ako je veza ka serveru prekinuta. Korisno za udaljene lokacije sa nestabilnom vezom. Cena je prostor na disku i veće opterećenje SQLite baze.

### MySQL backend za veliki proxy

```yaml
role_zabbix_proxy_db_backend: mysql
role_zabbix_proxy_db_name: zabbix_proxy
role_zabbix_proxy_db_host: localhost
role_zabbix_proxy_db_user: zabbix
role_zabbix_proxy_db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...
```

> Uz MySQL backend rola **ne kreira bazu niti uvozi šemu**. To moraš uraditi ručno, ili rolom `zabbix_db` uz prilagođeno ime baze. Šema je u `/usr/share/zabbix-sql-scripts/mysql/proxy.sql.gz`.

### Šifrovana veza preko PSK

```bash
openssl rand -hex 32
ansible-vault encrypt_string '<psk_hex>' --name 'role_zabbix_proxy_tls_psk'
```

```yaml
role_zabbix_proxy_tls_connect: psk
role_zabbix_proxy_tls_accept: psk
role_zabbix_proxy_tls_psk_identity: "PSK-proxy-ns"
role_zabbix_proxy_tls_psk: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  38396264...
```

Isti identitet i ključ upiši i u Zabbix serveru, u podešavanjima proxy-ja.

### Agenti koji šalju podatke proxy-ju

Na hostovima iza proxy-ja, umesto adrese servera zadaj adresu proxy-ja:

```yaml
# group_vars/lokacija_ns.yml
role_zabbix_agent_server: "10.10.0.5"
role_zabbix_agent_server_active: "10.10.0.5"
```

---

## Napomene

**SQLite bazu proxy kreira sam.** Rola priprema samo folder sa vlasnikom `zabbix`. Fajl nastaje pri prvom pokretanju servisa i tada se u log upisuje poruka o kreiranju baze. Ako fajl obrišeš, proxy će ga napraviti ponovo — uz gubitak neposlatih podataka.

**Ime proxy-ja je kritično.** Mora se poklapati sa imenom u Zabbix serveru, karakter po karakter. Podrazumevana vrednost `{{ inventory_hostname }}` znači da je ime iz `hosts.ini` merodavno — upiši u server tačno to.

**Neusklađen režim ne prijavljuje grešku.** Ako je proxy aktivan a u serveru je upisan kao pasivan, podataka prosto nema. Proveri obe strane pre nego što tražiš uzrok drugde.

**`fping` se instalira zasebno.** Nije zavisnost Zabbix paketa, a bez njega ICMP provere ne rade.

**Proxy ne čuva istoriju.** Podaci se brišu čim ih server potvrdi, osim ako povećaš `role_zabbix_proxy_local_buffer`. Istorija živi na serveru.

**Konfiguracioni fajl može sadržati lozinku** (uz MySQL backend), pa ima dozvole `0640` i grupu `zabbix`. Task ima `no_log: true`, što znači da `--diff` neće prikazati razliku u tom fajlu.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servis, osim kada se paket ili konfiguracija zaista promene.

---

## Struktura

```text
roles/zabbix_proxy/
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
    └── zabbix_proxy.conf.j2
```

---

## Provera

```bash
# Bez izmena
./apply.sh --limit deploy_zabbix_proxy --check --diff

# Primena
./apply.sh --limit srv-proxy-ns-01

# Stanje servisa
ansible srv-proxy-ns-01 -m command -a "systemctl status zabbix-proxy"

# Log — trazi "Zabbix Proxy started"
ansible srv-proxy-ns-01 -m command -a "tail -30 /var/log/zabbix/zabbix_proxy.log"

# Da li je SQLite baza kreirana
ansible srv-proxy-ns-01 -m command -a "ls -lh /var/lib/zabbix/"

# Da li proxy slusa (pasivan rezim)
ansible srv-proxy-ns-01 -m command -a "ss -lntp sport = :10051"
```

U frontendu, pod `Administration → Proxies`, kolona `Last seen` pokazuje kada se proxy poslednji put javio. Ako stoji `Never`, komunikacija ne radi.

---

## Rešavanje problema

**`Proxy "ime" not found` u logu proxy-ja**

Proxy nije dodat u Zabbix serveru, ili se ime razlikuje. Uporedi `Hostname` iz konfiguracije sa imenom u frontendu.

**`Last seen: Never` u frontendu**

Najčešće neusklađen režim rada, ili zaštitni zid. Proveri:

```bash
# Sa proxy-ja, da li server odgovara (aktivan rezim)
nc -zv 10.0.0.50 10051
```

**Proxy radi ali hostovi nemaju podatke**

Hostovi u Zabbix-u moraju biti dodeljeni proxy-ju — u podešavanjima hosta, polje `Monitored by proxy`. Sama instalacija proxy-ja ne prebacuje hostove na njega.

**Baza raste bez kontrole**

`role_zabbix_proxy_offline_buffer` je previsok, a veza ka serveru prekinuta. Proveri da li server prima podatke; SQLite fajl će se smanjiti tek posle uspešnog slanja.
