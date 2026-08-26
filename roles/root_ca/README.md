# Rola: root_ca

Vodi lokalni Certificate Authority i izdaje serverske sertifikate potpisane njime. Namenjena je internoj infrastrukturi — monitoring, interni web servisi, VPN, privatni API-ji — gde javni CA nije potreban.

Rola radi **na jednom hostu**. Taj host čuva privatni ključ CA i izdaje sertifikate; ostali hostovi dobijaju samo `ca.crt` i sopstveni par ključ/sertifikat.

---

## Preduslovi

Kolekcija `community.crypto`:

```bash
ansible-galaxy collection install community.crypto
```

Python biblioteka `cryptography` na CA hostu — rolu je instalira sama (`role_root_ca_install_dependencies`).

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_root_ca]
srv-ca-01
```

**Jedan host.** Rola prekida rad ako ih grupa sadrži više — svaki bi napravio sopstveni, međusobno nepovezan CA, a greška se otkriva tek kada poverenje ne proradi.

Grupi pripada `group_vars/deploy_root_ca.yml`, koji postavlja `role_root_ca_enabled: true`.

---

## Šta se promenilo u odnosu na prethodnu verziju

| Ranije | Sada |
|---|---|
| `openssl` kroz `command` | moduli iz `community.crypto`, idempotentni |
| Vrednosti konkretne organizacije u `defaults` | `CHANGEME` placeholderi, `assert` traži da budu promenjeni |
| `role_root_ca_state` (pokrajina) | `role_root_ca_state_or_province` — staro ime se mešalo sa `present`/`absent` |
| Promena subject polja tiho pravi nov CA | `assert` poredi sa postojećim i prekida rad |
| Bez ekstenzija | `basicConstraints`, `keyUsage`, `extendedKeyUsage`, SKI/AKI |
| SAN se navodi ceo, ručno | `DNS:<cn>` se dodaje sam; navodi se samo ono dodatno |
| Bez obnove | obnova pre isteka, upozorenje za sam CA |
| Bez uklanjanja | `state: absent` po unosu |
| Fajlovi u jednom folderu | `private/` 0700, `certs/`, `csr/` |

Migracija sa postojeće instalacije: preimenuj `role_root_ca_state` u `role_root_ca_state_or_province` i **prekopiraj postojeći `ca.key` i `ca.crt`** u `private/` odnosno `certs/` pre prvog pokretanja. Ako to izostane, rola pravi nov CA i stari izdati sertifikati prestaju da se lančaju.

---

## Struktura na disku

```text
/root/ca/
├── private/          0700
│   ├── ca.key        0600
│   └── zabbix.example.com.key
├── certs/            0755
│   ├── ca.crt
│   ├── zabbix.example.com.crt
│   └── zabbix.example.com-fullchain.crt
└── csr/              0755
```

---

## Varijable

### Aktivacija i lokacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_root_ca_dir` | `/root/ca` | Koren CA foldera. |
| `role_root_ca_basename` | `ca` | Osnovno ime CA fajlova. |

### Identitet CA

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_common_name` | `CHANGEME Root CA` | **Obavezno promeniti.** |
| `role_root_ca_organization` | `CHANGEME` | **Obavezno promeniti.** |
| `role_root_ca_country` | `""` | Dvoslovna oznaka. Prazno = ne upisuj. |
| `role_root_ca_state_or_province` | `""` | Pokrajina. |
| `role_root_ca_locality` | `""` | Grad. |
| `role_root_ca_ou` | `""` | Organizaciona jedinica. |
| `role_root_ca_days` | `7300` | Važenje CA (~20 godina). |
| `role_root_ca_warn_before_days` | `90` | Upozorenje pred istek CA. |

### Ključ CA

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_key_type` | `RSA` | `RSA` ili `ECC`. |
| `role_root_ca_key_size` | `4096` | Za RSA. |
| `role_root_ca_key_curve` | `secp384r1` | Za ECC. |
| `role_root_ca_digest` | `sha256` | Algoritam potpisa. |
| `role_root_ca_key_regenerate` | `never` | Zaštita od nenamernog pravljenja novog ključa. |

### Izdati sertifikati

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_issued_certs` | `[]` | Lista sertifikata. |
| `role_root_ca_cert_days` | `397` | Važenje. |
| `role_root_ca_cert_key_type` | `RSA` | Tip ključa. |
| `role_root_ca_cert_key_size` | `2048` | Za RSA. |
| `role_root_ca_cert_extended_key_usage` | `[serverAuth]` | Namena. |
| `role_root_ca_cert_key_usage` | `[digitalSignature, keyEncipherment]` | Namena ključa. |
| `role_root_ca_cert_subject_from_ca` | `true` | Preuzima C/ST/L/O/OU iz CA. |
| `role_root_ca_cert_owner` | `root` | Vlasnik fajlova. |
| `role_root_ca_cert_group` | `root` | Grupa fajlova. |
| `role_root_ca_cert_key_mode` | `'0640'` | Dozvole nad privatnim ključem. |
| `role_root_ca_cert_mode` | `'0644'` | Dozvole nad sertifikatom. |
| `role_root_ca_renew_before_days` | `30` | Obnova pred istek. `0` isključuje. |
| `role_root_ca_fullchain` | `true` | Upisuje `<ime>-fullchain.crt`. |

### Ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_trust_local` | `false` | Upisuje CA u trust store **ovog** hosta. |
| `role_root_ca_trust_filename` | `internal-root-ca` | Ime fajla u trust store-u. |
| `role_root_ca_fetch_enabled` | `false` | Preuzima sertifikate na kontrolni čvor. |
| `role_root_ca_fetch_dir` | `/opt/ansible/production/files/pki` | Ciljni folder. |
| `role_root_ca_install_dependencies` | `true` | Instalira `python3-cryptography`. |
| `role_root_ca_allow_multiple_hosts` | `false` | Dozvoljava više CA hostova. |
| `role_root_ca_group_name` | `deploy_root_ca` | Grupa koju proverava `assert`. |

---

## Struktura unosa u `role_root_ca_issued_certs`

| Polje | Obavezno | Opis |
|---|---|---|
| `cn` | da | Common Name. |
| `state` | ne | `present` (podrazumevano) ili `absent`. |
| `sans` | ne | **Dodatni** SAN unosi. `DNS:<cn>` se dodaje sam. |
| `filename` | ne | Osnovno ime fajlova. |
| `days` | ne | Važenje. |
| `key_type`, `key_size`, `key_curve` | ne | Nadjačavaju globalne. |
| `owner`, `group`, `key_mode`, `mode` | ne | Vlasništvo i dozvole. |
| `key_usage`, `extended_key_usage` | ne | Namena. |

---

## Primeri

### Minimalna konfiguracija

```yaml
# inventory/group_vars/all.yml
role_root_ca_common_name: "Example Root CA"
role_root_ca_organization: "Example d.o.o."
role_root_ca_country: "RS"

role_root_ca_issued_certs:
  - cn: zabbix.example.com
  - cn: wiki.example.com
```

Svaki dobija SAN `DNS:<cn>` automatski i važi 397 dana.

### Više imena i IP adresa

```yaml
role_root_ca_issued_certs:
  - cn: www.example.com
    sans:
      - "DNS:example.com"
      - "DNS:www2.example.com"
      - "IP:10.0.0.10"
```

### Sertifikat koji čita servis

```yaml
role_root_ca_issued_certs:
  - cn: zabbix.example.com
    owner: root
    group: www-data
    key_mode: '0640'
```

Nginx čita ključ preko grupe. Dozvole se ne otvaraju na `0644` — privatni ključ ne sme biti čitljiv svakom nalogu na sistemu.

### Wildcard

```yaml
role_root_ca_issued_certs:
  - cn: "*.apps.example.com"
    filename: wildcard-apps
```

Bez `filename` fajl bi se zvao `wildcard.apps.example.com.crt` — ispravno, ali `filename` je čitljivije.

### Klijentski sertifikat

```yaml
role_root_ca_issued_certs:
  - cn: klijent-01
    extended_key_usage:
      - clientAuth
```

### Preuzimanje na kontrolni čvor

```yaml
role_root_ca_fetch_enabled: true
role_root_ca_fetch_dir: /opt/ansible/production/files/pki
```

Ciljni folder mora imati dozvole `0700` i biti izvan git repozitorijuma — preuzimaju se i privatni ključevi izdatih sertifikata. Ključ samog CA se ne preuzima nikada.

---

## Napomene

**Privatni ključ CA je najosetljiviji podatak u okruženju.** Ko dođe do njega može izdati sertifikat za bilo koje ime kojem ovi sistemi veruju — uključujući i imena koja nikada nisu bila izdata. Folder je `0700`, ključ `0600`, i ne napušta host.

**Subject polja se ne menjaju posle prvog pokretanja.** Promena bi napravila nov CA sa istim ključem ali drugim izdavačem, i svi ranije izdati sertifikati prestali bi da se lančaju. Rola poredi konfiguraciju sa postojećim sertifikatom i prekida rad. Zamena CA je svesna operacija: arhiviraj folder, obriši ga ručno, pokreni rolu ponovo, pa redistribuiraj `ca.crt` na sve klijente.

**Common Name se više ne gleda.** Od Chrome 58 i ekvivalentnih verzija ostalih klijenata validacija ide isključivo preko SAN-a. Sertifikat bez SAN unosa za sopstveni CN biva odbijen porukom koja ne upućuje na uzrok. Rola zato `DNS:<cn>` dodaje sama — u `sans` ide samo ono dodatno.

**Sistemski trust store ne pokriva sve.** `update-ca-certificates` menja OpenSSL i GnuTLS. Java (`cacerts`), NSS (Firefox, Chrome), Python (`certifi`) i Node imaju sopstvene. Zabbix Java gateway i `pip` su najčešći primeri gde poverenje i dalje ne radi iako je CA uredno instaliran.

**`pathlen:0`.** CA može potpisivati samo krajnje sertifikate, ne i posredne CA. Ako ti treba dvostepena hijerarhija, promeni vrednost u `tasks/main.yml` — ali onda je i izdavanje posrednog CA posao koji ova rola ne pokriva.

**Rola ne vodi CRL.** `state: absent` briše fajlove sa CA hosta, ali ne povlači sertifikat. Ko ga već ima, može ga koristiti do isteka. Zato je podrazumevano važenje 397 dana, a ne nekoliko godina.

**Obnova zadržava ključ.** Menja se samo `.crt` fajl, pa se ne mora ništa ponovo generisati na strani servisa — dovoljno je preuzeti nov sertifikat i restartovati servis.

**Rola ne restartuje servise koji koriste sertifikate.** Obnovljen sertifikat počinje da važi tek kada ga servis ponovo pročita. To pripada roli koja tim servisom upravlja.

---

## Struktura

```text
roles/root_ca/
├── README.md
├── defaults/
│   └── main.yml
├── vars/
│   └── main.yml
├── handlers/
│   └── main.yml
└── tasks/
    ├── main.yml
    └── issue.yml
```

`issue.yml` se uključuje petljom po sertifikatu. Po unosu ide šest koraka koji moraju ići redom — šest paralelnih petlji nad istom listom bilo bi kraće, ali neuporedivo teže za čitanje.

---

## Idempotentnost

Rola je idempotentna. Moduli `openssl_privatekey`, `openssl_csr` i `x509_certificate` porede postojeće stanje sa zadatim parametrima i menjaju samo pri razlici.

Dva slučaja u kojima je `changed` očekivan:

- sertifikat ulazi u prozor obnove (`role_root_ca_renew_before_days`)
- promenjena je `sans` lista ili druga polja CSR-a

Ključevi se ne generišu ponovo ni u jednom slučaju (`regenerate: never`).

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit deploy_root_ca --check --diff

# Primena
./apply.sh --limit srv-ca-01

# CA sertifikat
ansible srv-ca-01 -m command -a "openssl x509 -in /root/ca/certs/ca.crt -noout -text"

# Izdat sertifikat — subject, SAN, istek
ansible srv-ca-01 -m command -a \
  "openssl x509 -in /root/ca/certs/zabbix.example.com.crt -noout -subject -ext subjectAltName -dates"

# Da li se lanča do CA
ansible srv-ca-01 -m command -a \
  "openssl verify -CAfile /root/ca/certs/ca.crt /root/ca/certs/zabbix.example.com.crt"

# Da li ključ i sertifikat pripadaju jedno drugom
ansible srv-ca-01 -m shell -a \
  "openssl x509 -noout -modulus -in /root/ca/certs/zabbix.example.com.crt | openssl md5; \
   openssl rsa  -noout -modulus -in /root/ca/private/zabbix.example.com.key | openssl md5"
```

Poslednja komanda mora dati dva identična heša. Različiti znače da su ključ i sertifikat iz različitih generisanja.

---

## Rešavanje problema

**`assert` prijavljuje da se identitet CA promenio**

Neko od subject polja se razlikuje od onoga u postojećem `ca.crt`. Vrati staru vrednost, ili — ako je zamena CA namera — arhiviraj i obriši `/root/ca`.

**`CHANGEME` u poruci greške**

`role_root_ca_common_name` ili `role_root_ca_organization` nisu popunjeni. Upiši ih u `group_vars/all.yml`.

**Grupa sadrži više hostova**

Ostavi jedan. Ako zaista vodiš više odvojenih CA, `role_root_ca_allow_multiple_hosts: true` — ali proveri da li ti to stvarno treba.

**`ERR_CERT_COMMON_NAME_INVALID` u pregledaču**

Ime kojim pristupaš nije u SAN listi. Dodaj ga u `sans` tog unosa i pokreni rolu ponovo — sertifikat će biti prepisan pri prvoj promeni CSR-a.

**Klijent i dalje ne veruje CA**

Sertifikat nije u trust store-u tog klijenta, ili klijent ima svoj. Redom:

```bash
ls /usr/local/share/ca-certificates/
openssl s_client -connect zabbix.example.com:443 -CAfile /put/do/ca.crt
```

Za Javu, Firefox, `pip` i Node vidi napomenu o odvojenim trust store-ovima.

**`Unable to load private key`**

Servis nema pravo čitanja ključa. Proveri `owner`, `group` i `key_mode` tog unosa; služba treba da čita preko grupe, ne kroz otvaranje dozvola.

**Rola prijavljuje `changed` pri svakom pokretanju**

Najčešće se `sans` lista razlikuje po redosledu između pokretanja — proveri da nije generisana kroz Jinja izraz koji vraća nesortiran skup.

**`ModuleNotFoundError: cryptography`**

`role_root_ca_install_dependencies` je isključen a paket nije instaliran ručno:

```bash
apt install python3-cryptography
```
