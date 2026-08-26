# Rola: timezone

Postavlja vremensku zonu sistema i, opciono, konfiguriše sinhronizaciju vremena.

Dva su zadatka namerno razdvojena prekidačima. Zona se postavlja uvek; NTP deo je podrazumevano isključen, jer većina distribucija već ima ispravno podešenu sinhronizaciju i nema razloga da se dira.

| Šta rola radi | Podrazumevano |
|---|---|
| Postavlja vremensku zonu | uključeno |
| Konfiguriše `systemd-timesyncd` ili `chrony` | isključeno |
| Menja režim hardverskog sata | isključeno |

---

## Preduslovi

Kolekcija `community.general` (modul `timezone`):

```bash
ansible-galaxy collection install community.general
```

Za NTP deo rola zahteva Debian/Ubuntu — putanje konfiguracije se razlikuju po familiji distribucija. Postavljanje same zone radi svuda.

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

### Aktivacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_timezone_enabled` | `false` | Kada je `false`, rola ne dira ništa. |

### Vremenska zona

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_timezone_name` | `Etc/UTC` | Ime zone po IANA bazi. |
| `role_timezone_hwclock` | `""` | `UTC` ili `local`. Prazno = ne diraj. |
| `role_timezone_restart_services` | `[]` | Servisi koji se restartuju posle promene zone. |

### Sinhronizacija vremena

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_timezone_ntp_enabled` | `false` | Uključuje konfiguraciju NTP klijenta. |
| `role_timezone_ntp_service` | `systemd-timesyncd` | `systemd-timesyncd` ili `chrony`. |
| `role_timezone_ntp_servers` | `[]` | **Obavezno** kada je NTP uključen. |
| `role_timezone_ntp_fallback_servers` | `[]` | Samo za `systemd-timesyncd`. |

### chrony

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_timezone_chrony_source_type` | `server` | `server`, `pool` ili `peer`. |
| `role_timezone_chrony_iburst` | `true` | Ubrzava prvu sinhronizaciju. |
| `role_timezone_chrony_makestep` | `"1.0 3"` | Skokovit ispravak u prvim merenjima. Prazno = ne upisuj. |
| `role_timezone_chrony_disable_default_pools` | `false` | Gasi `pool` linije u osnovnom `chrony.conf`. |

---

## Primeri

### Zona za sve hostove

```yaml
# inventory/group_vars/all.yml
role_timezone_name: Europe/Belgrade
```

### Interni NTP izvor u zatvorenoj mreži

```yaml
# inventory/group_vars/all.yml
role_timezone_ntp_enabled: true
role_timezone_ntp_service: chrony
role_timezone_ntp_servers:
  - ntp1.example.com
  - ntp2.example.com
role_timezone_chrony_disable_default_pools: true
```

Bez poslednje linije host bi pored internih izvora pokušavao i javni pool iz osnovnog `chrony.conf`, što u mreži bez izlaza znači nepotrebna čekanja.

### timesyncd sa rezervnim izvorom

```yaml
role_timezone_ntp_enabled: true
role_timezone_ntp_service: systemd-timesyncd
role_timezone_ntp_servers:
  - 10.0.0.53
role_timezone_ntp_fallback_servers:
  - 0.pool.ntp.org
```

### Host u drugoj zoni

```yaml
# inventory/host_vars/srv-app-01.yml
role_timezone_name: UTC
```

---

## Napomene

**Neki demoni ne vide promenu zone dok se ne restartuju.** `cron` i `rsyslog` čitaju `TZ` pri pokretanju i posle promene nastavljaju da rade po staroj zoni. Ako ti je to bitno:

```yaml
role_timezone_restart_services:
  - cron
  - rsyslog
```

Restart se izvršava **samo ako je zona stvarno promenjena** — ponovljeno pokretanje role ne restartuje ništa.

**chrony drop-in dodaje izvore, ne zamenjuje ih.** Rola upisuje `/etc/chrony/conf.d/99-ansible.conf`, a osnovni `/etc/chrony/chrony.conf` ostaje nedirnut sa svojim `pool` linijama. To je namerno — dve role koje pišu isti fajl su izvor sukoba. Za isključivu kontrolu nad izvorima koristi `role_timezone_chrony_disable_default_pools`.

**chrony stariji od 4.0 ne podržava `conf.d`.** Na Ubuntu 20.04 (chrony 3.5) drop-in bi bio uredno upisan ali nikada pročitan. Rola to hvata i prekida rad sa objašnjenjem. Rešenje je ručno dodavanje `confdir /etc/chrony/conf.d` u osnovni fajl ili prelazak na `systemd-timesyncd`.

**chrony i timesyncd ne rade istovremeno.** `chrony.service` ima `Conflicts=systemd-timesyncd.service`, pa pokretanjem chrony-ja timesyncd sam prestaje da radi. Rola ne mora ništa da gasi.

**`hwclock` u virtuelnim mašinama.** Postavljanje ove vrednosti može da padne jer hardverski sat nije dostupan. Podrazumevano je prazno — ne diraj ga bez razloga.

**Zona sa velikim i malim slovima.** `Europe/Belgrade` je ispravno, `europe/belgrade` nije. Rola pre postavljanja proverava da fajl postoji u `/usr/share/zoneinfo` i prijavljuje jasnu grešku.

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
    ├── chrony.conf.j2
    └── timesyncd.conf.j2
```

`vars/main.yml` sadrži izvedene vrednosti — imena paketa, servisa i putanje konfiguracije po izabranom NTP demonu. Prefiks `_` označava da nisu deo javnog interfejsa role i da se ne menjaju kroz inventory.

---

## Idempotentnost

Rola je idempotentna. Modul `community.general.timezone` poredi trenutnu zonu i menja je samo ako se razlikuje; `template` upisuje samo pri razlici u sadržaju; `replace` ne hvata već zakomentarisane linije. Ponovljeno pokretanje nad nepromenjenom konfiguracijom prijavljuje `ok`, ne `changed`.

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit apply_timezone --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Stanje sata i sinhronizacije
ansible srv-web-01 -m command -a "timedatectl status"

# Izvori — timesyncd
ansible srv-web-01 -m command -a "timedatectl show-timesync --all"

# Izvori — chrony
ansible srv-web-01 -m command -a "chronyc sources -v"
```

---

## Rešavanje problema

**`assert` puca na zoni koja ne postoji**

Ime je pogrešno napisano ili sistem nema `tzdata`. Proveri:

```bash
ansible srv-web-01 -m command -a "timedatectl list-timezones"
```

**Vreme se ne sinhronizuje iako je servis pokrenut**

Proveri da li izvori uopšte odgovaraju:

```bash
chronyc sources -v          # kolona ^* označava aktivan izvor
timedatectl show-timesync   # ServerAddress mora biti popunjen
```

Najčešći uzrok je zatvoren UDP port 123 ka izvoru. Ako rola `firewall` upravlja hostom, izlazni saobraćaj podrazumevano nije ograničen, ali proveri mrežu između hosta i NTP servera.

**`chronyc` prijavlja izvore koje nisi zadao**

To su `pool` linije iz osnovnog `/etc/chrony/chrony.conf`. Uključi `role_timezone_chrony_disable_default_pools: true`.

**Logovi i dalje pišu staro vreme**

Demon nije pročitao novu zonu. Dodaj ga u `role_timezone_restart_services` i pokreni rolu ponovo, ili restartuj ručno.

**Promena zone ne prolazi u kontejneru**

`timedatectl` zahteva `systemd` i pisanje u `/etc/localtime`. U LXC/Docker okruženju bez `systemd`-a rola nije primenljiva — isključi je kroz `host_vars`.
