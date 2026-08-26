# Rola: users

Upravlja korisničkim nalozima, grupama, SSH ključevima i sudo pravilima.

Rola je **aditivna**: nalozi koji nisu navedeni u `role_users_list` se ne diraju. Nema režima koji briše sve što nije opisano — uklanjanje naloga je uvek eksplicitno, kroz `state: absent`.

---

## Preduslovi

Kolekcija `ansible.posix` (modul `authorized_key`):

```bash
ansible-galaxy collection install ansible.posix
```

---

## Aktivacija

```ini
# inventory/hosts.ini
[apply_users]
srv-web-01
srv-web-02
```

Grupi pripada `group_vars/apply_users.yml`, koji postavlja `role_users_enabled: true`. Taj fajl ne treba dirati.

Izuzetak po hostu:

```yaml
# inventory/host_vars/srv-db-01.yml
role_users_enabled: false
```

---

## Šta rola radi

| Korak | Opis |
|---|---|
| 1 | Proverava strukturu liste, heš lozinke, zaštićene naloge |
| 2 | Kreira grupe iz `role_users_groups` |
| 3 | Kreira i ažurira naloge iz `role_users_list` |
| 4 | Podešava dozvole nad kućnim folderom (opciono) |
| 5 | Upisuje SSH ključeve u `authorized_keys` |
| 6 | Upisuje sudo pravila u `/etc/sudoers.d/` |
| 7 | Briše naloge sa `state: absent` |

---

## Varijable

### Aktivacija

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_users_enabled` | `false` | Kada je `false`, rola ne dira ništa. |

### Liste

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_users_groups` | `[]` | Grupe koje treba kreirati pre naloga. |
| `role_users_list` | `[]` | Nalozi. |

### Podrazumevane vrednosti za naloge

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_users_default_shell` | `/bin/bash` | Shell za naloge koji ga ne zadaju. |
| `role_users_default_groups` | `[]` | Grupe koje dobija svaki nalog. |
| `role_users_append_groups` | `true` | `false` **zamenjuje** članstvo umesto da dodaje. |
| `role_users_create_home` | `true` | Kreiranje kućnog foldera. |
| `role_users_home_mode` | `""` | Dozvole nad kućnim folderom. Prazno = ne diraj. |
| `role_users_update_password` | `always` | `always` ili `on_create`. |

### SSH ključevi

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_users_ssh_key_exclusive` | `false` | Uklanja ključeve koji nisu navedeni. |

### Sudo

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_users_sudo_enabled` | `true` | Globalni prekidač za `/etc/sudoers.d/`. |
| `role_users_sudo_file_prefix` | `user-` | Prefiks imena fajla. |
| `role_users_sudo_commands` | `ALL` | Komande za nalog sa `sudo: true`. |
| `role_users_sudo_nopasswd` | `false` | Sudo bez lozinke. |

### Brisanje

| Varijabla | Podrazumevano | Opis |
|---|---|---|
| `role_users_remove_home` | `false` | **Nepovratno.** Briše i kućni folder. |
| `role_users_protected` | `[root, daemon, ...]` | Nalozi koji se ne smeju obrisati. |

---

## Struktura naloga

| Polje | Obavezno | Opis |
|---|---|---|
| `name` | da | Ime naloga. |
| `state` | ne | `present` (podrazumevano) ili `absent`. |
| `comment` | ne | Polje u `/etc/passwd`. |
| `uid` | ne | Fiksan UID. |
| `groups` | ne | Lista dodatnih grupa. |
| `append` | ne | Nadjačava `role_users_append_groups`. |
| `shell` | ne | Nadjačava `role_users_default_shell`. |
| `home` | ne | Kućni folder. |
| `create_home` | ne | Nadjačava `role_users_create_home`. |
| `system` | ne | Sistemski nalog. |
| `password` | ne | **Heš**, nikada čist tekst. |
| `password_lock` | ne | Zaključava lozinku. |
| `ssh_keys` | ne | Lista javnih ključeva. |
| `ssh_key_exclusive` | ne | Nadjačava globalnu vrednost. |
| `sudo` | ne | `true` za pun pristup, ili string sa komandama. |
| `sudo_nopasswd` | ne | Nadjačava `role_users_sudo_nopasswd`. |

---

## Struktura grupe

| Polje | Obavezno | Opis |
|---|---|---|
| `name` | da | Ime grupe. |
| `gid` | ne | Fiksan GID. |
| `system` | ne | Sistemska grupa. |
| `state` | ne | `present` (podrazumevano) ili `absent`. |

Sistemske grupe (`sudo`, `adm`, `docker`) već postoje — ne treba ih navoditi, samo koristiti u polju `groups` naloga.

---

## Primeri

### Administratori na svim hostovima

```yaml
# inventory/group_vars/all.yml
role_users_list:
  - name: milan
    comment: "Milan Petrovic"
    groups: [sudo, adm]
    ssh_keys:
      - "ssh-ed25519 AAAAC3Nz... milan@laptop"
    sudo: true

  - name: jelena
    comment: "Jelena Nikolic"
    groups: [sudo]
    ssh_keys:
      - "ssh-ed25519 AAAAC3Nz... jelena@laptop"
      - "ssh-ed25519 AAAAC3Nz... jelena@desktop"
    sudo: true
```

Sa podrazumevanim `role_users_sudo_nopasswd: false` oba naloga moraju uneti sopstvenu lozinku pri `sudo` pozivu. Za to im lozinka mora biti postavljena — vidi primer ispod.

### Servisni nalog sa uskim sudo pravilom

```yaml
role_users_list:
  - name: deploy
    comment: "Nalog za isporuku aplikacije"
    ssh_keys:
      - "ssh-ed25519 AAAAC3Nz... ci@runner"
    sudo: "/usr/bin/systemctl restart aplikacija, /usr/bin/systemctl status aplikacija"
    sudo_nopasswd: true
```

Rezultat u `/etc/sudoers.d/user-deploy`:

```text
deploy ALL=(ALL) NOPASSWD:/usr/bin/systemctl restart aplikacija, /usr/bin/systemctl status aplikacija
```

### Nalog sa lozinkom

Heš se pravi na kontrolnom čvoru:

```bash
mkpasswd --method=yescrypt        # Ubuntu 24.04 podrazumevano
openssl passwd -6                 # SHA-512, radi svuda
```

Heš je osetljiv podatak i pripada vault-u:

```bash
ansible-vault encrypt_string --name 'lozinka_milan' '$y$j9T$...'
```

```yaml
role_users_list:
  - name: milan
    password: "{{ lozinka_milan }}"
    groups: [sudo]
```

### Namenska grupa

```yaml
role_users_groups:
  - name: operateri
    gid: 3000

role_users_list:
  - name: operater1
    groups: [operateri]
  - name: operater2
    groups: [operateri]
```

Grupa se kreira pre naloga — obrnut redosled bi značio da nalog pokušava da uđe u grupu koja ne postoji.

### Naloge samo na jednom hostu

```yaml
# inventory/host_vars/srv-db-01.yml
role_users_list:
  - name: dba
    comment: "Administrator baze"
    groups: [sudo]
    ssh_keys:
      - "ssh-ed25519 AAAAC3Nz... dba@laptop"
```

`host_vars` **zamenjuje** globalnu listu, ne dodaje na nju. Ako host treba i globalne i sopstvene naloge, nabroj sve.

### Uklanjanje naloga

```yaml
role_users_list:
  - name: bivsi-kolega
    state: absent
```

Kućni folder ostaje. Da bi i on nestao:

```yaml
role_users_remove_home: true
```

Ovo je nepovratno — arhiviraj podatke pre pokretanja.

### Zatvoreni kućni folderi

```yaml
role_users_home_mode: '0750'
```

---

## Napomene

**Lozinka mora biti heš.** Čist tekst `useradd` upisuje doslovno u `/etc/shadow`. Nalog tada postaje trajno nedostupan, a nijedna komanda to ne prijavljuje kao grešku — prijava jednostavno ne prolazi. Rola to hvata `assert`-om koji traži da vrednost počinje znakom `$`.

**`sudo` ignoriše fajlove sa tačkom u imenu.** Naziv `user-marko.petrovic` bi bio uredno upisan i nikada pročitan. Rola iz imena naloga uklanja sve osim slova, cifara, crte i donje crte, pa fajl postaje `user-marko_petrovic`.

**Sudo pravilo se proverava pre upisa.** Task koristi `validate: 'visudo -cf %s'`. Neispravan fajl u `/etc/sudoers.d/` može onesposobiti `sudo` na celom sistemu, pa sadržaj stiže na disk tek kada `visudo` potvrdi sintaksu.

**`role_users_append_groups: false` briše članstva.** Nalog gubi svaku grupu koja nije navedena u njegovom `groups`. Ako je nalog bio u `sudo` grupi a to nije zapisano u inventory-ju, gubi administratorski pristup pri prvom pokretanju.

**`ssh_key_exclusive` briše ručno dodate ključeve.** Korisno pri rotaciji, opasno u svakodnevnom radu. Proveri `authorized_keys` pre uključivanja.

**Rola ne dira nalog `ansible`.** Tim nalogom upravlja rola `ansible_user`, kroz `playbooks/bootstrap.yml`. Ako se nađe sa `state: absent`, `assert` prekida rad — brisanje naloga pod kojim Ansible radi prekinulo bi vezu usred pokretanja.

**Rola ne dira `/etc/ssh/sshd_config`.** Ograničavanje prijave po grupi (`AllowGroups`) pripada zasebnoj roli. Dve role koje menjaju isti fajl su izvor sukoba.

**Promena `shell`-a prijavljenom korisniku.** Izmena važi od sledeće prijave; postojeća sesija zadržava stari shell.

**Rola nema handler.** Nijedna izmena ne zahteva restart servisa. Nalozi i ključevi važe odmah, za svaku narednu prijavu.

---

## Struktura

```text
roles/users/
├── README.md
├── defaults/
│   └── main.yml
├── vars/
│   └── main.yml
├── tasks/
│   └── main.yml
└── templates/
    └── sudoers.j2
```

`vars/main.yml` sadrži putanju do `sudoers.d` i prošireni spisak zaštićenih naloga — nalog pod kojim se Ansible povezuje se dodaje automatski, iz `ansible_user`, `ansible_user_id` i `role_ansible_user_name`.

---

## Idempotentnost

Rola je idempotentna. Moduli `user`, `group` i `authorized_key` porede trenutno stanje i menjaju ga samo pri razlici; `template` upisuje samo pri razlici u sadržaju.

Jedan izuzetak: sa `role_users_update_password: always` i hešom koji koristi nasumičnu so, modul upoređuje same heševe, ne lozinke. Isti heš u inventory-ju daje `ok`; novi heš iste lozinke daje `changed`.

---

## Provera

```bash
# Bez izmena, sa prikazom razlike
./apply.sh --limit apply_users --check --diff

# Primena na jedan host
./apply.sh --limit srv-web-01

# Da li nalog postoji i u kojim je grupama
ansible srv-web-01 -m command -a "id milan"

# Ključevi
ansible srv-web-01 -m command -a "cat /home/milan/.ssh/authorized_keys"

# Sudo pravila koja je upisala rola
ansible srv-web-01 -m command -a "ls -l /etc/sudoers.d/"

# Šta nalog sme
ansible srv-web-01 -m command -a "sudo -l -U milan"
```

`sudo -l -U` je bolja provera od čitanja fajla — pokazuje spojen rezultat svih pravila, uključujući i ona iz `/etc/sudoers`.

---

## Rešavanje problema

**`assert` prijavljuje da lozinka nije heš**

Vrednost ne počinje znakom `$`. Napravi heš sa `mkpasswd --method=yescrypt` ili `openssl passwd -6` i upiši rezultat, ne lozinku.

**`Group X does not exist`**

Nalog navodi grupu koje nema ni na sistemu ni u `role_users_groups`. Dodaj je u listu grupa.

**`userdel: user is currently used by process`**

Nalog ima pokrenut proces. Rola koristi `force: true`, što to rešava u većini slučajeva; ako i dalje pada, proveri:

```bash
ansible srv-web-01 -m command -a "ps -u bivsi-kolega"
```

**Sudo pravilo je upisano ali ne važi**

Ime fajla sadrži znak koji `sudo` ne prihvata, ili je pravilo nadjačano kasnijim fajlom. Proveri stvarni rezultat:

```bash
sudo -l -U milan
```

**Nalog ne može da se prijavi iako ključ postoji**

Najčešće dozvole. `authorized_key` postavlja ispravne, ali ručne izmene ih znaju pokvariti:

```bash
ls -ld /home/milan/.ssh          # 0700, vlasnik milan
ls -l  /home/milan/.ssh/authorized_keys   # 0600, vlasnik milan
```

Drugi čest uzrok je kopiran privatni umesto javnog ključa — javni se završava na `.pub` i staje u jednu liniju.

**Nalog izgubio članstvo u grupi posle pokretanja**

`role_users_append_groups` je `false`, a grupa nije navedena u `groups` tog naloga.

**Korisnik promenio lozinku, pa mu je vraćena stara**

`role_users_update_password` je `always`. Postavi `on_create` ako lozinkama upravljaju sami korisnici.
