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
| Sertifikat i ključ (uz HTTPS) | rola `root_ca`, ili ručno |

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

```yaml
# host_vars/srv-mon-01.yml — deljen nalog sa serverom
role_zabbix_web_db_user: "zabbix"
role_zabbix_web_db_password: "prva-lozinka"
```

---

## HTTPS

Uključuje se jednom varijablom, ali traži sertifikat i privatni ključ na hostu.

```yaml
# host_vars/srv-web-01.yml
role_zabbix_web_https_enabled: true
role_zabbix_web_https_port: 443
role_zabbix_web_hostname: "zabbix.example.com"

role_zabbix_web_tls_cert: /etc/ssl/certs/zabbix-frontend-fullchain.pem
role_zabbix_web_tls_key: /etc/ssl/private/zabbix-frontend.key
```

Fajlovi mogu doći na dva načina.

**Već postoje na hostu** — postavila ih je rola `root_ca` ili si ih doneo ručno. Rola ih tada samo koristi i proverava da postoje.

**Sadržaj se zada kroz varijable** — rola ih upisuje na zadate putanje:

```yaml
role_zabbix_web_tls_cert_content: |
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----

role_zabbix_web_tls_key_content: |
  -----BEGIN PRIVATE KEY-----
  ...
  -----END PRIVATE KEY-----
```

> Sertifikat mora biti **pun lanac**: prvo sertifikat hosta, pa sertifikat izdavaoca. Sa samo listom sertifikatom pretraživač prijavljuje nepoznatog izdavaoca, iako je CA u sistemskom skladištu poverenja.

> `role_zabbix_web_hostname` mora odgovarati imenu iz sertifikata. Sa podrazumevanim `_` pretraživač uvek prijavljuje neslaganje.

Pravila zaštitnog zida:

```yaml
role_firewall_rules:
  - { rule: allow, port: 443, proto: tcp, from: "10.0.0.0/8", comment: "Zabbix frontend HTTPS" }
  - { rule: allow, port: 8080, proto: tcp, from: "10.0.0.0/8", comment: "Zabbix frontend, preusmeravanje" }
```

Drugo pravilo je potrebno samo dok je `role_zabbix_web_http_redirect: true`.

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
| `role_zabbix_web_tls_cert_content` | `""` | PEM sadržaj. Prazno = fajl već postoji. |
| `role_zabbix_web_tls_key_content` | `""` | PEM sadržaj. **Tajna.** |
| `role_zabbix_web_tls_protocols` | `TLSv1.2 TLSv1.3` | Dozvoljene verzije. |
| `role_zabbix_web_tls_ciphers` | Mozilla intermediate | Spisak šifri. |
| `role_zabbix_web_http2` | `true` | HTTP/2. Sintaksa se bira prema verziji Nginx-a. |
| `role_zabbix_web_hsts_enabled` | `false` | HSTS zaglavlje. Pažljivo — vidi napomene. |
| `role_zabbix_web_hsts_max_age` | `31536000` | Sekunde. Godina dana. |

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

### Sve na jednom hostu, HTTP

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_web_db_password: "prva-lozinka"
role_zabbix_web_server_name: "Monitoring — Produkcija"

role_firewall_rules:
  - { rule: allow, port: 8080, proto: tcp, from: "10.0.0.0/8", comment: "Zabbix frontend" }
```

Frontend je na `http://srv-mon-01:8080`.

### Frontend na zasebnom hostu, HTTPS na 443

```yaml
# host_vars/srv-web-01.yml
role_zabbix_web_db_host: "10.0.0.21"
role_zabbix_web_db_user: "zabbix_web"
role_zabbix_web_db_password: "druga-lozinka"
role_zabbix_web_server_host: "10.0.0.50"

role_zabbix_web_hostname: "zabbix.example.com"
role_zabbix_web_https_enabled: true
role_zabbix_web_https_port: 443
role_zabbix_web_listen_port: 80

role_firewall_rules:
  - { rule: allow, port: 443, proto: tcp, from: "10.0.0.0/8", comment: "Zabbix frontend HTTPS" }
  - { rule: allow, port: 80, proto: tcp, from: "10.0.0.0/8", comment: "Preusmeravanje na HTTPS" }
```

Na hostu baze mora postojati dozvola i za ovaj host:

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_frontend_enabled: true
role_zabbix_db_frontend_password: "druga-lozinka"
role_zabbix_db_frontend_hosts:
  - "10.0.0.60"
```

### Samo HTTPS, bez preusmeravanja

```yaml
role_zabbix_web_https_enabled: true
role_zabbix_web_http_redirect: false
```

Na HTTP portu tada nema ničega.

### Ograničavanje pristupa po mreži

```yaml
role_zabbix_web_nginx_extra_config: |
  allow 10.0.0.0/8;
  deny all;
```

### Stariji klijenti bez TLSv1.3

```yaml
role_zabbix_web_tls_protocols: "TLSv1.2"
```

---

## Napomene

**Čarobnjak se preskače.** Kada `zabbix.conf.php` postoji i sadrži ispravne podatke, frontend odmah prikazuje ekran za prijavu. Podrazumevani nalog je `Admin` sa lozinkom `zabbix` — **promeni je odmah po prvoj prijavi.**

**Verzija PHP-a se otkriva iz sistema.** Ubuntu 22.04 isporučuje PHP 8.1, 24.04 isporučuje 8.3. Rola pokreće `php -r` umesto da verziju zakuje, pa putanja do `conf.d` foldera uvek odgovara.

**Sintaksa za HTTP/2 se menjala.** Do Nginx 1.25.0 ide kao parametar direktive `listen`, od 1.25.1 kao zasebna direktiva `http2 on`. Stara sintaksa na novom Nginx-u ispisuje upozorenje, nova na starom prekida rad. Rola otkriva verziju i bira ispravnu — Ubuntu 24.04 isporučuje 1.24.0, dakle staru.

**HSTS se ne može povući.** Pretraživač pamti zaglavlje `max_age` sekundi bez obzira na to što si opciju u međuvremenu ugasio. Ako sertifikat istekne ili sajt posluži preko HTTP-a, klijenti dobijaju grešku koju ne mogu preskočiti. Uključi tek kada je HTTPS stabilan i sertifikat se pouzdano obnavlja.

**`fastcgi_param HTTPS on`** se dodaje samo uz TLS. Bez toga PHP ne zna da je veza šifrovana, pa Zabbix ne postavlja `secure` zastavicu na kolačić sesije.

**Konfiguracija se proverava pre restarta.** Rola pokreće `nginx -t` posle upisa vhost-a. Greška u konfiguraciji prekida rolu pre nego što obori web server koji do tada radi.

**Privatni ključ ima dozvole `0600` i vlasnika `root`.** Nginx master proces radi kao root i čita ga pre nego što spusti privilegije radnih procesa. Task ima `no_log: true`, pa se ključ ne pojavljuje u ispisu.

**`zabbix.conf.php` sadrži lozinku**, pa ima dozvole `0640` i grupu `www-data`. Task ima `no_log: true`, što znači da `--diff` neće prikazati razliku u tom fajlu.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servise, osim kada se paket ili konfiguracija zaista promene.

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

# Šta Nginx sluša
ansible srv-web-01 -m command -a "ss -lntp sport = :443"

# Da li konfiguracija prolazi
ansible srv-web-01 -m command -a "nginx -t" --become
```

Provera TLS-a sa kontrolnog čvora:

```bash
# Lanac, ime i rok važenja
openssl s_client -connect zabbix.example.com:443 -servername zabbix.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# Da li preusmeravanje radi
curl -sI http://zabbix.example.com/ | head -3

# Da li frontend odgovara
curl -sI https://zabbix.example.com/ | head -3
```

Iz pretraživača otvori `https://zabbix.example.com`. Očekuje se ekran za prijavu, ne čarobnjak.

---

## Rešavanje problema

### `nginx -t` prijavljuje `cannot load certificate`

Putanja je pogrešna ili fajl ne postoji:

```bash
ls -l /etc/ssl/certs/zabbix-frontend-fullchain.pem /etc/ssl/private/zabbix-frontend.key
```

Ako je poruka `PEM_read_bio_X509_AUX`, fajl nije u PEM formatu — verovatno je DER ili PKCS#12. Konverzija:

```bash
openssl x509 -inform DER -in cert.der -out cert.pem
openssl pkcs12 -in cert.pfx -nocerts -nodes -out key.pem
```

### Pretraživač prijavljuje nepoznatog izdavaoca

Sertifikat nije pun lanac. Proveri koliko blokova ima:

```bash
grep -c "BEGIN CERTIFICATE" /etc/ssl/certs/zabbix-frontend-fullchain.pem
```

Uz sopstveni CA očekuje se najmanje 2. Spoj ih:

```bash
cat host.crt ca.crt > fullchain.pem
```

### Pretraživač prijavljuje neslaganje imena

`role_zabbix_web_hostname` se razlikuje od CN/SAN vrednosti u sertifikatu:

```bash
openssl x509 -in /etc/ssl/certs/zabbix-frontend-fullchain.pem -noout -text | grep -A1 "Subject Alternative Name"
```

### Beskonačno preusmeravanje

Reverse proxy ispred već završava TLS i prosleđuje HTTP, a ovaj vhost opet preusmerava. Isključi preusmeravanje:

```yaml
role_zabbix_web_http_redirect: false
role_zabbix_web_https_enabled: false
```

### Pojavljuje se čarobnjak umesto ekrana za prijavu

`zabbix.conf.php` ne postoji ili PHP ne može da ga pročita:

```bash
ansible srv-web-01 -m command -a "ls -l /etc/zabbix/web/zabbix.conf.php"
```

Očekuje se `root:www-data` sa `0640`.

### `Database error: Connection to database failed`

Frontend ne može do baze. Proveri da lozinka i ime naloga odgovaraju roli `zabbix_db`, i da `role_zabbix_db_frontend_hosts` pokriva IP ovog hosta.

### `Zabbix server is not running`

Frontend radi, ali ne može do servera na portu 10051. Proveri `role_zabbix_web_server_host` i pravilo zaštitnog zida. Ovo ne sprečava pregled podataka — samo radnje koje traže server.

### `502 Bad Gateway`

PHP-FPM nije pokrenut ili socket ne postoji:

```bash
ansible srv-web-01 -m command -a "ls -l /run/php/zabbix.sock"
```

### Odjavljuje me pri svakom osvežavanju stranice

Uz HTTPS iza reverse proxy-ja koji ne prosleđuje `X-Forwarded-Proto`, Zabbix postavi `secure` kolačić koji pretraživač ne vraća preko HTTP-a. Reši se time što proxy prosleđuje zaglavlje, ili se TLS završava na ovom hostu.
