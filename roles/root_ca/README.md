# Rola: root_ca

Vodi lokalni Certificate Authority i izdaje serverske sertifikate potpisane njime. Namenjena je internoj infrastrukturi — monitoring, interni web servisi, VPN, privatni API-ji — gde javni CA nije potreban.

Rola radi **na jednom hostu**. Taj host čuva privatni ključ CA i potpisuje sertifikate; ostali hostovi dobijaju samo `ca.crt` i sopstveni sertifikat.

---

## Preduslovi

Kolekcija `community.crypto`:

```bash
ansible-galaxy collection install community.crypto
```

Python biblioteka `cryptography` na CA hostu — rola je instalira sama (`role_root_ca_install_dependencies`).

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

## Dva toka izdavanja

Rola podržava dva načina da se dođe do sertifikata. Razlikuju se po tome gde nastaje privatni ključ, što je najvažnija odluka u celom procesu.

### `role_root_ca_signed_csrs` — ključ nastaje na ciljnom hostu

Server sam pravi privatni ključ i zahtev (CSR). Na CA host stiže samo CSR, vraća se potpisan sertifikat. **Privatni ključ nikada ne napušta host kojem pripada** i nikada ne prolazi kroz kontrolni čvor.

Ovo je bolji tok i treba mu dati prednost svuda gde je izvodljiv.

Cena: ekstenzije sertifikata dolaze iz CSR-a i rola nad njima nema kontrolu. CSR bez `keyUsage` i `extendedKeyUsage` daje sertifikat bez njih.

### `role_root_ca_issued_certs` — ključ nastaje na CA hostu

CA pravi i ključ i sertifikat. Jednostavnije za podešavanje i rola potpuno kontroliše ekstenzije, ali ključ mora nekako stići do servisa — a svaki prenos privatnog ključa je prilika da se izgubi.

Koristi kada ciljni host ne postoji još uvek, kada nema `openssl`, ili kada je reč o kratkotrajnim sertifikatima za testiranje.

---

## Put jednog CSR-a

Kod `signed_csrs` toka fajl prolazi kroz tri sistema. Rola pokriva sredinu, krajevi su ručni:

```text
1. CILJNI SERVER      openssl req → ključ i CSR
                      ključ ostaje ovde, zauvek
                              │
                              ▼  scp (ručno)
2. KONTROLNI ČVOR     production/files/csr/<ime>.csr
                      navodi se u polju src
                              │
                              ▼  rola
3. CA HOST            /root/ca/csr/<ime>.csr
                      /root/ca/certs/<ime>.crt
                              │
                              ▼  rola, ako je fetch uključen
4. KONTROLNI ČVOR     production/files/pki/<ime>.crt
                              │
                              ▼  scp (ručno)
5. CILJNI SERVER      .crt se spaja sa ključem koji je čekao
```

**CSR uvek ide preko kontrolnog čvora.** Direktno spuštanje na CA host nije podržano — ostavljalo bi tamo fajl koji nije opisan nijednom konfiguracijom, pa se stanje CA hosta ne bi moglo rekonstruisati iz `production/` foldera.

Folder `production/files/csr/` napravi ručno ako ne postoji:

```bash
mkdir -p /opt/ansible/production/files/csr
mkdir -p /opt/ansible/production/files/pki
chmod 0700 /opt/ansible/production/files/pki
```

`pki/` mora biti `0700` — kod `issued_certs` unosa se tu spuštaju i privatni ključevi.

---

## Uvoz postojećeg CA

Rola može preuzeti CA napravljen ranije — ručno, starijom verzijom ove role, ili drugim alatom — i nastaviti da izdaje sertifikate istim ključem.

```yaml
role_root_ca_import_enabled: true
role_root_ca_import_remote: true
role_root_ca_import_key_src:  /root/ca/private/ca.key.pem
role_root_ca_import_cert_src: /root/ca/certs/ca.cert.pem
```

`role_root_ca_import_remote: false` (podrazumevano) znači da su putanje na kontrolnom čvoru.

Uvoz je jedino mesto gde rola čita fajl direktno sa CA hosta. To je namerno: reč je o jednokratnoj migraciji sa fajlova koji tamo već postoje godinama, i nema razloga da prođu kroz kontrolni čvor. Kod potpisivanja CSR-ova takve opcije nema.

Uvoz je **jednokratan**. Kada su fajlovi na mestu, sledeći prolaz ne radi ništa — pa `role_root_ca_import_enabled` može ostati uključen bez posledica. Prepisivanje živog CA traži `role_root_ca_import_force: true` i pravu meru opreza.

Rola proverava da uvezeni ključ i sertifikat pripadaju jedno drugom, poređenjem otiska javnog ključa. Neusaglašen par ne bi izazvao grešku pri izdavanju — greška bi se pojavila tek na klijentu, kao odbijen potpis.

### Šta uskladiti posle uvoza

Rola ispisuje identitet i tip ključa uvezenog CA. Prepiši te vrednosti u `group_vars`:

| Ako je uvezeni CA... | Postavi |
|---|---|
| ECC `secp384r1` | `role_root_ca_key_type: ECC`, `role_root_ca_key_curve: secp384r1` |
| potpisan sa SHA-384 | `role_root_ca_digest: sha384` |
| sa drugim CN | `role_root_ca_common_name` na tačnu vrednost |

Bez usklađenog CN-a provera identiteta prekida rad pri sledećem prolazu.

### Zašto se uvezeni sertifikat ne dira

`role_root_ca_preserve_cert` je podrazumevano `true`, pa rola CA sertifikat pravi samo ako ga nema.

Bez toga bi se desilo sledeće: CSR koji rola sastavlja sadrži `pathlen:0` i `subjectKeyIdentifier`. CA napravljen ručno ili starijom verzijom role ih po pravilu nema. Modul `x509_certificate` bi zaključio da se sertifikat i CSR razlikuju i napravio **nov CA sertifikat**. Ključ bi ostao isti i lančanje se ne bi prekinulo, ali bi se `ca.crt` promenio i morao redistribuirati svuda gde je već instaliran.

Posledica: parametri kao `pathlen`, `digest` i `role_root_ca_days` primenjuju se samo na novonapravljen CA. Nad postojećim nemaju efekta dok se `role_root_ca_preserve_cert` ne isključi izričito.

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
│   ├── zabbix.example.com-fullchain.crt
│   ├── app-01.crt              ← iz spoljnog CSR-a, bez ključa
│   └── app-01-fullchain.crt
└── csr/              0755
```

Sertifikati iz oba toka završavaju u istom `certs/` folderu. Rola prekida rad ako se imena poklapaju.

Sadržaj `fullchain` fajla je krajnji sertifikat pa CA sertifikat, tim redom. Obrnut redosled Nginx prihvata bez greške pri startu, ali servira CA kao krajnji sertifikat i klijenti odbijaju vezu.

---

## Varijable

### Aktivacija i lokacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_root_ca_dir` | `/root/ca` | Koren CA foldera. |
| `role_root_ca_basename` | `ca` | Osnovno ime CA fajlova. |

### Uvoz postojećeg CA

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_import_enabled` | `false` | Uključuje uvoz. |
| `role_root_ca_import_remote` | `false` | `true` = izvor je na CA hostu, `false` = na kontrolnom čvoru. |
| `role_root_ca_import_key_src` | `""` | Putanja do postojećeg CA ključa. |
| `role_root_ca_import_cert_src` | `""` | Putanja do postojećeg CA sertifikata. |
| `role_root_ca_import_force` | `false` | Prepisuje postojeći CA. **Opasno.** |

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
| `role_root_ca_preserve_cert` | `true` | Ne dira postojeći CA sertifikat. |

### Ključ CA

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_key_type` | `RSA` | `RSA` ili `ECC`. |
| `role_root_ca_key_size` | `4096` | Za RSA. |
| `role_root_ca_key_curve` | `secp384r1` | Za ECC. |
| `role_root_ca_digest` | `sha256` | Algoritam potpisa. |
| `role_root_ca_key_regenerate` | `never` | Zaštita od nenamernog pravljenja novog ključa. |

### Sertifikati koje CA izdaje (`issued_certs`)

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_issued_certs` | `[]` | Lista sertifikata. |
| `role_root_ca_cert_days` | `397` | Važenje. |
| `role_root_ca_cert_key_type` | `RSA` | Tip ključa. |
| `role_root_ca_cert_key_size` | `2048` | Za RSA. |
| `role_root_ca_cert_key_curve` | `secp256r1` | Za ECC. |
| `role_root_ca_cert_extended_key_usage` | `[serverAuth]` | Namena. |
| `role_root_ca_cert_key_usage` | `[digitalSignature, keyEncipherment]` | Namena ključa. |
| `role_root_ca_cert_subject_from_ca` | `true` | Preuzima C/ST/L/O/OU iz CA. |
| `role_root_ca_cert_owner` | `root` | Vlasnik fajlova. |
| `role_root_ca_cert_group` | `root` | Grupa fajlova. |
| `role_root_ca_cert_key_mode` | `'0640'` | Dozvole nad privatnim ključem. |
| `role_root_ca_cert_mode` | `'0644'` | Dozvole nad sertifikatom. |

### Potpisivanje spoljnih CSR-ova (`signed_csrs`)

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_signed_csrs` | `[]` | Lista zahteva za potpisivanje. |
| `role_root_ca_signed_days` | `397` | Važenje. |
| `role_root_ca_signed_owner` | `root` | Vlasnik sertifikata. |
| `role_root_ca_signed_group` | `root` | Grupa sertifikata. |
| `role_root_ca_signed_mode` | `'0644'` | Dozvole. Privatnog ključa ovde nema. |

### Zajedničko za oba toka

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_renew_before_days` | `30` | Obnova pred istek. `0` isključuje. |
| `role_root_ca_fullchain` | `true` | Upisuje `<ime>-fullchain.crt`. |
| `role_root_ca_fetch_enabled` | `false` | Preuzima sertifikate na kontrolni čvor. |
| `role_root_ca_fetch_dir` | `/opt/ansible/production/files/pki` | Ciljni folder. |

### Ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_root_ca_trust_local` | `false` | Upisuje CA u trust store **ovog** hosta. |
| `role_root_ca_trust_filename` | `internal-root-ca` | Ime fajla u trust store-u. |
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
| `filename` | ne | Osnovno ime fajlova; podrazumevano se izvodi iz `cn`. |
| `days` | ne | Važenje. |
| `key_type`, `key_size`, `key_curve` | ne | Nadjačavaju globalne. |
| `owner`, `group`, `key_mode`, `mode` | ne | Vlasništvo i dozvole. |
| `key_usage`, `extended_key_usage` | ne | Namena. |

## Struktura unosa u `role_root_ca_signed_csrs`

| Polje | Obavezno | Opis |
|---|---|---|
| `filename` | da | Osnovno ime fajlova. |
| `src` | da, osim kod `absent` | **Apsolutna** putanja do CSR-a na kontrolnom čvoru. |
| `state` | ne | `present` (podrazumevano) ili `absent`. |
| `days` | ne | Važenje. |
| `owner`, `group`, `mode` | ne | Vlasništvo i dozvole nad sertifikatom. |

Nema `cn` ni `sans` — te vrednosti dolaze iz samog CSR-a.

Putanja u `src` mora biti apsolutna. Relativnu modul `copy` traži unutar repozitorijuma, čime bi konfiguracija završila u kodu.

### Ograničenje za `filename`

Vrednost ulazi pravo u putanju (`<certs_dir>/<filename>.crt`), pa su dozvoljeni samo slova, cifre, tačka, crta i donja crta, uz slovo ili cifru na početku. Kose crte i `..` pisali bi izvan CA foldera; rola takav unos odbija.

Isto važi i za `filename` u `issued_certs`, kao i za ime izvedeno iz `cn`. Za wildcard CN zadaj `filename` ručno — izvedeno ime bi sadržalo zvezdicu.

---

## Primeri

### 1. Prvo pokretanje — CA i dva sertifikata

Ceo tok od praznog servera do sertifikata na disku.

**`inventory/hosts.ini`**

```ini
[deploy_root_ca]
srv-ca-01
```

**`inventory/group_vars/all.yml`** (samo deo koji se tiče ove role)

```yaml
role_root_ca_common_name: "Example Root CA"
role_root_ca_organization: "Example d.o.o."
role_root_ca_country: "RS"
role_root_ca_locality: "Beograd"

role_root_ca_issued_certs:
  - cn: zabbix.example.com
  - cn: wiki.example.com
```

**Pokretanje**

```bash
cd /opt/ansible/production
./apply.sh --limit srv-ca-01 --check --diff   # pregled
./apply.sh --limit srv-ca-01                  # primena
```

**Rezultat na `srv-ca-01`**

```text
/root/ca/private/ca.key                            0600
/root/ca/private/zabbix.example.com.key            0640
/root/ca/private/wiki.example.com.key              0640
/root/ca/certs/ca.crt
/root/ca/certs/zabbix.example.com.crt
/root/ca/certs/zabbix.example.com-fullchain.crt
/root/ca/certs/wiki.example.com.crt
/root/ca/certs/wiki.example.com-fullchain.crt
```

Svaki sertifikat dobija SAN `DNS:<cn>` automatski i važi 397 dana. CA važi 20 godina.

**Provera**

```bash
ansible srv-ca-01 -m command -a \
  "openssl verify -CAfile /root/ca/certs/ca.crt /root/ca/certs/zabbix.example.com.crt"
```

---

### 2. Sertifikat za Nginx — potpisivanje spoljnog CSR-a

Privatni ključ nastaje na `app-01` i tamo ostaje. Preporučen tok.

**Korak 1 — na `app-01`, ključ i zahtev**

```bash
openssl req -new -newkey rsa:2048 -nodes \
  -keyout /etc/ssl/private/app-01.key \
  -out /tmp/app-01.csr \
  -subj "/CN=app-01.example.com" \
  -addext "subjectAltName=DNS:app-01.example.com,DNS:app.example.com,IP:10.0.0.11" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"

chown root:www-data /etc/ssl/private/app-01.key
chmod 0640 /etc/ssl/private/app-01.key
```

Proveri šta si napravio pre nego što pošalješ:

```bash
openssl req -in /tmp/app-01.csr -noout -text | grep -A5 "Requested Extensions"
```

**Korak 2 — prenos na kontrolni čvor**

```bash
scp app-01:/tmp/app-01.csr /opt/ansible/production/files/csr/
```

**Korak 3 — `inventory/group_vars/all.yml`**

```yaml
role_root_ca_signed_csrs:
  - src: /opt/ansible/production/files/csr/app-01.csr
    filename: app-01

role_root_ca_fetch_enabled: true
role_root_ca_fetch_dir: /opt/ansible/production/files/pki
```

**Korak 4 — potpisivanje**

```bash
./apply.sh --limit srv-ca-01
```

Na kontrolnom čvoru se pojavljuju `files/pki/app-01.crt` i `files/pki/app-01-fullchain.crt`.

**Korak 5 — nazad na `app-01`**

```bash
scp /opt/ansible/production/files/pki/app-01-fullchain.crt \
    app-01:/etc/ssl/certs/
```

**Nginx**

```nginx
ssl_certificate      /etc/ssl/certs/app-01-fullchain.crt;
ssl_certificate_key  /etc/ssl/private/app-01.key;
```

Nginx traži sertifikat i CA u jednom fajlu — zato `fullchain`. Apache koristi odvojene, pa se tamo prenosi `app-01.crt` uz `SSLCertificateChainFile` koji pokazuje na `ca.crt`.

**Provera na `app-01`**

```bash
nginx -t && systemctl reload nginx
openssl s_client -connect app-01.example.com:443 -CAfile /usr/local/share/ca-certificates/internal-root-ca.crt </dev/null
```

Poslednja linija izlaza treba da glasi `Verify return code: 0 (ok)`.

---

### 3. Poverenje na ostalim hostovima

Sertifikat ne vredi ništa ako klijent ne veruje CA. `ca.crt` se distribuira zasebno.

**Preuzimanje na kontrolni čvor**

```yaml
role_root_ca_fetch_enabled: true
```

Posle prolaza `ca.crt` je u `/opt/ansible/production/files/pki/ca.crt`.

**Distribucija ad-hoc komandom**

```bash
ansible all -m copy -a \
  "src=/opt/ansible/production/files/pki/ca.crt \
   dest=/usr/local/share/ca-certificates/internal-root-ca.crt \
   owner=root group=root mode=0644" --become

ansible all -m command -a "update-ca-certificates" --become
```

Ekstenzija **mora** biti `.crt` — `update-ca-certificates` ignoriše sve ostalo, bez poruke.

**Na samom CA hostu**

```yaml
role_root_ca_trust_local: true
```

Odnosi se samo na taj host; ostali i dalje idu kroz distribuciju.

**Provera**

```bash
ansible all -m shell -a \
  "openssl verify /usr/local/share/ca-certificates/internal-root-ca.crt"
```

---

### Kraći isečci

**Više imena i IP adresa**

```yaml
role_root_ca_issued_certs:
  - cn: www.example.com
    sans:
      - "DNS:example.com"
      - "DNS:www2.example.com"
      - "IP:10.0.0.10"
```

**Sertifikat koji čita servis**

```yaml
role_root_ca_issued_certs:
  - cn: zabbix.example.com
    owner: root
    group: www-data
    key_mode: '0640'
```

Nginx čita ključ preko grupe. Dozvole se ne otvaraju na `0644` — privatni ključ ne sme biti čitljiv svakom nalogu na sistemu.

**Wildcard**

```yaml
role_root_ca_issued_certs:
  - cn: "*.apps.example.com"
    filename: wildcard-apps
```

`filename` je ovde obavezan — izvedeno ime bi sadržalo zvezdicu.

**Klijentski sertifikat**

```yaml
role_root_ca_issued_certs:
  - cn: klijent-01
    extended_key_usage:
      - clientAuth
```

**Uklanjanje**

```yaml
role_root_ca_issued_certs:
  - cn: stari.example.com
    state: absent

role_root_ca_signed_csrs:
  - filename: ukinut
    state: absent
```

Brišu se fajlovi na CA hostu. Kopije koje su već distribuirane ostaju upotrebljive do isteka — rola ne vodi CRL.

---

## Napomene

**Privatni ključ CA je najosetljiviji podatak u okruženju.** Ko dođe do njega može izdati sertifikat za bilo koje ime kojem ovi sistemi veruju — uključujući i imena koja nikada nisu bila izdata. Folder je `0700`, ključ `0600`, i ne napušta host.

**Subject polja se ne menjaju posle prvog pokretanja.** Promena bi napravila nov CA sa istim ključem ali drugim izdavačem, i svi ranije izdati sertifikati prestali bi da se lančaju. Rola poredi konfiguraciju sa postojećim sertifikatom i prekida rad. Zamena CA je svesna operacija: arhiviraj folder, obriši ga ručno, pokreni rolu ponovo, pa redistribuiraj `ca.crt` na sve klijente.

**Common Name se više ne gleda.** Od Chrome 58 i ekvivalentnih verzija ostalih klijenata validacija ide isključivo preko SAN-a. Sertifikat bez SAN unosa za sopstveni CN biva odbijen porukom koja ne upućuje na uzrok. Kod `issued_certs` rola `DNS:<cn>` dodaje sama; kod `signed_csrs` prekida rad ako CSR nema SAN.

**Kod spoljnih CSR-ova rola ne bira ekstenzije.** `keyUsage`, `extendedKeyUsage` i `basicConstraints` preuzimaju se iz zahteva onako kako ih je napravila druga strana. CSR bez njih daje sertifikat bez njih. Rola upozorava kada `extendedKeyUsage` nedostaje, ali ga ne može dopuniti — to bi značilo menjanje zahteva, a onda potpis više ne bi bio potvrda onoga što je traženo.

**Sistemski trust store ne pokriva sve.** `update-ca-certificates` menja OpenSSL i GnuTLS. Java (`cacerts`), NSS (Firefox, Chrome), Python (`certifi`) i Node imaju sopstvene. Zabbix Java gateway i `pip` su najčešći primeri gde poverenje i dalje ne radi iako je CA uredno instaliran.

**`pathlen:0`.** CA može potpisivati samo krajnje sertifikate, ne i posredne CA. Ako ti treba dvostepena hijerarhija, promeni vrednost u `tasks/main.yml` — ali onda je i izdavanje posrednog CA posao koji ova rola ne pokriva.

**Rola ne vodi CRL.** Nema `index.txt`, nema evidencije izdatih sertifikata, nema osnove za povlačenje. `state: absent` briše fajlove sa CA hosta, ali ne povlači sertifikat — ko ga već ima, koristi ga do isteka. Zato je podrazumevano važenje 397 dana, a ne nekoliko godina: kraće važenje je jedini mehanizam povlačenja koji ova rola ima.

**Obnova zadržava ključ.** Menja se samo `.crt` fajl. Kod `signed_csrs` unosa isti CSR se potpisuje iznova — na ciljnom hostu se ne mora dirati ništa osim preuzimanja novog sertifikata.

**Rola ne restartuje servise koji koriste sertifikate.** Obnovljen sertifikat počinje da važi tek kada ga servis ponovo pročita. To pripada roli koja tim servisom upravlja.

**`not_before` je pomeren dan unazad.** Sertifikat koji „još ne važi" je česta i neočekivana greška u okruženjima bez NTP-a.

**Rola nije predviđena za `--check`.** Kod `signed_csrs` toka `copy` u check režimu ne upiše CSR, pa sledeći korak puca na nepostojećoj putanji. `--check` radi kada je ta lista prazna.

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
    ├── import.yml
    ├── issue.yml
    └── sign.yml
```

`issue.yml` i `sign.yml` se uključuju petljom po unosu. Po unosu ide više koraka koji moraju ići redom — paralelne petlje nad istom listom bile bi kraće, ali neuporedivo teže za čitanje.

---

## Idempotentnost

Rola je idempotentna. Moduli `openssl_privatekey`, `openssl_csr` i `x509_certificate` porede postojeće stanje sa zadatim parametrima i menjaju samo pri razlici.

Slučajevi u kojima je `changed` očekivan:

- sertifikat ulazi u prozor obnove (`role_root_ca_renew_before_days`)
- promenjena je `sans` lista ili drugo polje CSR-a
- promenjen je sadržaj spoljnog CSR-a

Ključevi se ne generišu ponovo ni u jednom slučaju (`regenerate: never`).

Uvoz je idempotentan jer se izvršava samo kada ciljni fajlovi ne postoje.

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
  "openssl x509 -noout -pubkey -in /root/ca/certs/zabbix.example.com.crt | openssl md5; \
   openssl pkey -noout -pubout -in /root/ca/private/zabbix.example.com.key | openssl md5"

# Redosled u fullchain fajlu — prvi subject mora biti krajnji sertifikat
ansible srv-ca-01 -m shell -a \
  "openssl crl2pkcs7 -nocrl -certfile /root/ca/certs/app-01-fullchain.crt \
   | openssl pkcs7 -print_certs -noout | grep subject"

# Sadržaj spoljnog CSR-a pre nego što se pošalje
openssl req -in app-01.csr -noout -text | grep -A3 "Requested Extensions"
```

Poređenje heševa mora dati dve identične vrednosti. Različite znače da su ključ i sertifikat iz različitih generisanja. (Varijanta sa `-modulus` radi samo za RSA; `-pubkey`/`-pubout` radi i za ECC.)

---

## Rešavanje problema

**`assert` prijavljuje da se identitet CA promenio**

Neko od subject polja se razlikuje od onoga u postojećem `ca.crt`. Vrati staru vrednost, ili — ako je zamena CA namera — arhiviraj i obriši `/root/ca`.

Posle uvoza starog CA ovo je očekivano: prepiši `role_root_ca_common_name` na vrednost koju rola ispisuje u koraku uvoza.

**`CHANGEME` u poruci greške**

`role_root_ca_common_name` ili `role_root_ca_organization` nisu popunjeni. Upiši ih u `group_vars/all.yml`.

**Grupa sadrži više hostova**

Ostavi jedan. Ako zaista vodiš više odvojenih CA, `role_root_ca_allow_multiple_hosts: true` — ali proveri da li ti to stvarno treba.

**„Polje remote_src više nije podržano"**

Konfiguracija je pisana za raniju verziju role. Prenesi CSR sa CA hosta na kontrolni čvor i zameni polje:

```bash
scp srv-ca-01:/tmp/ime.csr /opt/ansible/production/files/csr/
```

```yaml
- src: /opt/ansible/production/files/csr/ime.csr
  filename: ime
```

**„Ime fajla nije ispravno"**

`filename` sadrži kosu crtu, `..`, ili počinje tačkom. Dozvoljeni su slova, cifre, tačka, crta i donja crta.

**„Uvezeni CA ključ i sertifikat NE pripadaju jedno drugom"**

Naveo si ključ iz jednog generisanja i sertifikat iz drugog. Proveri ručno:

```bash
openssl x509 -noout -pubkey -in ca.cert.pem | openssl md5
openssl pkey -noout -pubout -in ca.key.pem  | openssl md5
```

**Uvoz kaže da se preskače, a CA nije prenet**

U `/root/ca` već postoje `private/ca.key` i `certs/ca.crt` — verovatno ih je rola napravila u ranijem prolazu, pre nego što je uvoz podešen. Arhiviraj folder, obriši ga, pa pokreni ponovo. `role_root_ca_import_force: true` radi isto, ali bez arhive.

**CA sertifikat se ne menja iako sam promenio `role_root_ca_days`**

`role_root_ca_preserve_cert` je uključen — postojeći CA sertifikat se ne dira. To je namerno. Za ponovno pravljenje postavi `role_root_ca_preserve_cert: false`, ali imaj u vidu da se `ca.crt` menja i mora redistribuirati.

**„CSR nema subjectAltName"**

Zahtev je napravljen bez `-addext "subjectAltName=..."`. Ponovi ga na strani servera; ključ ne mora da se menja:

```bash
openssl req -new -key /etc/ssl/private/app-01.key \
  -out /tmp/app-01.csr \
  -subj "/CN=app-01.example.com" \
  -addext "subjectAltName=DNS:app-01.example.com"
```

**`Could not find or access` na `src` putanji**

Putanja je relativna, pa je `copy` traži unutar repozitorijuma. Navedi punu putanju od `/opt/ansible/production/`.

**`ERR_CERT_COMMON_NAME_INVALID` u pregledaču**

Ime kojim pristupaš nije u SAN listi. Kod `issued_certs` dodaj ga u `sans`. Kod `signed_csrs` napravi nov CSR sa ispravnim SAN-om — rola će ga potpisati pri sledećem prolazu.

**Klijent i dalje ne veruje CA**

Sertifikat nije u trust store-u tog klijenta, ili klijent ima svoj. Redom:

```bash
ls /usr/local/share/ca-certificates/
openssl s_client -connect zabbix.example.com:443 -CAfile /put/do/ca.crt
```

Za Javu, Firefox, `pip` i Node vidi napomenu o odvojenim trust store-ovima.

**`Unable to load private key`**

Servis nema pravo čitanja ključa. Kod `issued_certs` proveri `owner`, `group` i `key_mode` tog unosa. Kod `signed_csrs` ključ je pravio sam server — dozvole su njegova stvar, rola ih ne dira.

**Rola prijavljuje `changed` pri svakom pokretanju**

Najčešće se `sans` lista razlikuje po redosledu između pokretanja — proveri da nije generisana kroz Jinja izraz koji vraća nesortiran skup.

**`ModuleNotFoundError: cryptography`**

`role_root_ca_install_dependencies` je isključen a paket nije instaliran ručno:

```bash
apt install python3-cryptography
```
