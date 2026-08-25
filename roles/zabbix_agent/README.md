# Rola: zabbix_agent

Instalira i konfiguriše Zabbix agenta na Debian/Ubuntu sistemima.

Podržana su oba agenta — klasični `zabbix-agent` i noviji `zabbix-agent2`. Izbor je jedna varijabla; rola sama izvodi ime servisa, putanju konfiguracije i include folder.

---

## Preduslov: repozitorijum

Zabbix agent ne postoji u sistemskim Ubuntu izvorima u aktuelnoj verziji. Pre ove role host mora proći kroz rolu `repos`:

```ini
[apply_repos]
srv-web-01

[deploy_zabbix_agent]
srv-web-01
```

```yaml
# group_vars/all.yml
role_repos_list:
  - name: zabbix
    uris: "https://repo.zabbix.com/zabbix/7.0/ubuntu"
    suites: "{{ ansible_distribution_release }}"
    components: [main]
    signed_by: "https://repo.zabbix.com/zabbix-official-repo.key"
```

U `playbook.yml` `apply_repos` ide pre `deploy_zabbix_agent`, pa je redosled ispravan i pri jednom pokretanju.

---

## Aktivacija

```ini
# inventory/hosts.ini
[deploy_zabbix_agent]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/deploy_zabbix_agent.yml`, koji postavlja `role_zabbix_agent_enabled: true`. Taj fajl ne treba dirati.

Kaskadno, ako agent ide na sve servere:

```ini
[deploy_zabbix_agent:children]
webservers
dbservers
```

---

## Obavezna konfiguracija

```yaml
# group_vars/all.yml
role_zabbix_agent_server: "10.0.0.50"
```

Bez ovoga rola prekida rad na prvoj proveri. Agent bi inače bio instaliran, ali ne bi imao kome da se javi.

---

## Varijable

### Aktivacija i izbor agenta

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_enabled` | `false` | Kada je `false`, rola ne dira ništa. |
| `role_zabbix_agent_package` | `zabbix-agent` | Ili `zabbix-agent2`. |
| `role_zabbix_agent_version` | `""` | Zakovana verzija. Prazno = najnovija. |

### Veza sa serverom

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_server` | `""` | **Obavezno.** Odakle se prihvataju pasivne provere. |
| `role_zabbix_agent_server_active` | isto kao `_server` | Kome se šalju aktivne provere. |
| `role_zabbix_agent_hostname` | `{{ inventory_hostname }}` | Ime pod kojim se agent predstavlja. |
| `role_zabbix_agent_host_metadata` | `""` | Metapodaci za automatsku registraciju. |

### Mreža

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_listen_port` | `10050` | Port na kojem agent sluša. |
| `role_zabbix_agent_listen_ip` | `""` | Prazno = sve adrese. |
| `role_zabbix_agent_timeout` | `3` | Sekunde. Zabbix 7.0 dozvoljava do 30. |

### Logovanje

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_logfile` | `/var/log/zabbix/zabbix_agentd.log` | Putanja log fajla. |
| `role_zabbix_agent_logfile_size` | `10` | MB. Nula isključuje rotaciju agenta. |
| `role_zabbix_agent_debug_level` | `3` | 0–5. Nivoi 4 i 5 brzo pune disk. |

### Dozvoljeni ključevi

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_allow_keys` | `[]` | Izuzeci od zabrane. |
| `role_zabbix_agent_deny_keys` | `["system.run[*]"]` | Zabranjeni ključevi. |

### TLS

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_tls_connect` | `unencrypted` | `unencrypted`, `psk` ili `cert`. |
| `role_zabbix_agent_tls_accept` | `unencrypted` | Isto. |
| `role_zabbix_agent_tls_psk_identity` | `""` | Identitet PSK ključa. |
| `role_zabbix_agent_tls_psk` | `""` | Sam ključ. **Tajna** — ide u vault. |
| `role_zabbix_agent_tls_psk_file` | `/etc/zabbix/zabbix_agent.psk` | Gde se ključ upisuje. |

### Ostalo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_zabbix_agent_extra_config` | `""` | Proizvoljne linije na kraju konfiguracije. |
| `role_zabbix_agent_service_enabled` | `true` | Startuje uz sistem. |
| `role_zabbix_agent_service_state` | `started` | `started`, `stopped`. |

---

## Primeri

### Osnovna postavka

```yaml
# group_vars/all.yml
role_zabbix_agent_server: "10.0.0.50"
```

To je sve. Hostname se izvodi iz `inventory_hostname`, aktivne provere idu na istu adresu.

### Kroz Zabbix proxy

```yaml
# group_vars/all.yml
role_zabbix_agent_server: "10.0.0.60"
role_zabbix_agent_server_active: "10.0.0.60:10051"
```

### Agent2

```yaml
role_zabbix_agent_package: zabbix-agent2
role_zabbix_agent_logfile: /var/log/zabbix/zabbix_agent2.log
```

Putanja loga se ne izvodi automatski — promeni je zajedno sa paketom.

### Automatska registracija

```yaml
role_zabbix_agent_host_metadata: "linux-production"
```

Na Zabbix strani napravi akciju koja hostove sa tim metapodatkom automatski dodaje u odgovarajuću grupu i template.

### Šifrovana veza preko PSK

Generiši ključ:

```bash
openssl rand -hex 32
```

Šifruj ga:

```bash
ansible-vault encrypt_string '<psk_hex>' --name 'role_zabbix_agent_tls_psk'
```

Rezultat upiši u `group_vars/all.yml`:

```yaml
role_zabbix_agent_tls_connect: psk
role_zabbix_agent_tls_accept: psk
role_zabbix_agent_tls_psk_identity: "PSK-produkcija"
role_zabbix_agent_tls_psk: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  38396264...
```

Isti identitet i ključ moraju biti upisani i na Zabbix strani, u podešavanjima hosta.

### Dozvoljavanje jedne komande

```yaml
role_zabbix_agent_allow_keys:
  - "system.run[/usr/local/bin/provera-diska.sh]"
```

Redosled je bitan: `AllowKey` linije se ispisuju pre `DenyKey`, pa izuzetak važi. Ne dozvoljavaj `system.run[*]` — time Zabbix server dobija mogućnost da izvršava proizvoljne komande na hostu.

### Poseban port

```yaml
# host_vars/srv-db-01.yml
role_zabbix_agent_listen_port: 10060
```

Ne zaboravi da isti port upišeš i na Zabbix strani, u interfejsu hosta.

---

## Napomene

**Rola upisuje sopstvenu konfiguraciju.** Fajl koji dolazi uz paket biva prepisan, uz `backup: true`. Razlog je predvidljivost — kada rola upravlja celim fajlom, sadržaj je uvek tačno ono što je u šablonu. Sporedna korist: nadogradnja paketa ne ostavlja `.dpkg-dist` fajlove za ručno mirenje.

**Ono što treba da preživi rolu ide u include folder:**

```text
/etc/zabbix/zabbix_agentd.d/*.conf     (zabbix-agent)
/etc/zabbix/zabbix_agent2.d/*.conf     (zabbix-agent2)
```

Tu paketi za dodatke sami upisuju svoje konfiguracije. Rola taj folder kreira ali njegov sadržaj ne dira.

**Rola ne otvara port na zaštitnom zidu.** Zabbix server mora moći da dođe do porta 10050 na hostu. To je posao role `firewall`; dve role koje menjaju ista pravila su izvor sukoba.

**Hostname mora da se poklapa.** Ako se `role_zabbix_agent_hostname` razlikuje od imena hosta u Zabbix konfiguraciji, pasivne provere će raditi a aktivne neće — i to bez jasne greške. Podrazumevana vrednost `{{ inventory_hostname }}` znači da je ime iz `hosts.ini` merodavno.

**PSK fajl ima dozvole `0400` i vlasnika `zabbix`.** Agent odbija da startuje ako su dozvole šire. Task koristi `no_log: true`, pa se ključ ne pojavljuje u ispisu.

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje nad nepromenjenom konfiguracijom prijavljuje `ok`, ne `changed`, i ne restartuje servis. Restart se dešava samo kada se paket, konfiguracija ili PSK zaista promene.

---

## Struktura

```text
roles/zabbix_agent/
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
    └── zabbix_agent.conf.j2
```

`vars/main.yml` sadrži izvedene vrednosti — putanje i ime servisa koji se razlikuju između `zabbix-agent` i `zabbix-agent2`. To nisu podešavanja i ne menjaju se kroz `group_vars`.

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit deploy_zabbix_agent --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Stanje servisa
ansible srv-web-01 -m command -a "systemctl status zabbix-agent"

# Da li agent odgovara lokalno
ansible srv-web-01 -m command -a "zabbix_agentd -t agent.ping"

# Log
ansible srv-web-01 -m command -a "tail -20 /var/log/zabbix/zabbix_agentd.log"
```

Sa Zabbix servera, provera da agent odgovara spolja:

```bash
zabbix_get -s srv-web-01 -k agent.ping
```

Odgovor `1` znači da veza radi. `Connection refused` je skoro uvek zaštitni zid ili `ListenIP`.
