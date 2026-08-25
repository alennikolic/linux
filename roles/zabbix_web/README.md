# Rola: zabbix_web

Instalira i konfiguriše Zabbix web frontend na Debian/Ubuntu sistemima.

Podržani su Nginx (podrazumevano) i Apache. Rola upisuje `zabbix.conf.php` i time **preskače čarobnjak za instalaciju** koji se inače pojavljuje pri prvom otvaranju frontenda.

---

## Preduslovi

| Preduslov | Ko ga rešava |
|---|---|
| Zabbix repozitorijum | rola `repos`, grupa `[apply_repos]` |
| Baza sa uvezenom šemom | role `zabbix_db` i `zabbix_server` |
| Port otvoren | rola `firewall`, grupa `[apply_firewall]` |

**Frontend čita bazu direktno**, ne kroz Zabbix server. To znači da mora imati mrežni pristup do baze, a ne samo do servera. Serveru se javlja samo za pojedine radnje — izvršavanje skripti i proveru dostupnosti.

Frontend ne mora biti na istom hostu kao Zabbix server.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_web]
srv-mon-01
```

Grupi pripada `group_vars/deploy_zabbix_web.yml`, koji postavlja `role_zabbix_web_enabled: true`.

---

## Obavezna konfiguracija

Lozinka baze mora biti ista u sve tri Zabbix role. Definiši je jednom:

```yaml
# host_vars/srv-mon-01.yml
_zabbix_db_pass: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313436...

role_zabbix_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_server_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_web_db_password: "{{ _zabbix_db_pass }}"
```

---

## Varijable

### Aktivacija i web server

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_web_server` | `nginx` | `nginx` ili `apache`. |
| `role_zabbix_web_version` | `""` | Zakovana verzija. Prazno = najnovija. |

### Baza

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_web_db_host` | `localhost` | Adresa baze. |
| `role_zabbix_web_db_port` | `3306` | Port. |
| `role_zabbix_web_db_name` | `zabbix` | Ime baze. |
| `role_zabbix_web_db_user` | `zabbix` | Korisnik. |
| `role_zabbix_web_db_password` | `""` | **Obavezno.** Ide u vault. |
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
| `role_zabbix_web_listen_port` | `8080` | Port web servera. |
| `role_zabbix_web_hostname` | `_` | `server_name`. Zvezdica prihvata sve. |
| `role_zabbix_web_listen_address` | `""` | Prazno = sve adrese. |

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
| `role_zabbix_web_extra_config` | `""` | Proizvoljne PHP linije. |
| `role_zabbix_web_service_enabled` | `true` | Startuje uz sistem. |
| `role_zabbix_web_service_state` | `started` | `started`, `stopped`. |

---

## Primeri

### Sve na jednom hostu

```yaml
# host_vars/srv-mon-01.yml
role_zabbix_web_db_password: "{{ _zabbix_db_pass }}"
role_zabbix_web_server_name: "Monitoring — Produkcija"
```

Frontend je dostupan na `http://srv-mon-01:8080`.

Pravilo zaštitnog zida:

```yaml
role_firewall_rules:
  - { rule: allow, port: 8080, proto: tcp, from: "10.0.0.0/8", comment: "Zabbix frontend" }
```

### Frontend na zasebnom hostu

```yaml
# host_vars/srv-web-01.yml
role_zabbix_web_db_host: "10.0.0.21"
role_zabbix_web_server_host: "10.0.0.50"
role_zabbix_web_db_password: "{{ _zabbix_db_pass }}"
```

Na hostu baze mora postojati dozvola i za ovaj host:

```yaml
# host_vars/srv-db-01.yml
role_zabbix_db_user_host: "10.0.0.%"
```

### Apache umesto Nginx-a

```yaml
role_zabbix_web_server: apache
role_zabbix_web_listen_port: 80
```

### Standardni HTTP port

```yaml
role_zabbix_web_listen_port: 80
role_zabbix_web_hostname: "zabbix.example.com"
```

### Enkriptovana veza ka bazi

```yaml
role_zabbix_web_extra_config: |
  $DB['ENCRYPTION'] = true;
  $DB['CA_FILE'] = '/etc/ssl/certs/ca-cert.pem';
  $DB['VERIFY_HOST'] = true;
```

---

## Napomene

**Čarobnjak se preskače.** Kada `zabbix.conf.php` postoji i sadrži ispravne podatke, frontend odmah prikazuje ekran za prijavu. Podrazumevani nalog je `Admin` sa lozinkom `zabbix` — **promeni je odmah po prvoj prijavi.** Rola to ne radi, jer se korisnicima frontenda upravlja kroz Zabbix API, što je posao role `zabbix_provisioning`.

**Verzija PHP-a se otkriva iz sistema.** Ubuntu 22.04 isporučuje PHP 8.1, 24.04 isporučuje 8.3. Rola pokreće `php -r` da sazna verziju umesto da je zakuje, pa putanja do `conf.d` foldera uvek odgovara.

**Nginx vhost se prepisuje u celosti.** Paket `zabbix-nginx-conf` isporučuje `/etc/zabbix/nginx.conf` sa zakomentarisanim `listen` i `server_name` — bez izmene taj vhost ne radi. Rola upisuje sopstvenu verziju, uz `backup: true`.

**PHP-FPM socket.** Nginx konfiguracija koristi `/run/php/zabbix.sock`, koji dolazi iz FPM pool-a što ga instalira `zabbix-nginx-conf`. Ako promeniš pool, promeni i `fastcgi_pass`.

**Rola ne postavlja HTTPS.** Frontend servira običan HTTP. Za TLS postavi reverse proxy ispred, ili proširi vhost šablon. Sertifikatima upravlja rola `root_ca`, ne ova.

**`zabbix.conf.php` sadrži lozinku**, pa ima dozvole `0640` i grupu `www-data`. Task ima `no_log: true`, što znači da `--diff` neće prikazati razliku u tom fajlu.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje prijavljuje `ok` i ne restartuje servise, osim kada se paket ili konfiguracija zaista promene.

---

## Struktura

```text
roles/zabbix_web/
├── README.md
├── defaults/
│   └── main.yml
├── vars/
│   └── main.yml
├── handlers/
│   └── main.yml
├── tasks/
│   └── main.yml
└── templates/
    ├── zabbix.conf.php.j2
    ├── nginx.conf.j2
    └── zabbix-php.ini.j2
```

---

## Provera

```bash
# Bez izmena
./apply.sh --limit deploy_zabbix_web --check --diff

# Primena
./apply.sh --limit srv-mon-01

# Stanje servisa
ansible srv-mon-01 -m command -a "systemctl status nginx"
ansible srv-mon-01 -m command -a "systemctl status php8.3-fpm"

# Da li web server slusa
ansible srv-mon-01 -m command -a "ss -lntp sport = :8080"

# Da li frontend odgovara
ansible srv-mon-01 -m uri -a "url=http://localhost:8080 return_content=no"
```

Iz pretraživača otvori `http://<host>:8080`. Očekuje se ekran za prijavu, ne čarobnjak.

---

## Rešavanje problema

**Pojavljuje se čarobnjak umesto ekrana za prijavu**

`zabbix.conf.php` ne postoji ili PHP ne može da ga pročita. Proveri dozvole:

```bash
ansible srv-mon-01 -m command -a "ls -l /etc/zabbix/web/zabbix.conf.php"
```

Očekuje se `root:www-data` sa `0640`.

**`Database error: Connection to database failed`**

Frontend ne može do baze. Proveri da je lozinka ista kao u `zabbix_db`, i da `role_zabbix_db_user_host` pokriva host frontenda.

**`Zabbix server is not running`**

Frontend radi, ali ne može do servera na portu 10051. Ako su na različitim hostovima, proveri `role_zabbix_web_server_host` i pravilo zaštitnog zida. Ovo ne sprečava pregled podataka — samo radnje koje traže server.

**`502 Bad Gateway`**

PHP-FPM nije pokrenut ili socket ne postoji:

```bash
ansible srv-mon-01 -m command -a "ls -l /run/php/zabbix.sock"
```

**Frontend prijavlja da PHP opcija nije dovoljna**

Podešavanja nisu učitana. Proveri da je fajl u ispravnom folderu za tvoju verziju PHP-a:

```bash
ansible srv-mon-01 -m shell -a "php -i | grep -E 'memory_limit|max_execution_time'"
```
