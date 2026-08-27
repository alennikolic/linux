# Rola: zabbix_web

Instalira i konfiguriše Zabbix web frontend na **Nginx-u**, sa opcionim HTTPS-om.

Rola upisuje `zabbix.conf.php` i time **preskače čarobnjak** koji se inače pojavljuje pri prvom otvaranju frontenda.

Apache više nije podržan.

---

## Šta rola dira, a šta ne

Ovo je najvažnija stvar za razumevanje role.

Zabbix paket `zabbix-nginx-conf` isporučuje dva konfiguraciona fajla i, kroz `postinst` skriptu, dve simbolične veze koje ih aktiviraju. **Rola ne menja nijedan od ta dva fajla.** Umesto toga uklanja veze i upisuje sopstvene fajlove pod sopstvenim imenima.

| Putanja | Ko je vlasnik | Šta rola radi |
|---|---|---|
| `/etc/zabbix/nginx.conf` | dpkg conffile | **ne dira** |
| `/etc/zabbix/php-fpm.conf` | dpkg conffile | **ne dira** |
| `/etc/nginx/conf.d/zabbix.conf` | veza, pravi je `postinst` | uklanja |
| `/etc/php/<v>/fpm/pool.d/zabbix.conf` | veza, pravi je `postinst` | uklanja |
| `/etc/nginx/conf.d/zabbix-ansible.conf` | **rola** | upisuje vhost |
| `/etc/php/<v>/fpm/pool.d/zabbix-ansible.conf` | **rola** | upisuje FPM pool |
| `/etc/zabbix/web/zabbix.conf.php` | **rola** | upisuje, preskače čarobnjak |
| `/etc/php/<v>/fpm/conf.d/99-zabbix.ini` | ranija verzija role | uklanja |

Posledice:

- `apt upgrade` **nikada** ne postavlja pitanje o izmenjenom conffile-u.
- Vendorova konfiguracija ostaje na disku netaknuta i služi kao referenca pri nadogradnji Zabbix-a.
- Ime pool-a je `zabbix-ansible`, ne `zabbix`. Namerno — dva pool-a sa istim imenom sprečavaju pokretanje **celog** `php-fpm` servisa, ne samo tog pool-a. Različito ime čini uklanjanje veze bezopasnim i ako zakaže.

Nadogradnja paketa može ponovo napraviti vendorove veze. Rola ih pri sledećem pokretanju ponovo uklanja; do tada frontend radi, samo uz suvišan pool i moguć sukob oko podrazumevanog server bloka na portu 80.

Poređenje sa onim što Zabbix trenutno preporučuje:

```bash
diff /etc/zabbix/nginx.conf /etc/nginx/conf.d/zabbix-ansible.conf
diff /etc/zabbix/php-fpm.conf /etc/php/8.3/fpm/pool.d/zabbix-ansible.conf
```

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

**Rola ne prima sadržaj sertifikata ni ključa kroz varijable** — svesna odluka. Privatni ključ ne prolazi kroz Ansible: ne stoji u `host_vars`, ne prolazi kroz templating, ne pojavljuje se u izlazu. Materijal se donosi na host nezavisno od role. Ostaju dva načina.

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

## PHP podešavanja

Sve `role_zabbix_web_php_*` vrednosti rola upisuje kao `php_value[]` u sopstveni FPM pool. **To je jedino mesto na kome one stvarno važe** — direktive `php_value[]` iz pool-a imaju prednost nad `php.ini` i nad svime iz `conf.d`.

Ranija verzija role pisala ih je u `conf.d/99-zabbix.ini`, gde ih je vendorov pool tiho pregazio; jedina vrednost koja je radila bila je `date.timezone`, jer je vendor nju ostavljao zakomentarisanu. Rola sada taj fajl uklanja.

```yaml
role_zabbix_web_php_memory_limit: "256M"
role_zabbix_web_php_pm_max_children: 50
role_zabbix_web_php_extra_values:
  opcache.memory_consumption: 256
```

Provera šta je zaista na snazi:

```bash
sudo ss -lx | grep zabbix-ansible
sudo grep -r php_value /etc/php/*/fpm/pool.d/
```

Broj procesa puta `memory_limit` je gornja granica potrošnje memorije. Sa podrazumevanih `50 × 128M` to je teorijskih 6.4 GB — u praksi mnogo manje, ali vredi znati pre nego što podigneš oba.

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
| `role_zabbix_web_hostname` | `_` | `server_name`. Više imena razdvoji razmakom. |
| `role_zabbix_web_listen_address` | `""` | Prazno = sve adrese. |
| `role_zabbix_web_client_max_body_size` | `16M` | Najveći zahtev. Drži ≥ `post_max_size`. |

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

### PHP vrednosti

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_php_max_execution_time` | `300` | Sekunde. Minimum koji Zabbix traži. |
| `role_zabbix_web_php_memory_limit` | `128M` | Minimum. |
| `role_zabbix_web_php_post_max_size` | `16M` | Minimum. |
| `role_zabbix_web_php_upload_max_filesize` | `2M` | Minimum. Mora biti ≤ `post_max_size`. |
| `role_zabbix_web_php_max_input_time` | `300` | Sekunde. |
| `role_zabbix_web_php_max_input_vars` | `10000` | Zabbix zahteva ovoliko. |
| `role_zabbix_web_php_timezone` | `Europe/Belgrade` | Utiče na prikaz vremena. |
| `role_zabbix_web_php_extra_values` | `{}` | Dodatne `php_value[]` direktive. |

### PHP-FPM pool

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_php_pm` | `dynamic` | `dynamic`, `ondemand`, `static`. |
| `role_zabbix_web_php_pm_max_children` | `50` | Gornja granica broja procesa. |
| `role_zabbix_web_php_pm_start_servers` | `5` | Samo uz `dynamic`. |
| `role_zabbix_web_php_pm_min_spare_servers` | `5` | Samo uz `dynamic`. |
| `role_zabbix_web_php_pm_max_spare_servers` | `35` | Samo uz `dynamic`. |
| `role_zabbix_web_php_pm_idle_timeout` | `10s` | Samo uz `ondemand`. |

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

### Frontend na IP adresi i po imenu

```yaml
role_zabbix_web_hostname: "10.0.0.60 zabbix.example.com"
role_zabbix_web_https_enabled: true
role_zabbix_web_tls_selfsigned_cn: "zabbix.example.com"
role_zabbix_web_tls_selfsigned_sans:
  - "IP:10.0.0.60"
```

`server_name` prima oba imena. CN je ime, IP ide u SAN ručno.

### Frontend na hostu sa malo memorije

```yaml
role_zabbix_web_php_pm: ondemand
role_zabbix_web_php_pm_max_children: 10
role_zabbix_web_php_pm_idle_timeout: "30s"
```

Prvi zahtev posle mirovanja je sporiji, ali u praznom hodu nema nijednog PHP procesa.

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

**Nijedan dpkg conffile nije izmenjen.** Rola uklanja samo simbolične veze, koje pravi `postinst` skripta i koje dpkg ne prati. Vendorovi fajlovi ostaju netaknuti.

**Putanja frontenda se otkriva.** Od zvaničnih paketa 7.2 PHP fajlovi su premešteni iz `/usr/share/zabbix` u `/usr/share/zabbix/ui`. Rola proverava postojanje `ui` podfoldera umesto da putanju zakuje. Sa zakovanom putanjom na 7.2+ frontend prikazuje stranicu sa uputstvom umesto ekrana za prijavu.

**Verzija PHP-a se čita iz `/etc/php`, ne iz `php -r`.** CLI SAPI ne mora biti instaliran, a na hostu sa više PHP verzija pokazuje na onu koju bira `update-alternatives` — što ne mora biti verzija čija FPM instanca servisira Zabbix.

**Rola ne prima TLS materijal kroz varijable.** Privatni ključ ne prolazi kroz Ansible. Sertifikat i ključ se donose na host nezavisno, ili ih rola napravi sama kao privremene.

**Self-signed se pravi samo kada oba fajla nedostaju.** Čim jedan postoji, rola ne pravi ništa — inače bi ručno donet sertifikat bio prepisan pri sledećem pokretanju. Ako postoji tačno jedan fajl, rola prekida rad, jer je to gotovo uvek trag prekinutog ranijeg pokušaja.

**SAN je obavezan, CN se ne gleda.** Od Chrome 58 i ekvivalentnih verzija ostalih klijenata validacija ide isključivo preko SAN-a. Rola zato unos za sam CN dodaje sama.

**HSTS i self-signed se ne trpe.** Greška sertifikata uz aktivan HSTS se u većini pretraživača **ne može preskočiti**. Ostavi HSTS isključen dok ne dobiješ sertifikat kojem klijenti veruju.

**Sintaksa za HTTP/2 se menjala.** Do Nginx 1.25.0 ide kao parametar direktive `listen`, od 1.25.1 kao zasebna direktiva `http2 on`. Rola otkriva verziju i bira ispravnu — Ubuntu 24.04 isporučuje 1.24.0, dakle staru.

**`fastcgi_param HTTPS on`** se dodaje samo uz TLS. Bez toga PHP ne zna da je veza šifrovana, pa Zabbix ne postavlja `secure` zastavicu na kolačić sesije.

**`client_max_body_size` je usklađen sa PHP-om.** Nginx podrazumevano prima 1M po zahtevu, što je manje od `post_max_size`. Uvoz većeg template fajla bi vratio `413` pre nego što PHP uopšte vidi zahtev.

**Obe konfiguracije se proveravaju pre restarta.** Rola pokreće `nginx -t` i `php-fpm<v> -t` posle upisa. Greška prekida rolu pre nego što obori servis koji do tada radi. Provera ne može ići kroz `validate` parametar modula `template`, jer oba alata proveravaju **celu** konfiguraciju — pojedinačan fajl van svog konteksta nije važeća celina.

**`session.save_path` se namerno ne zadaje.** Bez njega važi podrazumevana putanja iz `php.ini`, koju Debian redovno čisti kroz sopstveni posao. Sopstvena putanja bi zahtevala i sopstveno čišćenje, inače se folder vremenom napuni, a simptom — nasumično odjavljivanje — ne upućuje na uzrok.

**Privatni ključ ima dozvole `0600` i vlasnika `root`.** Nginx master proces radi kao root i čita ga pre nego što spusti privilegije radnih procesa. Taskovi koji ga dodiruju imaju `no_log: true`.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servise. Self-signed sertifikat se ne pravi ponovo — ni pri isteku. Obnova je ručna: obriši oba fajla i pusti rolu.

---

## Migracija sa ranije verzije role

Prvi prolaz na hostu koji je već prošao kroz stariju verziju uradi sve sam. Vredi znati šta se dešava:

1. Upisuje se novi vhost i novi pool.
2. Uklanjaju se vendorove veze i `99-zabbix.ini`.
3. Socket se menja iz `/run/php/zabbix.sock` u `/run/php/zabbix-ansible.sock`.
4. Rola proverava `dpkg --verify` i ispisuje napomenu ako je stariji `/etc/zabbix/nginx.conf` izmenjen.

Fajl `/etc/zabbix/nginx.conf` na takvom hostu i dalje nosi sadržaj koji je upisala stara verzija role. Sada je van upotrebe i ne utiče ni na šta. Ako želiš čist original:

```bash
sudo apt-get install --reinstall \
  -o Dpkg::Options::="--force-confask" zabbix-nginx-conf
```

Backup fajlovi koje je stara verzija ostavila (`*.NNNN.YYYY-MM-DD@HH:MM:SS~`) mogu se obrisati kad potvrdiš da frontend radi.

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
    └── php-fpm.conf.j2
```

---

## Provera

```bash
./apply.sh --limit srv-web-01

# Stanje servisa
ansible srv-web-01 -m command -a "systemctl status nginx"
ansible srv-web-01 -m shell -a "systemctl status php*-fpm"

# Da li obe konfiguracije prolaze
ansible srv-web-01 -m command -a "nginx -t" --become
ansible srv-web-01 -m shell -a "/usr/sbin/php-fpm*  -t" --become

# Šta Nginx sluša
ansible srv-web-01 -m command -a "ss -lntp sport = :443"

# Da li je vendorova konfiguracija zaista isključena
ansible srv-web-01 -m shell -a "ls -l /etc/nginx/conf.d/ /etc/php/*/fpm/pool.d/"
```

Očekuje se `zabbix-ansible.conf` na oba mesta, i **nijedan** `zabbix.conf`.

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

### `php-fpm` neće da startuje, poruka o duplom pool-u

Vendorova veza nije uklonjena, a naš pool nosi isto ime. Ne bi trebalo da se desi jer se imena razlikuju, ali ako si ručno menjao `_zabbix_web_pool_name`:

```bash
ls -l /etc/php/*/fpm/pool.d/
sudo rm -f /etc/php/8.3/fpm/pool.d/zabbix.conf
sudo systemctl restart php8.3-fpm
```

### `502 Bad Gateway`

PHP-FPM nije pokrenut, ili socket ne postoji na očekivanoj putanji:

```bash
ansible srv-web-01 -m command -a "ls -l /run/php/zabbix-ansible.sock"
```

Ako fajla nema, pool nije učitan. Proveri da postoji `pool.d/zabbix-ansible.conf` i da `php-fpm<v> -t` prolazi.

Ako socket postoji ali greška ostaje, u pitanju su dozvole — očekuje se `www-data:www-data` i `0660`.

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

### Otvaram po imenu, dobijam tuđi sajt ili podrazumevanu stranicu

`server_name` sadrži samo IP adresu, pa se zahtev po imenu ne poklapa sa ovim server blokom. Navedi oba, razdvojena razmakom:

```yaml
role_zabbix_web_hostname: "10.0.0.60 zabbix.example.com"
```

### Beskonačno preusmeravanje

Reverse proxy ispred već završava TLS i prosleđuje HTTP, a ovaj vhost opet preusmerava:

```yaml
role_zabbix_web_http_redirect: false
role_zabbix_web_https_enabled: false
```

### Pojavljuje se čarobnjak umesto ekrana za prijavu

`zabbix.conf.php` ne postoji ili PHP ne može da ga pročita. Očekuje se `root:www-data` sa `0640`.

### Stranica sa uputstvom o `/usr/share/zabbix/ui`

Vhost pokazuje na staru putanju. Rola je otkriva sama, pa ovo znači da je vhost upisan pre nadogradnje na 7.2+. Pokreni rolu ponovo.

### PHP vrednost koju sam zadao ne važi

Proveri da nije ostao vendorov pool:

```bash
ls -l /etc/php/*/fpm/pool.d/
```

Ako je `zabbix.conf` tu, njegov `php_value[]` se primenjuje na njegov pool. Naš vhost gađa naš socket, pa to ne bi trebalo da utiče — ali ako je vhost ručno menjan, proveri na koji socket pokazuje `fastcgi_pass`.

### `Database error: Connection to database failed`

Proveri da lozinka i ime naloga odgovaraju roli `zabbix_db`, i da `role_zabbix_db_frontend_hosts` pokriva IP ovog hosta.

### `Zabbix server is not running`

Frontend radi, ali ne može do servera na portu 10051. Proveri `role_zabbix_web_server_host` i pravilo zaštitnog zida. Ne sprečava pregled podataka — samo radnje koje traže server.

### Odjavljuje me pri svakom osvežavanju stranice

Uz HTTPS iza reverse proxy-ja koji ne prosleđuje `X-Forwarded-Proto`, Zabbix postavi `secure` kolačić koji pretraživač ne vraća preko HTTP-a.
