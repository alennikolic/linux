# Rola: timezone

Postavlja vremensku zonu sistema i konfiguriše sinhronizaciju vremena preko `chrony`-ja.

Rola radi tri stvari:

| Šta rola radi | Napomena |
|---|---|
| Postavlja vremensku zonu | uvek |
| Instaliranje `chrony`-ja i upis izvora | uvek, lista izvora je obavezna |
| Restart servisa koji keširaju `TZ` | samo ako je zona stvarno promenjena |

Nema izbora između `chrony`-ja i `systemd-timesyncd`-a i nema drop-in konfiguracije. Rola upisuje **ceo** `/etc/chrony/chrony.conf`, pa je spisak izvora tačno ono što je zadato — ništa se ne dodaje iz podrazumevane konfiguracije, iz `/etc/chrony/conf.d` ni iz DHCP-a.

---

## Preduslovi

Kolekcija `community.general` (modul `timezone`):

```bash
ansible-galaxy collection install community.general
```

Debian ili Ubuntu. Putanje i ime servisa se razlikuju na RHEL familiji, pa rola tamo prekida rad uz jasnu poruku.

Izlazni UDP port 123 ka NTP izvorima mora biti prohodan.

---

## Aktivacija

Rola se primenjuje na hostove upisane u grupu `[apply_timezone]`:

```ini
# inventory/hosts.ini
[apply_timezone]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/apply_timezone.yml`, koji postavlja `role_timezone_enabled: true`. Taj fajl ne treba dirati — dolazi iz bootstrap šablona.

Izuzetak po hostu, uz zadržavanje članstva u grupi:

```yaml
# inventory/host_vars/srv-db-01.yml
role_timezone_enabled: false
```

---

## Varijable

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_timezone_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_timezone_name` | `Etc/UTC` | Ime zone po IANA bazi. |
| `role_timezone_ntp_servers` | `[]` | **Obavezno.** Spisak NTP izvora. |
| `role_timezone_ntp_source_type` | `server` | `server` ili `pool`. Važi za celu listu. |
| `role_timezone_restart_services` | `[]` | Servisi koji se restartuju posle promene zone. |

---

## Primeri

### Interni NTP izvori

```yaml
# inventory/group_vars/all.yml
role_timezone_name: Europe/Belgrade
role_timezone_ntp_servers:
  - ntp1.example.com
  - ntp2.example.com
```

### Javni pool

```yaml
role_timezone_ntp_source_type: pool
role_timezone_ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org
```

### Host u drugoj zoni

```yaml
# inventory/host_vars/srv-app-01.yml
role_timezone_name: UTC
```

### Restart demona koji keširaju zonu

```yaml
role_timezone_restart_services:
  - cron
  - rsyslog
```

---

## Napomene

**Fajl `/etc/chrony/chrony.conf` je u potpunosti u vlasništvu role.** Sve što je bilo u njemu se briše pri prvom pokretanju — uključujući izvore koje je upisao instalacioni program, `confdir /etc/chrony/conf.d` i `sourcedir /run/chrony-dhcp`. Prethodna verzija se čuva kao `.conf.<timestamp>~` u istom folderu.

**Posledica: DHCP više ne može da nametne NTP izvor.** Na sistemu koji dobija adresu preko DHCP-a to je čest izvor zabune — `chronyc sources` prikazuje server koji nigde nije zadat. Ovde toga nema.

**`role_timezone_ntp_source_type` važi za celu listu.** Mešanje javnog `pool`-a i internog `server`-a u istoj konfiguraciji nije podržano namerno; host u produkciji treba da ima jedan izvor istine o vremenu. Ako ti stvarno treba oboje, koristi `server` i upiši konkretne adrese javnih servera.

**`systemd-timesyncd` se ne gasi eksplicitno.** `chrony.service` ima `Conflicts=systemd-timesyncd.service`, pa pokretanjem `chrony`-ja `timesyncd` sam prestaje da radi, i pri startu sistema i pri ručnom pokretanju.

**Neki demoni ne vide promenu zone dok se ne restartuju.** `cron` i `rsyslog` čitaju `TZ` pri pokretanju i posle promene nastavljaju da rade po staroj zoni. Za njih postoji `role_timezone_restart_services`. Servis koji nije instaliran prekida rad role, pa u listu upisuj samo ono što na hostu zaista postoji.

**Zona razlikuje velika i mala slova.** `Europe/Belgrade` jeste, `europe/belgrade` nije. Rola pre postavljanja proverava da fajl postoji u `/usr/share/zoneinfo` i prijavljuje jasnu grešku.

**Nadogradnja paketa neće prepisati konfiguraciju.** `chrony.conf` je `conffile`; `dpkg` vidi lokalnu izmenu i zadržava postojeću verziju. Nova podrazumevana konfiguracija ostaje kao `chrony.conf.dpkg-dist` i može se bez posledica zanemariti.

---

## Struktura

```text
roles/timezone/
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
    └── chrony.conf.j2
```

---

## Idempotentnost

Rola je idempotentna. Modul `community.general.timezone` poredi trenutnu zonu i menja je samo ako se razlikuje; `template` upisuje samo pri razlici u sadržaju i restart `chrony`-ja aktivira isključivo preko handlera. Ponovljeno pokretanje nad nepromenjenom konfiguracijom prijavljuje `ok`, ne `changed`.

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit apply_timezone --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Zona i stanje sinhronizacije
ansible srv-web-01 -m command -a "timedatectl status"

# Izvori — kolona ^* označava izvor po kome se sat trenutno vodi
ansible srv-web-01 -m command -a "chronyc sources -v"

# Odstupanje sata i kvalitet sinhronizacije
ansible srv-web-01 -m command -a "chronyc tracking"
```

---

## Rešavanje problema

**`assert` puca na praznoj listi izvora**

Rola upisuje ceo `chrony.conf`, pa bez izvora host ne bi sinhronizovao vreme. Popuni `role_timezone_ntp_servers` u `group_vars/all.yml` ili isključi rolu za taj host.

**`assert` puca na zoni koja ne postoji**

Ime je pogrešno napisano ili sistem nema `tzdata`. Proveri:

```bash
ansible srv-web-01 -m command -a "timedatectl list-timezones"
```

**Vreme se ne sinhronizuje iako je servis pokrenut**

```bash
chronyc sources -v
```

Ako su svi izvori u stanju `?`, saobraćaj ne prolazi. Najčešći uzrok je zatvoren UDP port 123 ka izvoru. Rola `firewall` ne ograničava izlazni saobraćaj, pa proveri mrežu između hosta i NTP servera.

**`chronyc` prijavljuje izvor koji nisi zadao**

Znači da rola nije pokrenuta na tom hostu ili je konfiguracija posle toga ručno menjana. Pokreni `./apply.sh --limit <host> --check --diff` i pogledaj razliku.

**Logovi i dalje pišu staro vreme**

Demon nije pročitao novu zonu. Dodaj ga u `role_timezone_restart_services` i pokreni rolu ponovo, ili restartuj ručno.

**Promena zone ne prolazi u kontejneru**

`timedatectl` zahteva `systemd` i pisanje u `/etc/localtime`. U LXC/Docker okruženju bez `systemd`-a rola nije primenljiva — isključi je kroz `host_vars`.

---

## Izmene u odnosu na raniju verziju

Ranija verzija je nudila izbor između `systemd-timesyncd` i `chrony`-ja, upisivala drop-in u `/etc/chrony/conf.d/99-ansible.conf` i imala poseban prekidač za gašenje podrazumevanih `pool` linija u osnovnom fajlu.

Šta je s tim bilo loše:

- Drop-in **dodaje** izvore, ne zamenjuje ih. Bez `disable_default_pools` host je pored zadatih izvora koristio i Ubuntu-ove, a spisak izvora se nije video na jednom mestu.
- Gašenje `pool` linija se radilo modulom `replace` nad tuđim fajlom — krhko i teško za praćenje.
- `conf.d` postoji tek od `chrony` 4.0, pa je rola morala da detektuje verziju i da puca na starijim sistemima.
- Dva podržana demona znače dva šablona, mapu u `vars/main.yml` i grananje kroz cele taskove, a u praksi se koristio samo jedan.

Nova verzija piše ceo fajl, podržava samo `chrony` i ima pet varijabli umesto devet. Fajl `templates/timesyncd.conf.j2` se briše iz repozitorijuma.
