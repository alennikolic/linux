# zabbix_webdriver

Podiže Selenium WebDriver kao Docker kontejner pod systemd nadzorom, za
potrebe Zabbix *Browser* stavki.

Browser stavke izvršava sam Zabbix server ili proxy — ne agent. Zbog toga ova
rola ide na host na kojem radi `zabbix_server` ili `zabbix_proxy`, ili na
zaseban host kojem taj proces može da pristupi.

## Preduslovi

- Ubuntu 22.04+ / Debian 12+
- **Docker Engine mora već biti instaliran.** Rola ga namerno ne instalira.
  Kroz postojeće role:

```yaml
  # group_vars/apply_repos.yml
  role_repos_list:
    - name: docker
      uris: "https://download.docker.com/linux/ubuntu"
      suites: "{{ ansible_distribution_release }}"
      components: stable
      architectures: amd64
      signed_by: "https://download.docker.com/linux/ubuntu/gpg"

  # group_vars/deploy_packages.yml
  role_packages_install:
    - docker-ce
    - docker-ce-cli
    - containerd.io
```

- Pristup Docker Hub-u sa ciljnog hosta, ili ručno donesena slika uz
  `role_zabbix_webdriver_pull: false`
- Slobodnih ~500 MB RAM-a po istovremenoj sesiji pod opterećenjem

Rola ne traži nove Ansible kolekcije.

## Aktivacija

```ini
# hosts.ini
[deploy_zabbix_webdriver]
dr-itoc-zabbix-proxy01
```

Grupa aktivira rolu preko `group_vars/deploy_zabbix_webdriver.yml`, koji već
sadrži `role_zabbix_webdriver_enabled: true`.

## Varijable

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_webdriver_enabled` | `false` | Prekidač role |
| `role_zabbix_webdriver_image` | `selenium/standalone-chrome` | Slika; postoji i `-firefox`, `-edge` |
| `role_zabbix_webdriver_image_tag` | `latest` | Oznaka slike; zakuj u produkciji |
| `role_zabbix_webdriver_pull` | `true` | Preuzimanje slike pre pokretanja |
| `role_zabbix_webdriver_container_name` | `zabbix-webdriver` | Ime kontejnera i systemd servisa |
| `role_zabbix_webdriver_bind_address` | `172.17.0.1` | Adresa na kojoj se objavljuje port |
| `role_zabbix_webdriver_port` | `4444` | Port na hostu |
| `role_zabbix_webdriver_max_sessions` | `10` | Broj istovremenih sesija |
| `role_zabbix_webdriver_shm_size` | `2g` | Veličina `/dev/shm` |
| `role_zabbix_webdriver_session_timeout` | `300` | Neaktivnost pre gašenja sesije (s) |
| `role_zabbix_webdriver_session_request_timeout` | `300` | Čekanje u redu za sesiju (s) |
| `role_zabbix_webdriver_session_retry_interval` | `5` | Razmak između pokušaja (s) |
| `role_zabbix_webdriver_screen_width` | `1920` | Širina virtuelnog ekrana |
| `role_zabbix_webdriver_screen_height` | `1080` | Visina virtuelnog ekrana |
| `role_zabbix_webdriver_memory_limit` | `""` | `--memory` za kontejner |
| `role_zabbix_webdriver_cpus` | `""` | `--cpus` za kontejner |
| `role_zabbix_webdriver_extra_env` | `{}` | Dodatne promenljive okruženja |
| `role_zabbix_webdriver_extra_docker_args` | `""` | Dodatni argumenti za `docker run` |
| `role_zabbix_webdriver_docker_bin` | `/usr/bin/docker` | Putanja do `docker` |
| `role_zabbix_webdriver_restart_sec` | `10` | Pauza pre restarta po padu (s) |
| `role_zabbix_webdriver_service_enabled` | `true` | Pokretanje pri butu |
| `role_zabbix_webdriver_service_state` | `started` | Željeno stanje servisa |
| `role_zabbix_webdriver_check_bind_address` | `true` | Provera da bind adresa postoji |
| `role_zabbix_webdriver_wait_for_ready` | `true` | Čekanje na `/status` |
| `role_zabbix_webdriver_wait_retries` | `30` | Broj pokušaja provere |
| `role_zabbix_webdriver_wait_delay` | `5` | Razmak između pokušaja (s) |

## Primer

```yaml
# host_vars/dr-itoc-zabbix-proxy01.yml
role_zabbix_webdriver_image_tag: "4.27.0"
role_zabbix_webdriver_max_sessions: 10
role_zabbix_webdriver_memory_limit: "6g"
role_zabbix_webdriver_extra_env:
  TZ: "Europe/Belgrade"
```

Uz to, na Zabbix strani:

```yaml
role_zabbix_proxy_config:
  WebDriverURL: "http://172.17.0.1:4444"
  StartBrowserPollers: 10
```

## Zamke

**`SE_NODE_MAX_SESSIONS` sam po sebi ne radi ništa.** Bez
`SE_NODE_OVERRIDE_MAX_SESSIONS=true` Selenium ograničava broj sesija na broj
CPU jezgara i ne javlja ništa u logu. Rola tu promenljivu postavlja uvek.

**`StartBrowserPollers` mora biti ≤ `max_sessions`.** Ta dva broja žive u
različitim rolama i ništa ih automatski ne usklađuje. Kada je poller-a više,
višak zahteva čeka i stavke odlaze u timeout — bez jasne greške.

**Docker zaobilazi UFW.** Objavljeni portovi ulaze u iptables lanac `DOCKER`,
ispred UFW pravila. Zato je bind adresa `172.17.0.1`, a rola odbija
`0.0.0.0`. Nezaštićen WebDriver na javnoj adresi znači da svako može pokrenuti
proizvoljan JavaScript i otvoriti proizvoljan URL iz vaše mreže.

**Podrazumevanih 64 MB za `/dev/shm` obara Chrome.** Greška
`session deleted because of page crash` javlja se tek pod opterećenjem, pa se
teško povezuje sa uzrokom. Otud `--shm-size=2g`.

**Oznaka `latest` znači neplaniranu nadogradnju.** Rola pri svakom prolazu
preuzima sliku i restartuje kontejner ako se promenila. Zakujte verziju kada
želite predvidljivost.

**Browser stavke se izvršavaju na proxy-ju, ne na agentu.** Ako je host sa
stavkom vezan za proxy, WebDriver mora biti dostupan tom proxy-ju.

## Struktura

```text
roles/zabbix_webdriver/
├── defaults/main.yml
├── vars/main.yml
├── tasks/main.yml
├── handlers/main.yml
├── templates/
│   └── webdriver.service.j2
└── README.md
```

## Idempotentnost

Ponovno pokretanje ne menja ništa ako se ni unit fajl ni slika nisu promenili.
Izuzetak je `docker pull` sa oznakom `latest` — kad se na registru pojavi nova
slika, task se prijavljuje kao promenjen i kontejner se restartuje. To je
namerno.

## Provera

```bash
systemctl status zabbix-webdriver
docker ps --filter name=zabbix-webdriver
curl -s http://172.17.0.1:4444/status | python3 -m json.tool
journalctl -u zabbix-webdriver -n 50 --no-pager
```

U `/status` pogledajte `value.ready` i broj slobodnih slotova.

Na Zabbix strani:

```bash
grep -E 'WebDriverURL|StartBrowserPollers' /etc/zabbix/zabbix_proxy.d/zz-ansible.conf
zabbix_proxy -c /etc/zabbix/zabbix_proxy.conf -T
```

Zatim u frontendu: stavka tipa *Browser* → **Test** → **Get value**.

## Rešavanje problema

**Servis se stalno restartuje**

```bash
journalctl -u zabbix-webdriver -n 100 --no-pager
```

Najčešće: zauzet port, nepostojeća bind adresa, ili slika koja se ne može
preuzeti.

**`Cannot assign requested address`**

`docker0` most ima drugačiju podmrežu. Proverite sa `ip -4 addr show docker0`
i podesite `role_zabbix_webdriver_bind_address`.

**Stavke u timeout-u, a `/status` kaže `ready: true`**

Broj pollera premašuje broj sesija. Uporedite `StartBrowserPollers` sa
`role_zabbix_webdriver_max_sessions`.

**`session deleted because of page crash`**

Nedovoljan `/dev/shm` ili nedostatak RAM-a. Proverite `dmesg | grep -i oom`.

**Zabbix javlja `cannot connect to WebDriver`**

Sa Zabbix hosta:

```bash
curl -v http://172.17.0.1:4444/status
```

Ako ovo prolazi, a Zabbix ne, proverite da li je `WebDriverURL` zaista stigao
u drop-in i da li je proxy restartovan.

## Uklanjanje

Rola je aditivna i ne uklanja ono što je postavila. Ručno:

```bash
systemctl disable --now zabbix-webdriver
rm /etc/systemd/system/zabbix-webdriver.service
systemctl daemon-reload
docker rmi selenium/standalone-chrome:latest
```
