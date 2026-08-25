# Rola: banner

Upravlja porukama koje korisnik vidi pri prijavi na sistem.

Rola upisuje sadržaj u tri fajla, od kojih su dva podrazumevano isključena:

| Fajl | Kada se prikazuje | Podrazumevano |
|---|---|---|
| `/etc/motd` | posle uspešne prijave | uključeno |
| `/etc/issue` | pre prijave, lokalna konzola | isključeno |
| `/etc/issue.net` | pre prijave, SSH | isključeno |

---

## Aktivacija

Rola se primenjuje na hostove upisane u grupu `[apply_banner]`:

```ini
# inventory/hosts.ini
[apply_banner]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/apply_banner.yml`, koji postavlja `role_banner_enabled: true`. Taj fajl ne treba dirati — dolazi iz bootstrap šablona.

Da bi host privremeno bio izuzet, a da ostane u grupi:

```yaml
# inventory/host_vars/srv-db-01.yml
role_banner_enabled: false
```

---

## Varijable

### Aktivacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_banner_enabled` | `false` | Kada je `false`, rola ne dira nijedan fajl. |

### `/etc/motd`

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_banner_text` | nedefinisan | Prilagođen sadržaj. Ako nije zadat, koristi se `role_banner_default_text`. |
| `role_banner_default_text` | ugrađeno upozorenje | Podrazumevani sadržaj. |

### `/etc/issue`

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_banner_issue_enabled` | `false` | Uključuje upis u `/etc/issue`. |
| `role_banner_issue_text` | nedefinisan | Ako nije zadat, koristi se `role_banner_text`, pa `role_banner_default_text`. |

### `/etc/issue.net`

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_banner_issue_net_enabled` | `false` | Uključuje upis u `/etc/issue.net`. |
| `role_banner_issue_net_text` | nedefinisan | Ista kaskada kao gore. |

### Ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_banner_backup` | `false` | Čuva kopiju prethodnog sadržaja pre prepisivanja. |
| `role_banner_owner` | `root` | Vlasnik upisanih fajlova. |
| `role_banner_group` | `root` | Grupa upisanih fajlova. |
| `role_banner_mode` | `'0644'` | Dozvole nad upisanim fajlovima. |

---

## Kaskada teksta

Za `/etc/issue` i `/etc/issue.net` sadržaj se bira ovim redom:

```text
role_banner_issue_text  →  role_banner_text  →  role_banner_default_text
```

Praktično: ako zadaš samo `role_banner_text`, sva tri fajla dobijaju isti sadržaj. Poseban tekst po fajlu zadaješ samo kada ti stvarno treba.

Kaskada koristi Jinja2 filter `default(..., true)`. Drugi argument znači da fallback radi i kada je varijabla definisana ali **prazna**, ne samo kada je nedefinisana. Bez toga bi `role_banner_text: ""` upisao prazan fajl umesto podrazumevanog teksta.

---

## Primeri

### Globalni baner za sve hostove

```yaml
# inventory/group_vars/all.yml
role_banner_text: |
  *****************************************************************
  *  UPOZORENJE                                                   *
  *  Pristup dozvoljen samo ovlascenim licima.                    *
  *  Kontakt: sysadmin@example.com                                *
  *****************************************************************
```

### Poseban baner za jedan host

```yaml
# inventory/host_vars/srv-db-01.yml
role_banner_text: |
  PRODUKCIJSKA BAZA PODATAKA
  Izmene iskljucivo uz odobrenje.
```

### Uključivanje SSH banera pre prijave

```yaml
# inventory/group_vars/all.yml
role_banner_issue_net_enabled: true
```

### Dinamički sadržaj

Podržani su Jinja2 izrazi:

```yaml
role_banner_text: |
  Host: {{ inventory_hostname }}
  OS:   {{ ansible_distribution }} {{ ansible_distribution_version }}
  Kontakt: sysadmin@example.com
```

---

## Napomene

**Okvir od zvezdica i promenljive se ne slažu.** `{{ inventory_hostname }}` se širi na različitu dužinu po hostu, pa desna ivica okvira neće biti poravnata:

```text
* Host: srv01                    *
* Host: zabbix-proxy-ns-01                    *
```

Ako ti je poravnanje bitno, koristi `format` filter ili izostavi desnu ivicu.

**Rola ne dira `/etc/ssh/sshd_config`.** Da bi SSH zaista prikazao `/etc/issue.net`, tamo mora stajati:

```text
Banner /etc/issue.net
```

Ako ta opcija nije podešena, fajl će biti uredno upisan ali ga niko neće videti. Izmena `sshd_config` pripada zasebnoj roli — dve role koje menjaju isti fajl su izvor sukoba.

**Neke distribucije prepisuju `/etc/motd`.** Ubuntu koristi `update-motd.d` skripte koje generišu dinamički sadržaj pri svakoj prijavi. Ako baner ne vidiš posle primene role, proveri:

```bash
ls /etc/update-motd.d/
```

Ova rola upravlja isključivo statičkim `/etc/motd`.

---

## Struktura

```text
roles/banner/
├── README.md
├── defaults/
│   └── main.yml
└── tasks/
    └── main.yml
```

Rola nema `handlers/` — `/etc/motd` nema servis koji bi se restartovao. Izmene važe od sledeće prijave.

---

## Idempotentnost

Rola je idempotentna. Modul `ansible.builtin.copy` poredi sadržaj i upisuje samo kada se razlikuje. Ponovljeno pokretanje nad nepromenjenom konfiguracijom prijavljuje `ok`, ne `changed`.

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit apply_banner --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Provera rezultata
ansible srv-web-01 -m command -a "cat /etc/motd"
```
