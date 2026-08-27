# Rola: zabbix_web

Instalira i konfiguriše Zabbix web frontend na **Nginx-u**, sa opcionim HTTPS-om.

Rola upisuje `zabbix.conf.php` i time **preskače čarobnjak** koji se inače pojavljuje pri prvom otvaranju frontenda.

Apache više nije podržan.

---

## Preduslovi

| Preduslov | Ko ga rešava |
|---|---|
| Zabbix repozitorijum | rola `repos`, grupa `[apply_repos]` |
| Baza sa uvezenom šemom | rola `zabbix_db`, grupa `[deploy_zabbix_db]` |
| Port otvoren | rola `firewall`, grupa `[apply_firewall]` |
| Kolekcija `community.crypto` | samo uz automatski self-signed sertifikat |

```bash
ansible-galaxy collection install community.crypto
```

**Frontend čita bazu direktno**, ne kroz Zabbix server. Mora imati mrežni pristup do baze, a ne samo do servera. Serveru se javlja samo za pojedine radnje — izvršavanje skripti i proveru dostupnosti.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_web]
srv-web-01
```

Grupi pripada `group_vars/deploy_zabbix_web.yml`, koji postavlja `role_zabbix_web_enabled: true`.

---

## Obavezna konfiguracija

Samo lozinka baze. Koji je to nalog zavisi od toga da li rola `zabbix_db` ima uključen zaseban nalog za frontend:

```yaml
# host_vars/srv-web-01.yml — zaseban nalog za frontend
role_zabbix_web_db_user: "zabbix_web"
role_zabbix_web_db_password: "druga-lozinka"
```

---

## HTTPS

Uključuje se jednom varijablom:

```yaml
role_zabbix_web_https_enabled: true
role_zabbix_web_https_port: 443
role_zabbix_web_listen_port: 80
role_zabbix_web_hostname: "zabbix.example.com"
```

Sertifikat i ključ rola traži na `role_zabbix_web_tls_cert` i `role_zabbix_web_tls_key`.

**Rola ne prima sadržaj sertifikata ni ključa kroz varijable** — svesna odluka. Privatni ključ ne prolazi kroz Ansible varijable. Materijal se donosi na host van ove role, a rola ga samo koristi. Ostaju dva načina.

### 1. Fajlovi već postoje na hostu

Postavila ih je rola `root_ca`, doneti su ručno, isporučio ih je ACME klijent, ili ih je ova rola napravila ranije. Rola ih tada **samo koristi i ne dira**.

```yaml
role_zabbix_web_tls_cert: /root/ca/certs/zabbix-frontend-fullchain.crt
role_zabbix_web_tls_key: /root/ca/private/zabbix-frontend.key
```

### 2. Automatski self-signed

Kada **nijedan** od dva fajla ne postoji, rola pravi privremeni self-signed sertifikat, tako da frontend odmah radi preko HTTPS-a. Podrazumevano uključeno.

```yaml
role_zabbix_web_tls_selfsigned: true
role_zabbix_web_tls_selfsigned_cn: "zabbix.example.com"
role_zabbix_web_tls_selfsigned_sans:
  - "IP:10.0.0.60"
  - "DNS:srv-web-01"
role_zabbix_web_tls_selfsigned_days: 397
```

CN podrazumevano prati `role_zabbix_web_hostname`, a kada je on `_` pada na ime hosta iz inventory-ja. SAN unos za sam CN rola dodaje sama — kao `IP:` ako je CN IPv4 adresa, inače kao `DNS:`. U `role_zabbix_web_tls_selfsigned_sans` ide samo ono dodatno.

> Pretraživač će prijavljivati grešku koju korisnik mora ručno preskočiti. Ovo je polazna tačka, ne rešenje.

**Prelazak na pravi sertifikat** ne traži nikakvu izmenu konfiguracije. Prekopiraj fajlove preko postojećih i restartuj Nginx:

```bash
sudo cp fullchain.pem /etc/ssl/certs/zabbix-frontend-fullchain.pem
sudo cp privkey.pem /etc/ssl/private/zabbix-frontend.key
sudo chmod 0600 /etc/ssl/private/zabbix-frontend.key
sudo nginx -t && sudo systemctl reload nginx
```

Rola ih neće prepisati, jer nove pravi isključivo kada **oba** fajla nedostaju.

---

## Varijable

### Aktivacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_web_version` | `""` | Zakovana verzija. Prazno = najnovija. |

### Baza

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_db_host` | `localhost` | Adresa baze. |
| `role_zabbix_web_db_port` | `3306` | Port. |
| `role_zabbix_web_db_name` | `zabbix` | Ime baze. |
| `role_zabbix_web_db_user` | `zabbix` | Nalog. |
| `role_zabbix_web_db_password` | `""` | **Obavezno.** |
| `role_zabbix_web_db_backend` | `mysql` | `mysql` ili `pgsql`. |

### Zabbix server

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_server_host` | `localhost` | Adresa Zabbix servera. |
| `role_zabbix_web_server_port` | `10051` | Port servera. |
| `role_zabbix_web_server_name` | `""` | Naziv u zaglavlju frontenda. |

### Mreža

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_listen_port` | `8080` | HTTP port. |
| `role_zabbix_web_hostname` | `_` | `server_name`. Uz HTTPS mora biti stvarno ime. |
| `role_zabbix_web_listen_address` | `""` | Prazno = sve adrese. |

### HTTPS

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_https_enabled` | `false` | Uključuje TLS. |
| `role_zabbix_web_https_port` | `8443` | HTTPS port. |
| `role_zabbix_web_http_redirect` | `true` | Preusmerava HTTP na HTTPS. |
| `role_zabbix_web_tls_cert` | `/etc/ssl/certs/zabbix-frontend-fullchain.pem` | Putanja do punog lanca. |
| `role_zabbix_web_tls_key` | `/etc/ssl/private/zabbix-frontend.key` | Putanja do privatnog ključa. |
| `role_zabbix_web_tls_protocols` | `TLSv1.2 TLSv1.3` | Dozvoljene verzije. |
| `role_zabbix_web_tls_ciphers` | Mozilla intermediate | Spisak šifri. |
| `role_zabbix_web_http2` | `true` | HTTP/2. Sintaksa se bira prema verziji Nginx-a. |
| `role_zabbix_web_hsts_enabled` | `false` | HSTS zaglavlje. Vidi napomene. |
| `role_zabbix_web_hsts_max_age` | `31536000` | Sekunde. Godina dana. |

### Automatski self-signed

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_tls_selfsigned` | `true` | Pravi sertifikat kada oba fajla nedostaju. |
| `role_zabbix_web_tls_selfsigned_cn` | prati `hostname` | Common Name. |
| `role_zabbix_web_tls_selfsigned_sans` | `[]` | **Dodatni** SAN unosi. Za CN se dodaje sam. |
| `role_zabbix_web_tls_selfsigned_org` | `""` | Organizacija. Prazno = ne upisuj. |
| `role_zabbix_web_tls_selfsigned_days` | `397` | Važenje. |
| `role_zabbix_web_tls_selfsigned_key_size` | `2048` | Dužina RSA ključa. |
| `role_zabbix_web_tls_dependency_packages` | `[python3-cryptography]` | Zavisnosti za rad sa sertifikatima. |

### PHP

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_php_max_execution_time` | `300` | Sekunde. Minimum koji Zabbix traži. |
| `role_zabbix_web_php_memory_limit` | `128M` | Minimum. |
| `role_zabbix_web_php_post_max_size` | `16M` | Minimum. |
| `role_zabbix_web_php_upload_max_filesize` | `2M` | Minimum. |
| `role_zabbix_web_php_max_input_time` | `300` | Sekunde. |
| `role_zabbix_web_php_timezone` | `Europe/Belgrade` | Utiče na prikaz vremena. |

### Ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_extra_config` | `""` | Proizvoljne PHP linije u `zabbix.conf.php`. |
| `role_zabbix_web_nginx_extra_config` | `""` | Proizvoljne Nginx direktive u `server` bloku. |
| `role_zabbix_web_service_enabled` | `true` | Startuje uz sistem. |
| `role_zabbix_web_service_state` | `started` | `started`, `stopped`. |

---

## Primeri

### Najbrži put do HTTPS-a

```yaml
# host_vars/srv-web-01.yml
role_zabbix_web_db_password: "druga-lozinka"

role_zabbix_web_hostname: "zabbix.example.com"
role_zabbix_web_https_enabled: true
role_zabbix_web_https_port: 443
role_zabbix_web_listen_port: 80

role_firewall_rules:
  - { rule: allow, port: 443, proto: tcp, comment: "Zabbix frontend HTTPS" }
  - { rule: allow, port: 80, proto: tcp, comment: "Preusmeravanje na HTTPS" }
```

Ništa oko sertifikata — rola pravi self-signed za `zabbix.example.com`.

### Sertifikat iz role `root_ca` na istom hostu

```yaml
role_root_ca_issued_certs:
  - cn: "zabbix.example.com"
    filename: zabbix-frontend

role_zabbix_web_https_enabled: true
role_zabbix_web_hostname: "zabbix.example.com"
role_zabbix_web_tls_cert: /root/ca/certs/zabbix-frontend-fullchain.crt
role_zabbix_web_tls_key: /root/ca/private/zabbix-frontend.key
```

U `playbook.yml` `deploy_root_ca` mora ići pre `deploy_zabbix_web`.

### Frontend na IP adresi

```yaml
role_zabbix_web_hostname: "10.0.0.60"
role_zabbix_web_https_enabled: true
role_zabbix_web_tls_selfsigned_sans:
  - "DNS:srv-web-01"
```

CN je IP adresa, pa rola sama upisuje `IP:10.0.0.60` u SAN.

### Rola ne sme improvizovati

```yaml
role_zabbix_web_tls_selfsigned: false
```

Kada fajlova nema, rola prekida rad umesto da napravi privremeni sertifikat.

### Ograničavanje pristupa po mreži

```yaml
role_zabbix_web_nginx_extra_config: |
  allow 10.0.0.0/8;
  deny all;
```

---

## Napomene

**Čarobnjak se preskače.** Kada `zabbix.conf.php` postoji i sadrži ispravne podatke, frontend odmah prikazuje ekran za prijavu. Podrazumevani nalog je `Admin` sa lozinkom `zabbix` — **promeni je odmah po prvoj prijavi.**

**Rola ne unosi TLS materijal kroz varijable.** Privatni ključ ne prolazi kroz Ansible — ne završava u `host_vars`, ne prolazi kroz templating, ne pojavljuje se u izlazu. Sertifikat i ključ se donose na host nezavisno od ove role, ili ih rola napravi sama kao privremene.

**Self-signed se pravi samo kada oba fajla nedostaju.** Čim jedan postoji, rola ne pravi ništa — inače bi ručno donet sertifikat bio prepisan pri sledećem pokretanju. Ako postoji tačno jedan fajl, rola prekida rad, jer je to gotovo uvek trag prekinutog ranijeg pokušaja.

**SAN je obavezan, CN se ne gleda.** Od Chrome 58 i ekvivalentnih verzija ostalih klijenata validacija ide isključivo preko SAN-a. Rola zato unos za sam CN dodaje sama.

**HSTS i self-signed se ne trpe.** Greška sertifikata uz aktivan HSTS se u većini pretraživača **ne može preskočiti**. Ostavi HSTS isključen dok ne dobiješ sertifikat kojem klijenti veruju.

**Verzija PHP-a se otkriva iz sistema.** Ubuntu 22.04 isporučuje PHP 8.1, 24.04 isporučuje 8.3. Rola pokreće `php -r` umesto da verziju zakuje.

**Sintaksa za HTTP/2 se menjala.** Do Nginx 1.25.0 ide kao parametar direktive `listen`, od 1.25.1 kao zasebna direktiva `http2 on`. Rola otkriva verziju i bira ispravnu — Ubuntu 24.04 isporučuje 1.24.0, dakle staru.

**`fastcgi_param HTTPS on`** se dodaje samo uz TLS. Bez toga PHP ne zna da je veza šifrovana, pa Zabbix ne postavlja `secure` zastavicu na kolačić sesije.

**Konfiguracija se proverava pre restarta.** Rola pokreće `nginx -t` posle upisa vhost-a. Greška prekida rolu pre nego što obori web server koji do tada radi.

**Privatni ključ ima dozvole `0600` i vlasnika `root`.** Nginx master proces radi kao root i čita ga pre nego što spusti privilegije radnih procesa. Taskovi koji ga dodiruju imaju `no_log: true`.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servise. Self-signed sertifikat se ne pravi ponovo — ni pri isteku. Obnova je ručna: obriši oba fajla i pusti rolu.

---

## Struktura

```text
roles/zabbix_web/
├── README.md
├── defaults/main.yml
├── vars/main.yml
├── handlers/main.yml
├── tasks/main.yml
└── templates/
    ├── zabbix.conf.php.j2
    ├── nginx.conf.j2
    └── zabbix-php.ini.j2
```

---

## Provera

```bash
./apply.sh --limit srv-web-01

# Stanje servisa
ansible srv-web-01 -m command -a "systemctl status nginx"
ansible srv-web-01 -m shell -a "systemctl status php*-fpm"

# Da li konfiguracija prolazi
ansible srv-web-01 -m command -a "nginx -t" --become

# Šta Nginx sluša
ansible srv-web-01 -m command -a "ss -lntp sport = :443"
```

Sertifikat na hostu:

```bash
# Ko ga je izdao, kome glasi, dokle važi
sudo openssl x509 -in /etc/ssl/certs/zabbix-frontend-fullchain.pem \
  -noout -subject -issuer -dates

# SAN
sudo openssl x509 -in /etc/ssl/certs/zabbix-frontend-fullchain.pem \
  -noout -text | grep -A1 "Subject Alternative Name"
```

Ako su `subject` i `issuer` isti, sertifikat je self-signed.

Sa kontrolnog čvora:

```bash
openssl s_client -connect zabbix.example.com:443 -servername zabbix.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

curl -sI http://zabbix.example.com/ | head -3
curl -kIs https://zabbix.example.com/ | head -3
```

---

## Rešavanje problema

### `Postoji samo jedan od dva TLS fajla`

Prethodni pokušaj je prekinut na pola, ili je neko doneo samo sertifikat. Donesi i drugi fajl, ili obriši preostali:

```bash
sudo rm -f /etc/ssl/private/zabbix-frontend.key
```

pa pusti rolu ponovo — napraviće nov par.

### Self-signed sertifikat je istekao

Rola ga ne obnavlja sama. Obriši oba fajla i pusti rolu:

```bash
sudo rm -f /etc/ssl/certs/zabbix-frontend-fullchain.pem \
           /etc/ssl/private/zabbix-frontend.key
```

### `nginx -t` prijavljuje `cannot load certificate`

Ako je poruka `PEM_read_bio_X509_AUX`, fajl nije u PEM formatu — verovatno je DER ili PKCS#12:

```bash
openssl x509 -inform DER -in cert.der -out cert.pem
openssl pkcs12 -in cert.pfx -nocerts -nodes -out key.pem
```

### Pretraživač prijavljuje nepoznatog izdavaoca

Očekivano uz self-signed. Uz sertifikat iz sopstvenog CA znači da lanac nije pun:

```bash
grep -c "BEGIN CERTIFICATE" /etc/ssl/certs/zabbix-frontend-fullchain.pem
```

Očekuje se najmanje 2. Spoj ih:

```bash
cat host.crt ca.crt > fullchain.pem
```

### Pretraživač prijavljuje neslaganje imena

`role_zabbix_web_hostname` se razlikuje od SAN vrednosti u sertifikatu. Uz automatski self-signed to znači da je `hostname` promenjen posle pravljenja sertifikata — obriši oba fajla i pusti rolu ponovo.

### Beskonačno preusmeravanje

Reverse proxy ispred već završava TLS i prosleđuje HTTP, a ovaj vhost opet preusmerava:

```yaml
role_zabbix_web_http_redirect: false
role_zabbix_web_https_enabled: false
```

### Pojavljuje se čarobnjak umesto ekrana za prijavu

`zabbix.conf.php` ne postoji ili PHP ne može da ga pročita. Očekuje se `root:www-data` sa `0640`.

### `Database error: Connection to database failed`

Proveri da lozinka i ime naloga odgovaraju roli `zabbix_db`, i da `role_zabbix_db_frontend_hosts` pokriva IP ovog hosta.

### `Zabbix server is not running`

Frontend radi, ali ne može do servera na portu 10051. Proveri `role_zabbix_web_server_host` i pravilo zaštitnog zida. Ne sprečava pregled podataka — samo radnje koje traže server.

### `502 Bad Gateway`

PHP-FPM nije pokrenut ili socket ne postoji:

```bash
ansible srv-web-01 -m command -a "ls -l /run/php/zabbix.sock"
```

### Odjavljuje me pri svakom osvežavanju stranice

Uz HTTPS iza reverse proxy-ja koji ne prosleđuje `X-Forwarded-Proto`, Zabbix postavi `secure` kolačić koji pretraživač ne vraća preko HTTP-a.
