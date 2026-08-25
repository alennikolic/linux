# Rola: firewall

Upravlja UFW pravilima na Debian/Ubuntu sistemima.

> ## Upozorenje
>
> Pogrešna pravila mogu prekinuti SSH pristup serveru.
>
> Rola ima ugrađenu zaštitu — **SSH je uvek dozvoljen i to se ne može isključiti nijednom varijablom** — ali to ne pokriva svaki scenario. Pre primene na produkciju:
>
> ```bash
> ./apply.sh --check --diff --limit srv-web-01
> ```
>
> I zadrži otvorenu drugu SSH sesiju dok testiraš.

---

## Kako je rešeno zaključavanje

Tri mehanizma, svaki nezavisan:

**Redosled taskova.** SSH pravilo se upisuje pre nego što podrazumevana zabrana počne da važi. Obrnut redosled bi na aktivnom UFW-u prekinuo postojeću sesiju.

**Task bez uslova.** SSH task nema `when`. Ne postoji kombinacija varijabli koja ga preskače.

**Port iz same konekcije.** `role_firewall_ssh_port` se podrazumevano izvodi iz `ansible_port`, pa radi i kada u `hosts.ini` koristiš nestandardan port:

```ini
srv-web-01  ansible_host=10.0.0.11  ansible_port=2222
```

Rola tada otvara 2222, ne 22.

---

## Preduslovi

| Zahtev | Razlog |
|---|---|
| Kolekcija `community.general` | modul `ufw` |
| Debian ili Ubuntu | rola prekida rad nad ostalim distribucijama |

```bash
ansible-galaxy collection install community.general
```

Ovo je **druga kolekcija** u projektu, pored `ansible.posix` koju traži `ansible_user`.

---

## Aktivacija

```ini
# inventory/hosts.ini
[apply_firewall]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/apply_firewall.yml`, koji postavlja `role_firewall_enabled: true`. Taj fajl ne treba dirati.

Izuzetak po hostu:

```yaml
# inventory/host_vars/srv-db-01.yml
role_firewall_enabled: false
```

---

## Varijable

### SSH

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_firewall_ssh_port` | `{{ ansible_port \| default(22) }}` | Port SSH servisa. |
| `role_firewall_ssh_rule` | `allow` | `allow` ili `limit`. |
| `role_firewall_ssh_from` | `any` | Ograničenje izvorne adrese. |

### Podrazumevane politike

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_firewall_default_incoming` | `deny` | Dolazni saobraćaj. |
| `role_firewall_default_outgoing` | `allow` | Odlazni saobraćaj. |
| `role_firewall_default_routed` | `deny` | Prosleđivanje. |

### Pravila i ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_firewall_rules` | `[]` | Lista pravila. |
| `role_firewall_logging` | `low` | `off`, `low`, `medium`, `high`, `full`. |
| `role_firewall_state` | `enabled` | `enabled` ili `disabled`. |
| `role_firewall_reset` | `false` | **Destruktivno.** Briše sva pravila pre upisa. |

### Polja jednog pravila

| Polje | Obavezno | Podrazumevano | Opis |
|---|---|---|---|
| `port` | `port` ili `name` | — | Broj porta ili opseg (`"8000:8010"`). |
| `name` | `port` ili `name` | — | UFW aplikacioni profil. |
| `rule` | ne | `allow` | `allow`, `deny`, `reject`, `limit`. |
| `proto` | ne | `tcp` | `tcp`, `udp`, `any`. |
| `from` | ne | `any` | Izvorna adresa ili mreža. |
| `to` | ne | `any` | Odredišna adresa na ovom hostu. |
| `direction` | ne | `in` | `in` ili `out`. |
| `comment` | ne | — | Vidljiv u `ufw status`. |
| `delete` | ne | `false` | Uklanja pravilo. |

---

## Primeri

### Zabbix agent dostupan samo serveru

```yaml
# group_vars/all.yml
role_firewall_rules:
  - rule: allow
    port: 10050
    proto: tcp
    from: "10.0.0.50"
    comment: "Zabbix server -> agent"
```

Ovo je pravilo koje ti treba uz rolu `zabbix_agent` — bez njega server ne može da dođe do agenta.

### Web server

```yaml
role_firewall_rules:
  - { rule: allow, port: 80,  proto: tcp, comment: "HTTP" }
  - { rule: allow, port: 443, proto: tcp, comment: "HTTPS" }
```

### Kompletan Zabbix stack po ulozi

```yaml
# host_vars/srv-mon-01.yml
role_firewall_rules:
  - { rule: allow, port: 10051, proto: tcp, from: "10.0.0.0/8", comment: "Agenti -> server" }
  - { rule: allow, port: 8080,  proto: tcp, from: "10.0.0.0/8", comment: "Web frontend" }
```

```yaml
# host_vars/srv-db-01.yml
role_firewall_rules:
  - { rule: allow, port: 3306, proto: tcp, from: "10.0.0.50", comment: "Zabbix server -> baza" }
```

Baza je otvorena samo prema Zabbix serveru, ne prema celoj mreži.

### Opseg portova

```yaml
role_firewall_rules:
  - rule: allow
    port: "8000:8010"
    proto: tcp
    comment: "Aplikacioni portovi"
```

Navodnici su obavezni — bez njih YAML tumači dvotačku kao razdvajač ključa.

### Aplikacioni profil umesto porta

```yaml
role_firewall_rules:
  - rule: allow
    name: "Nginx Full"
    comment: "HTTP i HTTPS kroz profil"
```

Dostupne profile vidiš sa `ufw app list`. Paketi ih sami instaliraju u `/etc/ufw/applications.d/`.

### Zaštita SSH-a od brute-force napada

```yaml
role_firewall_ssh_rule: limit
```

UFW tada blokira izvornu adresu koja u 30 sekundi otvori šest ili više konekcija. Korisno, ali može pogoditi i legitimne alate koji otvaraju više sesija odjednom — na primer Ansible sa visokim `forks`.

### Ograničenje SSH-a na internu mrežu

```yaml
role_firewall_ssh_from: "10.0.0.0/8"
```

> Ako pristupaš sa adrese van tog opsega, ostaješ zaključan. Proveri sve putanje pristupa — kontrolni čvor, VPN, bastion — pre nego što ovo uključiš.

### Uklanjanje pravila

```yaml
role_firewall_rules:
  - rule: allow
    port: 8080
    proto: tcp
    delete: true
```

Unos mora ostati u listi dok se ne primeni na sve hostove. Ako ga samo obrišeš iz liste, pravilo na serveru ostaje — vidi napomenu o aditivnosti.

---

## Napomene

**Rola je aditivna.** Dodaje pravila iz liste, ali ne uklanja ona koja si ranije dodao pa obrisao iz `role_firewall_rules`. UFW nema način da kaže „neka bude tačno ovaj skup pravila", a rešenje kroz reset pri svakom pokretanju bi na trenutak ostavilo server bez zaštite i uvek prijavljivalo `changed`.

Za uklanjanje koristi `delete: true` na pravilu. Za potpunu izgradnju od nule postoji `role_firewall_reset`, uz sve rizike koje nosi.

**`deny` naspram `reject`.** `deny` tiho odbacuje paket — pošiljalac čeka do isteka vremena. `reject` šalje odgovor da je port zatvoren. Za dolazni saobraćaj se koristi `deny`: napadač ne dobija potvrdu da host uopšte postoji.

**IPv6.** UFW podrazumevano primenjuje pravila i na IPv6, kroz `IPV6=yes` u `/etc/default/ufw`. Rola taj fajl ne dira. Ako ti IPv6 nije potreban, isključi ga svesno i ručno.

**Docker zaobilazi UFW.** Ako na hostu radi Docker sa objavljenim portovima, on upisuje pravila direktno u iptables, ispod UFW-a. Kontejner objavljen sa `-p 8080:80` biće dostupan spolja bez obzira na UFW. To je poznato ponašanje Dockera, ne greška u roli — rešava se sa `--network host` ili vezivanjem za `127.0.0.1`.

**`--check` režim ima ograničenja.** UFW modul u check režimu ne može uvek tačno predvideti da li bi pravilo bilo promenjeno, pa ispis ume da bude nepouzdaniji nego kod ostalih rola. Uvek kombinuj sa `--limit` na jedan host.

**Idempotentnost.**
