# Rola: repos

Dodaje i uklanja APT repozitorijume na Debian/Ubuntu sistemima.

Rola **ne instalira aplikacije** — samo dodaje izvore. Instalacija je posao role `packages`, koja se u `playbook.yml` izvršava kasnije. Redosled je namerno takav: instalacija iz repozitorijuma koji još nije dodat bi pala.

---

## Dva načina dodavanja

| Varijabla | Kada se koristi |
|---|---|
| `role_repos_list` | **Podrazumevano.** Direktan upis APT izvora. |
| `role_repos_deb_packages` | Kada vendor ne dokumentuje direktan unos. |

Prvi način je predvidljiv: URL repozitorijuma se ne menja godinama, ključ se preuzima sa stabilne adrese, a modul poredi sadržaj i upisuje samo razliku.

Drugi način instalira vendorov konfiguracioni paket (`zabbix-release`, `mysql-apt-config`), koji zatim sam upiše `.sources` fajl i ključ. Radi, ali URL sadrži reviziju paketa koja se menja bez najave — `zabbix-release_7.0-1` je postao `7.0-2`, pa stari URL vraća 404. Zbog toga je ovo drugi izbor, ne prvi.

Ne mešaj oba načina za isti repozitorijum — dobićeš dva `.sources` fajla koja pokazuju na isto mesto.

---

## Aktivacija

Rola se primenjuje na hostove upisane u grupu `[apply_repos]`:

```ini
# inventory/hosts.ini
[apply_repos]
srv-web-01
srv-mon-01
```

Grupi pripada `group_vars/apply_repos.yml`, koji postavlja `role_repos_enabled: true`. Taj fajl ne treba dirati.

Izuzetak po hostu:

```yaml
# inventory/host_vars/srv-db-01.yml
role_repos_enabled: false
```

---

## Preduslovi

| Zahtev | Razlog |
|---|---|
| `ansible-core` 2.15+ | modul `deb822_repository` je dodat u toj verziji |
| `apt` 2.4+ (Ubuntu 22.04+) | podrška za `.sources` format |
| Debian ili Ubuntu | rola prekida rad nad ostalim distribucijama |

RHEL/Rocky/Alma nisu podržani. Rola pukne sa jasnom porukom umesto da tiho ne uradi ništa.

---

## Varijable

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_repos_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_repos_list` | `[]` | Repozitorijumi upisani direktno. |
| `role_repos_deb_packages` | `[]` | Vendorovi `.deb` release paketi. |
| `role_repos_update_cache` | `true` | Osvežava APT keš posle izmene. |

### Polja u `role_repos_list`

| Polje | Obavezno | Podrazumevano | Opis |
|---|---|---|---|
| `name` | da | — | Ime fajla u `/etc/apt/sources.list.d/`. |
| `uris` | da | — | Bazni URL repozitorijuma. |
| `suites` | ne | kodno ime distribucije | `noble`, `jammy`, `bookworm`… |
| `components` | ne | `[main]` | Kanali unutar repozitorijuma. |
| `signed_by` | ne | — | URL GPG ključa ili putanja do keyring fajla. |
| `architectures` | ne | sve | Npr. `amd64`. |
| `types` | ne | `[deb]` | Dodaj `deb-src` ako trebaju izvorni paketi. |
| `enabled` | ne | `true` | Upisuje unos ali ga isključuje. |
| `state` | ne | `present` | `absent` uklanja repozitorijum. |

### Polja u `role_repos_deb_packages`

| Polje | Obavezno | Opis |
|---|---|---|
| `name` | da | Ime paketa kako ga vidi `dpkg`. Koristi se pri uklanjanju. |
| `url` | za `present` | Puna adresa `.deb` fajla. |
| `state` | ne | `present` (podrazumevano) ili `absent`. |

---

## Primeri

Sve ide u `inventory/group_vars/all.yml` (globalno) ili `host_vars/<host>.yml` (za pojedinačan host).

### Zabbix 7.0 LTS

```yaml
role_repos_list:
  - name: zabbix
    uris: "https://repo.zabbix.com/zabbix/7.0/ubuntu"
    suites: "{{ ansible_distribution_release }}"
    components: [main]
    signed_by: "https://repo.zabbix.com/zabbix-official-repo.key"
```

**Pažnja na putanju** — Zabbix je menjao strukturu URL-a između verzija:

| Verzija | Putanja |
|---|---|
| 7.0 LTS | `/zabbix/7.0/ubuntu` |
| 7.2 | `/zabbix/7.2/release/ubuntu` |
| 7.4 | `/zabbix/7.4/release/ubuntu` |

Od 7.2 postoje dva odvojena repozitorijuma: `release` (zakovana tačka izdanja) i `stable` (prati minor izdanja unutar iste verzije). Za produkciju je `release` predvidljiviji.

### Docker

```yaml
role_repos_list:
  - name: docker
    uris: "https://download.docker.com/linux/ubuntu"
    suites: "{{ ansible_distribution_release }}"
    components: [stable]
    architectures: amd64
    signed_by: "https://download.docker.com/linux/ubuntu/gpg"
```

Docker zvanično traži da arhitektura bude eksplicitno navedena. Bez toga APT pokušava da povuče i `i386` indekse kojih nema, pa `apt update` prijavljuje grešku.

Na Debianu zameni `ubuntu` sa `debian` u `uris` i u putanji ključa.

### MySQL

```yaml
role_repos_list:
  - name: mysql
    uris: "https://repo.mysql.com/apt/ubuntu/"
    suites: "{{ ansible_distribution_release }}"
    components: [mysql-8.0, mysql-tools]
    signed_by: "https://repo.mysql.com/RPM-GPG-KEY-mysql-2023"
```

Dostupni kanali kao `components`: `mysql-8.0`, `mysql-8.4-lts`, `mysql-innovation`, `mysql-tools`, `mysql-apt-config`. Serija se bira ovde — nema interaktivnog dijaloga kao kod `mysql-apt-config` paketa.

> **Ključ MySQL-a redovno ističe.** Godina u imenu fajla nije stabilna (`-2022`, `-2023`, …), a ključ `B7B3B788A8D3785C` je istekao 22.10.2025. Kada `apt update` prijavi `EXPKEYSIG` ili `NO_PUBKEY`, proveri koji je aktuelan ključ na `repo.mysql.com` i izmeni `signed_by`. Zbog toga je URL ključa varijabla, a ne zakovana vrednost u roli.

### Sva tri odjednom

```yaml
role_repos_list:
  - name: zabbix
    uris: "https://repo.zabbix.com/zabbix/7.0/ubuntu"
    suites: "{{ ansible_distribution_release }}"
    components: [main]
    signed_by: "https://repo.zabbix.com/zabbix-official-repo.key"

  - name: docker
    uris: "https://download.docker.com/linux/ubuntu"
    suites: "{{ ansible_distribution_release }}"
    components: [stable]
    architectures: amd64
    signed_by: "https://download.docker.com/linux/ubuntu/gpg"

  - name: mysql
    uris: "https://repo.mysql.com/apt/ubuntu/"
    suites: "{{ ansible_distribution_release }}"
    components: [mysql-8.0, mysql-tools]
    signed_by: "https://repo.mysql.com/RPM-GPG-KEY-mysql-2023"
```

### Preko `.deb` release paketa

```yaml
role_repos_deb_packages:
  - name: zabbix-release
    url: "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb"
```

Verzija Ubuntua je deo imena fajla, pa isti URL ne radi na 22.04 i 24.04. Ako imaš mešovitu flotu:

```yaml
role_repos_deb_packages:
  - name: zabbix-release
    url: "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu{{ ansible_distribution_version }}_all.deb"
```

Uklanjanje, zajedno sa `.sources` fajlom koji je paket upisao:

```yaml
role_repos_deb_packages:
  - name: zabbix-release
    state: absent
```

### Uklanjanje direktno upisanog repozitorijuma

```yaml
role_repos_list:
  - name: stari-repo
    uris: "https://example.com/apt"
    state: absent
```

Unos mora ostati u listi dok se ne primeni nad svim hostovima. Ako ga samo obrišeš iz liste, fajl na serveru ostaje.

### Različiti repozitorijumi po ulozi servera

Pošto `host_vars` ima viši prioritet, lista se može zameniti za pojedinačan host:

```yaml
# host_vars/srv-mon-01.yml
role_repos_list:
  - name: zabbix
    uris: "https://repo.zabbix.com/zabbix/7.0/ubuntu"
    suites: "{{ ansible_distribution_release }}"
    components: [main]
    signed_by: "https://repo.zabbix.com/zabbix-official-repo.key"
```

Lista se **ne spaja** sa globalnom — `host_vars` je u celosti zamenjuje.

---

## Napomene

**Suite nije uvek kodno ime.** Podrazumevana vrednost je `ansible_distribution_release` (`noble`, `jammy`), što pokriva Zabbix, Docker i MySQL. Neki proizvođači koriste fiksnu vrednost poput `stable` ili `any` — tada je zadaj eksplicitno.

**Ključ se preuzima sa interneta.** `signed_by` sa URL-om znači da ciljni server mora imati pristup toj adresi. U zatvorenoj mreži prvo prekopiraj ključ i zadaj apsolutnu putanju:

```yaml
signed_by: /etc/apt/keyrings/zabbix.asc
```

**`.deb` paket se preuzima pri svakom pokretanju.** Modul poredi verziju sa instaliranom i prijavljuje `ok` ako je ista, ali fajl svejedno skida. Kod velikog broja hostova to je nepotreban saobraćaj — još jedan razlog da `role_repos_list` bude prvi izbor.

**Keš se osvežava kroz handler**, dakle na kraju play-a. Pošto `packages` rola ide u zasebnom, kasnijem play-u, redosled je ispravan.

**Idempotentnost.** `deb822_repository` poredi sadržaj i upisuje samo kada se razlikuje. Ponovljeno pokretanje prijavljuje `ok`, ne `changed`.

---

## Struktura

```text
roles/repos/
├── README.md
├── defaults/
│   └── main.yml
├── handlers/
│   └── main.yml
└── tasks/
    └── main.yml
```

Rola nema `templates/` — `deb822_repository` sam generiše `.sources` fajl.

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit apply_repos --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Sta je upisano
ansible srv-web-01 -m command -a "ls /etc/apt/sources.list.d/"
ansible srv-web-01 -m command -a "cat /etc/apt/sources.list.d/zabbix.sources"

# Da li APT prihvata izvore
ansible srv-web-01 -m command -a "apt-get update" --become
```

Ako `apt update` prijavi `NO_PUBKEY` ili `EXPKEYSIG`, problem je u ključu, ne u roli — vidi napomenu uz MySQL.
