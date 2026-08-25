# Rola: ansible_user

Priprema sveže instaliran server za upravljanje ostalim rolama iz ovog repozitorijuma.

Rola kreira namenski nalog za automatizaciju, postavlja SSH ključ kontrolnog čvora i upisuje sudo pravilo. Nakon toga se server može normalno koristiti kroz `apply.sh`.

---

## Zašto je ova rola drugačija

Sve ostale role se povezuju kao `ansible` korisnik, sa ključem. Ova rola **tek stvara taj nalog** — u trenutku njenog pokretanja on ne postoji.

Zato se ne pokreće kroz `playbook.yml`, nego kroz zaseban `playbooks/bootstrap.yml`, i to pod postojećim nalogom na serveru (`root`, `admin`, cloud-init korisnik).

Iz istog razloga grupa se zove `[bootstrap]`, bez `apply_` ili `deploy_` prefiksa — ne pripada svakodnevnom toku.

---

## Preduslovi

Javni ključ kontrolnog čvora mora biti upisan pre pokretanja:

```yaml
# inventory/group_vars/all.yml
role_ansible_user_ssh_key: "ssh-ed25519 AAAAC3Nz... ansible@control"
```

Ključ pročitaš sa:

```bash
cat ~/.ssh/id_ed25519.pub
```

Ako ključ još ne postoji:

```bash
ssh-keygen -t ed25519 -C "ansible@control"
```

Bez popunjene vrednosti rola prekida rad na prvom tasku. To je namerno — nalog bez ključa bio bi nedostupan.

---

## Upotreba

**1.** Dodaj host u grupu `[bootstrap]`:

```ini
# inventory/hosts.ini
[bootstrap]
srv-web-01
```

**2.** Pokreni bootstrap playbook pod postojećim nalogom:

```bash
cd /opt/ansible/production

ansible-playbook ../linux/playbooks/bootstrap.yml \
  --limit srv-web-01 \
  --user root --ask-pass --ask-become-pass
```

Zastavice zavise od toga kako pristupaš serveru:

| Situacija | Zastavice |
|---|---|
| root sa lozinkom | `--user root --ask-pass` |
| sudo korisnik sa lozinkom | `--user admin --ask-pass --ask-become-pass` |
| cloud-init sa ključem | `--user ubuntu` |

**3.** Proveri da ključ i sudo rade:

```bash
ssh ansible@srv-web-01 sudo whoami
```

Očekivani izlaz je `root`, bez pitanja za lozinku.

**4.** Prebaci host u ostale grupe i ukloni ga iz `[bootstrap]`:

```ini
[apply_timezone]
srv-web-01

[apply_banner]
srv-web-01
```

Od tog trenutka host se koristi normalno, kroz `./apply.sh`.

---

## Šta rola radi

| Korak | Opis |
|---|---|
| 1 | Proverava da je SSH ključ zadat i da liči na javni ključ |
| 2 | Instalira Python ako nedostaje (preko `raw` modula) |
| 3 | Kreira nalog sa zaključanom lozinkom |
| 4 | Postavlja SSH ključ u `authorized_keys` |
| 5 | Upisuje sudo pravilo u `/etc/sudoers.d/` |

---

## Varijable

### Aktivacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_ansible_user_enabled` | `false` | Kada je `false`, rola ne dira ništa. |

### Nalog

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_ansible_user_name` | `ansible` | Ime naloga. |
| `role_ansible_user_home` | `/home/ansible` | Kućni folder. |
| `role_ansible_user_shell` | `/bin/bash` | Podrazumevani shell. |
| `role_ansible_user_groups` | `[]` | Dodatne grupe. |
| `role_ansible_user_comment` | `Ansible automation account` | Komentar u `/etc/passwd`. |
| `role_ansible_user_password_lock` | `true` | Zaključava lozinku — prijava isključivo ključem. |

### SSH ključ

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_ansible_user_ssh_key` | `""` | **Obavezno.** Javni ključ kontrolnog čvora. |
| `role_ansible_user_ssh_key_extra` | `[]` | Dodatni ključevi. |
| `role_ansible_user_ssh_key_exclusive` | `false` | Uklanja sve ključeve koji nisu navedeni. |

### Sudo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_ansible_user_sudo_enabled` | `true` | Upisuje sudo pravilo. |
| `role_ansible_user_sudo_file` | `ansible` | Ime fajla u `/etc/sudoers.d/`. |
| `role_ansible_user_sudo_nopasswd` | `true` | Sudo bez lozinke. |
| `role_ansible_user_sudo_commands` | `ALL` | Dozvoljene komande. |

### Python

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_ansible_user_install_python` | `true` | Instalira Python ako nedostaje. |
| `role_ansible_user_python_package_debian` | `python3` | Ime paketa na Debian/Ubuntu. |
| `role_ansible_user_python_package_redhat` | `python3` | Ime paketa na RHEL/Rocky/Alma. |

---

## Primeri

### Drugo ime naloga

```yaml
# inventory/group_vars/all.yml
role_ansible_user_name: automation
role_ansible_user_home: /home/automation
```

Ako promeniš ime, dodaj ga i u `ansible.cfg` radnog foldera:

```ini
[defaults]
remote_user = automation
```

### Rezervni ključ drugog administratora

```yaml
role_ansible_user_ssh_key_extra:
  - "ssh-ed25519 AAAAC3Nz... backup@control"
```

### Ograničen sudo

```yaml
role_ansible_user_sudo_commands: "/usr/bin/systemctl, /usr/bin/dnf, /usr/bin/apt-get"
```

Sužava posledice kompromitovanog ključa, ali će mnoge role prestati da rade. Koristi samo ako tačno znaš koje komande su potrebne.

### Uklanjanje starih ključeva

```yaml
role_ansible_user_ssh_key_exclusive: true
```

Korisno pri rotaciji ključeva. Ručno dodati ključevi biće obrisani — proveri `authorized_keys` pre nego što uključiš.

---

## Bezbednosne napomene

**Sudo bez lozinke je podrazumevan.** Neophodan je za neinteraktivno pokretanje, ali znači da ko dođe do privatnog ključa kontrolnog čvora dobija root na svim serverima. Privatni ključ mora biti zaštićen odgovarajuće — po mogućstvu passphrase-om uz `ssh-agent`.

**Rola ne dira `/etc/ssh/sshd_config`.** Zabrana prijave lozinkom i root prijave ostaje ručna, svesna odluka. To je namerno: ako zabraniš lozinke pre nego što potvrdiš da ključ radi, ostaješ zaključan izvan servera.

Kada potvrdiš korak 3 iz uputstva, izmene možeš uraditi ručno:

```text
PasswordAuthentication no
PermitRootLogin no
```

Uvek zadrži otvorenu drugu SSH sesiju dok testiraš — ako nešto pođe naopako, imaš put nazad.

**Sudo pravilo se proverava pre upisa.** Task koristi `validate: 'visudo -cf %s'`. Neispravan fajl u `/etc/sudoers.d/` može onesposobiti `sudo` na celom sistemu, pa se sadržaj upisuje samo ako `visudo` potvrdi sintaksu.

---

## Tehničke napomene

**`gather_facts: false` u bootstrap playbook-u.** Prikupljanje podataka zahteva Python, kojeg na minimalnom image-u nema. Rola prvo instalira Python preko `raw` modula — jedinog koji radi bez njega — pa tek onda eksplicitno poziva `setup`.

**Zavisnost od kolekcije.** Task za SSH ključ koristi `ansible.posix.authorized_key`. Kolekcija je uključena u pun `ansible` paket, ali ne i u `ansible-core`:

```bash
ansible-galaxy collection install ansible.posix
```

**Idempotentnost.** Rola je idempotentna. Ponovljeno pokretanje nad pripremljenim serverom prijavljuje `ok`, ne `changed`. Bezbedno je pokrenuti je ponovo — na primer pri rotaciji ključeva.

---

## Struktura

```text
roles/ansible_user/
├── README.md
├── defaults/
│   └── main.yml
└── tasks/
    └── main.yml
```

Rola nema `handlers/` — nijedna izmena ne zahteva restart servisa.

---

## Rešavanje problema

**`Permission denied (publickey)` posle bootstrap-a**

Proveri da je ključ zaista stigao:

```bash
ansible srv-web-01 -m command -a "cat /home/ansible/.ssh/authorized_keys" \
  --user root --ask-pass
```

Najčešći uzrok je kopiran privatni umesto javnog ključa. Javni se završava na `.pub` i staje u jednu liniju.

**`sudo: a password is required`**

Sudo pravilo nije upisano ili je `role_ansible_user_sudo_nopasswd` postavljen na `false`:

```bash
ssh ansible@srv-web-01 sudo cat /etc/sudoers.d/ansible
```

**Playbook pada na `gather_facts` ili `setup`**

Python nedostaje, a `role_ansible_user_install_python` je `false`. Uključi ga, ili instaliraj Python ručno pre pokretanja.

**`assert` puca na prvom tasku**

`role_ansible_user_ssh_key` je prazan ili ne počinje sa `ssh-` odnosno `ecdsa-`. Poruka greške sadrži tačno uputstvo.
