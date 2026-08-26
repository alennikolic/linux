# Rola: etc_hosts

Upravlja statičkim mapiranjem imena u IP adrese kroz `/etc/hosts`.

Rola se zove `etc_hosts`, a ne `hosts`, jer je `hosts` rezervisana reč u Ansible playbook sintaksi.

---

## Dva režima

| Režim | Šta radi | Kada |
|---|---|---|
| `block` (podrazumevano) | upisuje samo označeni blok, ostatak fajla ne dira | gotovo uvek |
| `file` | prepisuje ceo `/etc/hosts` iz šablona | kada fajl mora biti identičan na svim hostovima |

Podrazumevani režim je aditivan namerno. `/etc/hosts` je fajl čiji gubitak sadržaja odmah pogađa ceo sistem — bez linije za `localhost` `sudo` čeka na tajmaut pri svakom pozivu, a servisi koji razrešavaju sopstveno ime prestaju da se podižu.

U režimu `block` fajl izgleda ovako:

```text
127.0.0.1   localhost
127.0.1.1   srv-web-01.example.com srv-web-01

# BEGIN ANSIBLE ROLA: etc_hosts
# Unosi iz role_etc_hosts_entries.
10.0.0.10       zabbix.example.com zabbix    # Zabbix server
10.0.0.53       ntp.example.com
# END ANSIBLE ROLA: etc_hosts
```

Sve izvan markera ostaje netaknuto.

---

## Aktivacija

```ini
# inventory/hosts.ini
[apply_etc_hosts]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/apply_etc_hosts.yml`, koji postavlja `role_etc_hosts_enabled: true`. Taj fajl ne treba dirati.

Izuzetak po hostu:

```yaml
# inventory/host_vars/srv-db-01.yml
role_etc_hosts_enabled: false
```

---

## Varijable

### Aktivacija i režim

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_etc_hosts_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_etc_hosts_manage_mode` | `block` | `block` ili `file`. |

### Unosi

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_etc_hosts_entries` | `[]` | Lista unosa. Prazna lista u režimu `block` uklanja blok. |

Struktura unosa:

| Ključ | Obavezno | Opis |
|---|---|---|
| `ip` | da | IPv4 ili IPv6 adresa. |
| `hostnames` | da | Lista imena ili jedno ime kao string. Prvo je kanonsko, ostala su aliasi. |
| `comment` | ne | Komentar na kraju linije. |

### Fajl

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_etc_hosts_path` | `/etc/hosts` | Putanja. Menja se praktično samo pri testiranju. |
| `role_etc_hosts_backup` | `true` | Kopija pre izmene. |
| `role_etc_hosts_owner` | `root` | Vlasnik. |
| `role_etc_hosts_group` | `root` | Grupa. |
| `role_etc_hosts_mode` | `'0644'` | Dozvole. |

### Režim `block`

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_etc_hosts_block_marker` | `ANSIBLE ROLA: etc_hosts` | Tekst markera. |
| `role_etc_hosts_block_insertafter` | `EOF` | Gde se blok upisuje ako još ne postoji. |
| `role_etc_hosts_block_state` | `present` | `absent` uklanja blok bez brisanja liste unosa. |

### Režim `file`

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_etc_hosts_localhost_lines` | četiri Debian linije | Sadržaj vrha fajla. Mora sadržati `127.0.0.1`. |
| `role_etc_hosts_self_enabled` | `true` | Upisuje liniju sa sopstvenim imenom hosta. |
| `role_etc_hosts_self_ip` | `127.0.1.1` | Adresa za tu liniju. |
| `role_etc_hosts_self_names` | `[]` | Prazno = izvedi iz `ansible_fqdn` i `ansible_hostname`. |

### cloud-init

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_etc_hosts_cloud_init_check` | `true` | Detektuje da li cloud-init regeneriše fajl. |
| `role_etc_hosts_cloud_init_disable` | `false` | Upisuje drop-in koji to gasi. |
| `role_etc_hosts_cloud_init_file` | `/etc/cloud/cloud.cfg.d/99-ansible-etc-hosts.cfg` | Putanja drop-in fajla. |

---

## Primeri

### Zabbix okruženje bez DNS-a

```yaml
# inventory/group_vars/all.yml
role_etc_hosts_entries:
  - ip: 10.0.0.10
    hostnames:
      - zabbix.example.com
      - zabbix
    comment: Zabbix server

  - ip: 10.0.0.11
    hostnames:
      - zabbix-proxy-01.example.com
      - zabbix-proxy-01
    comment: Zabbix proxy, lokacija A

  - ip: 10.0.0.20
    hostnames: db.example.com
```

Isti blok dobija svaki host u grupi `[apply_etc_hosts]`.

### Dodatni unos samo za jedan host

`host_vars` ima viši prioritet, ali **zamenjuje** listu, ne dodaje na nju:

```yaml
# inventory/host_vars/srv-app-01.yml
role_etc_hosts_entries: "{{ role_etc_hosts_entries + [{'ip': '10.0.0.99', 'hostnames': ['backup.example.com']}] }}"
```

Ako ti ova sintaksa smeta, jednostavnije je nabrojati celu listu ponovo.

### Uklanjanje bloka

```yaml
role_etc_hosts_block_state: absent
```

Ili prosto isprazni `role_etc_hosts_entries` — rola tada sama uklanja blok.

### Pun nadzor nad fajlom

```yaml
role_etc_hosts_manage_mode: file
role_etc_hosts_entries:
  - ip: 10.0.0.10
    hostnames: [zabbix.example.com, zabbix]
```

Pre prve primene obavezno:

```bash
./apply.sh --limit srv-web-01 --check --diff
```

---

## Napomene

**cloud-init briše `/etc/hosts` pri podizanju sistema.** Na cloud image-ima i instalacijama kroz subiquity `manage_etc_hosts` je često uključen, što znači da se fajl regeneriše iz šablona pri svakom butu. Izmene koje rola upiše nestaju posle prvog restarta — bez ijedne poruke o grešci.

Rola to prepoznaje i ispisuje upozorenje. Trajno rešenje:

```yaml
role_etc_hosts_cloud_init_disable: true
```

Provera stanja:

```bash
grep -rE 'manage_etc_hosts' /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d/
```

**Linija `127.0.1.1` nije ista stvar kao `127.0.0.1`.** Debian konvencija razdvaja localhost od imena mašine, da bi host bez stalne IP adrese mogao da razreši sopstveno ime. Bez te linije `sudo` prijavljuje `unable to resolve host` i čeka na tajmaut pri svakom pozivu. U režimu `file` rola je upisuje sama; u režimu `block` je ne dira jer je ionako ne briše.

**`/etc/hosts` ne zamenjuje DNS, ali ga nadjačava.** `nsswitch.conf` na većini sistema ima `hosts: files dns`, pa unos u `/etc/hosts` pobeđuje DNS zapis. Korisno u zatvorenoj mreži, ali znači da promena IP adrese na jednom mestu ne stiže do hostova — mora se pokrenuti rola.

**Isto ime na dve adrese je tiha greška.** Razrešavanje uzima prvi pogodak, pa rezultat zavisi od redosleda u listi. Rola to hvata `assert`-om pre upisa.

**Rola nema handler.** `/etc/hosts` nema servis koji bi se restartovao — izmene važe odmah, za svaki naredni poziv razrešavanja. Izuzetak su procesi koji su ime već keširali; njima je potreban restart.

---

## Struktura

```text
roles/etc_hosts/
├── README.md
├── defaults/
│   └── main.yml
├── tasks/
│   └── main.yml
└── templates/
    ├── entries.j2
    └── hosts.j2
```

`entries.j2` se koristi na dva mesta: kroz `lookup('template', ...)` za sadržaj bloka, i kroz `{% include %}` unutar `hosts.j2`. Zbog toga su unosi definisani samo jednom.

Rola nema `vars/` — nema izvedenih vrednosti koje bi tamo pripadale.

---

## Idempotentnost

Rola je idempotentna. `blockinfile` poredi sadržaj između markera; `template` poredi ceo fajl. Ponovljeno pokretanje nad nepromenjenom konfiguracijom prijavljuje `ok`, ne `changed`.

Izuzetak je host na kojem cloud-init regeneriše fajl — tamo će rola posle svakog restarta prijaviti `changed`. To je simptom, ne greška u roli.

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit apply_etc_hosts --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Sadržaj fajla
ansible srv-web-01 -m command -a "cat /etc/hosts"

# Da li se ime zaista razrešava
ansible srv-web-01 -m command -a "getent hosts zabbix.example.com"
```

`getent` je bolja provera od `ping` jer prolazi kroz `nsswitch.conf` i pokazuje šta sistem stvarno vidi.

---

## Rešavanje problema

**Blok nestane posle restarta**

cloud-init. Vidi napomenu iznad i uključi `role_etc_hosts_cloud_init_disable`.

**`sudo` je odjednom spor**

Nedostaje linija sa imenom hosta. Proveri:

```bash
hostname
getent hosts $(hostname)
```

Ako drugi izlaz je prazan, vrati liniju `127.0.1.1 <ime>` ili uključi `role_etc_hosts_self_enabled` u režimu `file`.

**`assert` prijavljuje ponovljeno ime**

Isto ime stoji u dva unosa sa različitim adresama. Poruka greške navodi tačno koja imena.

**Blok se upisuje na pogrešno mesto**

Podrazumevano ide na kraj fajla, što je bezbedno. Ako iz nekog razloga mora ranije:

```yaml
role_etc_hosts_block_insertafter: '^127\.0\.1\.1'
```

**Promena ne stiže do aplikacije**

Proces je ime već keširao. Restartuj ga; `systemd-resolved` po potrebi:

```bash
resolvectl flush-caches
```

**Rola prijavljuje da fajl ne postoji**

`/etc/hosts` ne postoji na hostu. Rola namerno ne kreira fajl od nule u režimu `block` — odsustvo tog fajla je znak da nešto nije u redu sa sistemom, i tiho kreiranje bi sakrilo pravi problem.
