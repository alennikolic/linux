# Rola: packages

Instalira i uklanja pakete na Debian/Ubuntu sistemima.

Rola radi sa dve liste — jednom za instalaciju, jednom za uklanjanje. Ne dodaje repozitorijume (to je posao role `repos`) i ne nadograđuje sistem (posao role `updates`).

---

## Mesto u redosledu

```text
repos  →  packages  →  updates
```

Redosled u `playbook.yml` je namerno takav. Instalacija iz repozitorijuma koji još nije dodat bi pala, pa `repos` mora ići prvi.

---

## Aktivacija

Rola se primenjuje na hostove upisane u grupu `[deploy_packages]`:

```ini
# inventory/hosts.ini
[deploy_packages]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/deploy_packages.yml`, koji postavlja `role_packages_enabled: true`. Taj fajl ne treba dirati.

Izuzetak po hostu:

```yaml
# inventory/host_vars/srv-db-01.yml
role_packages_enabled: false
```

Kaskadno uključivanje kroz `children`:

```ini
[deploy_packages:children]
webservers
dbservers
```

---

## Preduslovi

| Zahtev | Razlog |
|---|---|
| Debian ili Ubuntu | rola prekida rad nad ostalim distribucijama |
| Repozitorijum već dodat | za pakete van sistemskih izvora |

RHEL/Rocky/Alma nisu podržani. Rola pukne sa jasnom porukom umesto da tiho ne uradi ništa.

---

## Varijable

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_packages_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_packages_install` | `[]` | Paketi za instalaciju. |
| `role_packages_remove` | `[]` | Paketi za uklanjanje. |
| `role_packages_state` | `present` | `present` ili `latest`. |
| `role_packages_update_cache` | `true` | Osvežava listu paketa pre instalacije. |
| `role_packages_cache_valid_time` | `3600` | Preskače osvežavanje ako je keš noviji (sekunde). |
| `role_packages_purge` | `false` | Uklanja i konfiguraciju pri deinstalaciji. |

---

## Primeri

Sve ide u `inventory/group_vars/all.yml` (globalno) ili `host_vars/<host>.yml` (za pojedinačan host).

### Osnovni alati na svim serverima

```yaml
# group_vars/all.yml
role_packages_install:
  - htop
  - vim
  - curl
  - wget
  - net-tools
  - tmux
```

### Uklanjanje nesigurnih alata

```yaml
role_packages_remove:
  - telnet
  - rsh-client
  - rsh-redone-client
```

### Dodatni paketi samo za jedan host

```yaml
# host_vars/srv-db-01.yml
role_packages_install:
  - htop
  - vim
  - percona-toolkit
```

Lista se **ne spaja** sa globalnom — `host_vars` je u celosti zamenjuje. Ako želiš samo da dodaš, ponovi i globalne pakete.

### Zakovana verzija

```yaml
role_packages_install:
  - "zabbix-agent=1:7.0.19-1+ubuntu24.04"
```

Dostupne verzije:

```bash
apt-cache madison zabbix-agent
```

Zakovana verzija sprečava da je `updates` rola nadogradi. Koristi samo kada ti je to namera.

### Uklanjanje zajedno sa konfiguracijom

```yaml
role_packages_remove:
  - apache2
role_packages_purge: true
```

`purge` je nepovratan i briše `/etc/apache2/`. Uverі se da ti konfiguracija ne treba.

---

## Napomene

**`latest` nije za ovu rolu.** `role_packages_state: latest` bi pri svakom pokretanju nadograđivao pakete, i to nad celom grupom istovremeno. Nadogradnja pripada roli `updates`, čiji play koristi `serial: 1` upravo zato da ažuriranje ne obori sve hostove odjednom. Ostavi `present` osim ako tačno znaš zašto ne bi.

**Uklanjanje ne povlači `autoremove`.** Nekorišćene zavisnosti ostaju na sistemu. To je namerno — `autoremove` ume da ukloni više nego što očekuješ, posebno na serverima gde je nešto instalirano ručno. Ako ti treba, pokreni ga svesno:

```bash
ansible srv-web-01 -m apt -a "autoremove=yes" --become --check
```

**Isti paket u obe liste je greška.** Rola to proverava i prekida rad — bez provere bi rezultat zavisio od redosleda taskova, što nije pouzdano. Provera zanemaruje deo sa verzijom, pa `vim=2:9.1` u jednoj i `vim` u drugoj listi takođe biva uhvaćeno.

**Cela lista ide u jedan poziv `apt` modula**, ne u petlju po paketu. Apt tako rešava zavisnosti odjednom i radi osetno brže. Posledica je da izlaz ne pokazuje koji je pojedinačni paket promenjen — za to pokreni sa `-v`.

**`cache_valid_time` sprečava nepotreban `apt-get update`.** Ako je keš noviji od 3600 sekundi, osvežavanje se preskače. Na floti od pedeset servera to je razlika od nekoliko minuta po pokretanju.

**Idempotentnost.** Rola je idempotentna sa `state: present`. Ponovljeno pokretanje nad nepromenjenom listom prijavljuje `ok`, ne `changed`. Sa `state: latest` to više ne važi — svaka nova verzija u repozitorijumu proizvodi `changed`.

---

## Struktura

```text
roles/packages/
├── README.md
├── defaults/
│   └── main.yml
└── tasks/
    └── main.yml
```

Rola nema `handlers/` — instalacija paketa ne zahteva restart servisa koji rola sama upravlja. Servisi koje paketi donose startuju kroz svoje `postinst` skripte.

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit deploy_packages --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Da li je paket instaliran
ansible srv-web-01 -m command -a "dpkg -l htop"

# Koja je verzija
ansible srv-web-01 -m command -a "apt-cache policy zabbix-agent"
```
