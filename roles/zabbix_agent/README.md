<!-- roles/zabbix_agent/README.md -->

# Rola: `zabbix_agent`

Instalira Zabbix agenta (`zabbix-agent` ili `zabbix-agent2`) i upisuje
konfiguraciju kao **drop-in fajl** u include direktorijum koji paket već
predviđa. Podrazumevani `zabbix_agentd.conf` ostaje netaknut.

## Zašto drop-in

`/etc/zabbix/zabbix_agentd.conf` je dpkg *conffile*. Rola koja ga prepisuje u
celosti stvara dva problema:

- svaka nadogradnja paketa završava u konfliktu ili tiho zadržava našu
  verziju, pa nove opcije koje vendor doda nikada ne stignu na sistem;
- razlika između našeg i fabričkog fajla postaje neproverljiva.

Zabbix obrađuje `Include` direktivu u trenutku kada je pročita, a u paketima
ona stoji na kraju fajla. Posledica: parametar definisan u drop-in fajlu
nadjačava isti parametar iz podrazumevane konfiguracije. To je zvanično
podržan mehanizam, ne trik.

## Preduslovi

- Ubuntu 22.04+ ili Debian 11+
- Zabbix APT repozitorijum dodat — rola `repos`
- Bez dodatnih kolekcija (koriste se samo `ansible.builtin` moduli)

## Aktivacija

```ini
[deploy_zabbix_agent]
srv-web-01
srv-db-01
```

```yaml
# group_vars/deploy_zabbix_agent.yml
role_zabbix_agent_enabled: true
```

## Varijable

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_enabled` | `false` | Prekidač role |
| `role_zabbix_agent_variant` | `agent` | `agent` ili `agent2` |
| `role_zabbix_agent_package_state` | `present` | `present` ili `latest` |
| `role_zabbix_agent_server` | `""` | Adrese za pasivne provere |
| `role_zabbix_agent_server_active` | `""` | Adrese za aktivne provere |
| `role_zabbix_agent_server_allow_semicolon` | `false` | Dozvoljava `;` u `Server` |
| `role_zabbix_agent_hostname` | `{{ inventory_hostname }}` | Ime hosta u Zabbix-u |
| `role_zabbix_agent_config` | `{}` | Slobodan rečnik ostalih parametara |
| `role_zabbix_agent_extra_config` | `""` | Doslovan tekst na kraju fajla |
| `role_zabbix_agent_tls_psk` | `""` | PSK, heksadecimalno; prazno = bez TLS-a |
| `role_zabbix_agent_tls_psk_identity` | `PSK {{ inventory_hostname }}` | Identitet PSK-a |
| `role_zabbix_agent_tls_psk_file` | `/etc/zabbix/zabbix_agent.psk` | Putanja PSK fajla |
| `role_zabbix_agent_dropin_name` | `zz-ansible.conf` | Ime drop-in fajla |
| `role_zabbix_agent_include_dir` | `""` | Ručno zadata putanja; prazno = automatska detekcija |
| `role_zabbix_agent_include_strict` | `true` | Prekid ako u include direktorijumu ima rezervnih kopija |
| `role_zabbix_agent_service_enabled` | `true` | Servis omogućen pri podizanju sistema |
| `role_zabbix_agent_service_state` | `started` | Ciljno stanje servisa |

Ključevi `Server`, `ServerActive`, `Hostname` i `TLS*` su rezervisani i ne
smeju se pojaviti u `role_zabbix_agent_config` — `assert` prekida izvršavanje.

## Zadavanje adresa servera

`role_zabbix_agent_server` i `role_zabbix_agent_server_active` prihvataju tri
oblika zapisa:

| Zapis | Rezultat |
|---|---|
| `10.0.0.10` | `10.0.0.10` |
| `"10.0.0.10,10.0.0.11"` | prepisuje se doslovno |
| `[10.0.0.10, 10.0.0.11]` | `10.0.0.10,10.0.0.11` |
| `- [a, b]`<br>`- c` | `a;b,c` |

Ugnježdena lista se spaja tačkom-zarezom, spoljašnja zarezom.

### Zarez i tačka-zarez nisu isto

**`Server`** (pasivne provere) prima **isključivo zarez**. To je spisak adresa
sa kojih agent prihvata dolazne konekcije; tačka-zarez tu nije razdvajač, pa
bi cela niska bila protumačena kao jedna adresa i agent bi odbijao konekcije.
Isto važi i za HA klaster — svi čvorovi se navode razdvojeni zarezom.

Rola zato tačku-zarez u `Server` podrazumevano odbija. Prekidač
`role_zabbix_agent_server_allow_semicolon: true` isključuje tu proveru.

**`ServerActive`** (aktivne provere) razlikuje oba znaka:

- **`;`** — članovi jednog klastera ili proxy grupe. Agent u datom trenutku
  šalje podatke samo jednom od njih i sam prelazi na sledeći kad aktivni
  otkaže.
- **`,`** — nezavisni serveri ili klasteri. Agent šalje **svima**.

```text
ServerActive=zbx-a1;zbx-a2,zbx-b:20051
             └ jedan klaster ┘ └ nezavisan server ┘
```

### Format adrese

- port se odvaja dvotačkom: `zbx-a2:20051`
- IPv6 sa portom mora u uglaste zagrade: `[::1]:30051`; bez porta su zagrade
  opcione
- razmaci oko razdvajača su dozvoljeni, ali ih rola svejedno uklanja

## Primeri

Minimalno, aktivne i pasivne provere prema jednom serveru:

```yaml
role_zabbix_agent_enabled: true
role_zabbix_agent_server: 10.0.0.10
role_zabbix_agent_server_active: 10.0.0.10:10051
```

Dva nezavisna servera:

```yaml
role_zabbix_agent_server: [10.0.0.10, 10.0.0.11]
role_zabbix_agent_server_active: [10.0.0.10:10051, 10.0.0.11:10051]
```

HA klaster od dva čvora — za pasivne zarez, za aktivne tačka-zarez:

```yaml
role_zabbix_agent_server: [zbx-node1, zbx-node2]
role_zabbix_agent_server_active:
  - [zbx-node1, zbx-node2]
# Server=zbx-node1,zbx-node2
# ServerActive=zbx-node1;zbx-node2
```

Klaster plus nezavisan server sa izmenjenim portom:

```yaml
role_zabbix_agent_server: [zbx-node1, zbx-node2, zbx-solo]
role_zabbix_agent_server_active:
  - [zbx-node1, "zbx-node2:20051"]
  - zbx-solo
# ServerActive=zbx-node1;zbx-node2:20051,zbx-solo
```

Proxy grupa:

```yaml
role_zabbix_agent_server: [proxy1, proxy2, proxy3]
role_zabbix_agent_server_active:
  - [proxy1, proxy2, proxy3]
```

Dodatni parametri i korisničke provere:

```yaml
role_zabbix_agent_config:
  Timeout: 10
  RefreshActiveChecks: 60
  LogFileSize: 10
  UserParameter:
    - "mysql.ping,mysqladmin ping | grep -c alive"
    - "custom.disk[*],/usr/local/bin/disk.sh $1"
```

`agent2` sa parametrom dodatka:

```yaml
role_zabbix_agent_variant: agent2
role_zabbix_agent_config:
  Plugins.Uptime.Capacity: 1
```

## Zamke

**Tačka-zarez u `Server`.** Nije razdvajač. Agent ne prijavljuje jasnu grešku
— jednostavno odbija konekcije, a to se vidi tek kad server prijavi da host
nije dostupan.

**Proxy i server zajedno u `ServerActive`.** Ako je naveden proxy, server ili
klaster za taj proxy se ne navodi. Duplo prijavljivanje pravi konfuziju u
podacima.

**Rezervne kopije u include direktorijumu.** Ako `Include` pokazuje na go
direktorijum bez `*.conf` maske, Zabbix učitava *svaki* fajl u njemu.
Zaostali `zz-ansible.conf.dpkg-old` znači dupliran parametar i agenta koji se
ponaša nepredvidivo. Zato rola ne koristi `backup: true` za drop-in — jedini
izuzetak od konvencije projekta — i proverava direktorijum kada maske nema.

**Redosled učitavanja nije definisan.** Zabbix ne učitava include fajlove
abecedno i isti parametar ne sme biti u dva include fajla. Rola zato upisuje
tačno jedan fajl. Ako dodaješ svoje `.conf` fajlove ručno, ne ponavljaj u
njima parametre koje rola već ispisuje.

**Sintaksna greška ruši agenta.** Neispravan ili nečitljiv include fajl
sprečava pokretanje. Handler radi `restart`, a ne `reload`, da bi greška bila
odmah vidljiva.

**`Hostname` mora da se poklapa** sa imenom hosta u Zabbix-u. Stock
konfiguracija ima `Hostname=Zabbix server`, pa bi bez nadjačavanja svi hostovi
izveštavali pod istim imenom.

**Boolean vrednosti.** `true`/`false` iz YAML-a Jinja ispisuje kao
`True`/`False`, što Zabbix ne razume. Koristi `0` i `1`.

**Prelazak sa stare verzije role.** Serveri koji su već dobili potpuno
prepisan `zabbix_agentd.conf` neće biti vraćeni na fabrički automatski:

```bash
apt-get install --reinstall -o Dpkg::Options::="--force-confask,confnew" zabbix-agent
```

**`--check` na sistemu bez agenta.** Detekcija include putanje čita
instaliranu konfiguraciju, koja u probnom prolazu na svežem serveru još ne
postoji. Prvi prolaz mora biti pravi.

## Struktura

```text
roles/zabbix_agent/
├── defaults/main.yml
├── handlers/main.yml
├── tasks/main.yml
├── templates/dropin.conf.j2
├── vars/main.yml
└── README.md
```

## Idempotentnost

Sve izmene idu kroz `apt`, `template`, `copy`, `file` i `service`. `slurp` i
`find` su operacije čitanja. Drugi prolaz bez izmene varijabli ne prijavljuje
nijednu promenu i ne pokreće handler.

## Provera

```bash
# koji je include direktorijum otkriven
grep -n '^Include' /etc/zabbix/zabbix_agentd.conf

# šta je rola upisala
cat /etc/zabbix/zabbix_agentd.d/zz-ansible.conf

# zaostali fajlovi
ls -al /etc/zabbix/zabbix_agentd.d/

# da li se konfiguracija parsira (ispisuje podržane stavke)
zabbix_agentd -c /etc/zabbix/zabbix_agentd.conf -p | head

# stanje servisa i poslednje greške
systemctl status zabbix-agent
journalctl -u zabbix-agent -n 50 --no-pager

# provera sa Zabbix servera
zabbix_get -s 10.0.0.31 -k agent.ping
```

Bez primene role, samo za proveru kako će se adrese sklopiti:

```bash
ansible-playbook playbooks/playbook.yml --limit srv-web-01 --tags zabbix_agent \
  --check --diff
```

## Rešavanje problema

**Agent se ne pokreće posle prolaza role.** Skoro uvek sintaksna greška ili
neučitljiv fajl u include direktorijumu. `journalctl -u zabbix-agent -n 50`
navodi tačan fajl i liniju.

**Parametar iz drop-ina nema efekta.** Proveri da `Include` linija u glavnoj
konfiguraciji zaista stoji *posle* tog parametra. U paketima jeste, ali ako je
glavni fajl ručno menjan, redosled je mogao da se pomeri.

**Rola prekida sa „nije pronađena nijedna aktivna Include direktiva".**
Glavna konfiguracija je izmenjena ili paket nije standardan. Vrati fabrički
fajl, ili dodaj `Include` liniju ručno i postavi
`role_zabbix_agent_include_dir` na istu putanju.

**Aktivne provere ne stižu, pasivne rade.** `ServerActive` nije postavljen ili
se `Hostname` ne poklapa sa imenom hosta u Zabbix-u.

**Podaci stižu duplirano.** U `ServerActive` su čvorovi klastera razdvojeni
zarezom umesto tačkom-zarezom, pa agent izveštava svima umesto jednom.

**`zabbix_get` javlja da veza nije dozvoljena.** Adresa servera nije u
`Server`, ili UFW pravilo za port 10050 nedostaje — vidi rolu `firewall`.
