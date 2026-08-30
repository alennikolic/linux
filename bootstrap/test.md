# Modul 7: Performanse iz ugla sistemca

*MySQL za Linux administratore*

---

## Uvod: šta jeste, a šta nije vaš posao

Reč "optimizacija MySQL-a" pokriva dve potpuno različite discipline.

**Prva je optimizacija upita i šeme.** Indeksi, planovi izvršavanja, denormalizacija, prepisivanje `JOIN`-ova. To je posao developera ili DBA i o tome smo se dogovorili još u Modulu 1.

**Druga je podešavanje servera i sistema pod njim.** Koliko memorije, koliko konekcija, kako se piše na disk, kako se kernel ponaša. To je vaš posao i o tome je ovaj modul.

Postoji i treća stvar koju ćete raditi češće nego što očekujete: **dokazivanje da problem uopšte nije u bazi.** Tome je posvećeno poslednje poglavlje i, po mom iskustvu, ono je najkorisnije u celom modulu.

### Pravilo pre svih pravila

Internet je pun "MySQL tuning" članaka sa spiskovima od pedeset parametara. Većina je pisana za MySQL 5.5, mnogi savetuju stvari koje su danas štetne, a gotovo svi izostavljaju najvažniju rečenicu:

> **Ne menjajte parametar koji ne razumete i ne merite.**

Podrazumevane vrednosti u MySQL 8 su znatno bolje nego što su bile. Broj parametara koje zaista treba da dirate je mali — možda desetak. Sve preko toga je ili prerano ili pogrešno.

Redosled po važnosti, iskreno:

1. **`innodb_buffer_pool_size`** — jedini parametar koji svakako morate podesiti.
2. **Fajl deskriptori i konekcije** — jer neispravno podešeni proizvode ispade.
3. **`fsync` politika** — jer određuje odnos brzine i sigurnosti podataka.
4. **Kernel podešavanja** — swap, THP, NUMA.
5. **Sve ostalo** — retko vredi truda.

---

## 33. `innodb_buffer_pool_size`

### Šta je buffer pool

InnoDB drži podatke i indekse u memorijskom kešu koji se zove buffer pool. Kada upit traži red, InnoDB prvo gleda u buffer pool; ako ga tamo nema, mora na disk.

Razlika u brzini između ta dva slučaja je nekoliko redova veličine. Zato je ovo najvažniji parametar.

```sql
SELECT @@innodb_buffer_pool_size / 1024 / 1024 / 1024 AS gb;
```

Ako dobijete `0.125` — to je podrazumevanih 128 MB i to je premalo za bilo šta ozbiljno.

### Koliko dodeliti

Klasična preporuka je 50–75% RAM-a na namenskom serveru baze. To je dobra polazna tačka, ali nije cela priča.

**Bolje pravilo: dodelite onoliko koliko iznosi vaš radni skup podataka, plus rezerva.**

Ako je cela baza 6 GB, a server ima 64 GB RAM-a, nema svrhe dodeliti 40 GB. Dodelite 8 GB, cela baza staje u memoriju, a ostatak neka koristi operativni sistem.

Koliko podataka zapravo imate:

```sql
SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS gb
FROM information_schema.tables
WHERE engine = 'InnoDB';
```

Odluka:

| Situacija | Buffer pool |
|---|---|
| Baza staje u RAM sa rezervom | veličina baze × 1,2 |
| Namenski server, baza veća od RAM-a | 60–70% RAM-a |
| Server deli poslove sa aplikacijom | 25–40% RAM-a, uz merenje |
| Kontejner sa ograničenjem memorije | 50% ograničenja, ne 50% RAM-a hosta |

Poslednji red je čest previd: MySQL u kontejneru vidi ceo RAM hosta, ali ga cgroup ograničava. Ako dodelite buffer pool prema onome što `free -h` pokazuje, kontejner će biti ubijen.

### Promena bez restarta

Od MySQL 5.7.5 ovaj parametar je **dinamičan**:

```sql
SET GLOBAL innodb_buffer_pool_size = 10737418240;  -- 10 GB
```

Promena se dešava postepeno, u komadima. Pratite napredak:

```sql
SHOW STATUS LIKE 'InnoDB_buffer_pool_resize_status';
```

```bash
sudo tail -f /var/log/mysql/error.log | grep -i resiz
```

Kada vidite `Completed resizing buffer pool`, gotovo je.

Za trajno, u konfiguraciju (Modul 2):

```ini
[mysqld]
innodb_buffer_pool_size = 10G
```

**Napomena o smanjivanju:** povećanje je bezbedno; smanjivanje na opterećenom serveru može privremeno usporiti rad dok se stranice izbacuju. Smanjujte u periodu manjeg opterećenja.

### Zašto dobijate više nego što ste tražili

```sql
SELECT @@innodb_buffer_pool_size / 1024 / 1024 AS mb,
       @@innodb_buffer_pool_chunk_size / 1024 / 1024 AS chunk_mb,
       @@innodb_buffer_pool_instances AS instanci;
```

Stvarna veličina se zaokružuje naviše na umnožak `chunk_size × instances`. Sa podrazumevanim `chunk_size = 128M` i 8 instanci, jedinica zaokruživanja je 1 GB.

Ako tražite 10,5 GB, dobićete 11 GB. Nije greška — to je način na koji InnoDB deli pool.

Broj instanci: podrazumevano 8 kada je pool bar 1 GB. Deljenje na instance smanjuje nadmetanje niti oko istog mutex-a. Za pool ispod 1 GB, jedna instanca je dovoljna.

### Da li je veličina dovoljna

Nekoliko pokazatelja, po korisnosti:

**Odnos čitanja sa diska prema ukupnim čitanjima:**

```sql
SELECT
  ROUND(100 - (
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_reads') * 100.0 /
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_read_requests')
  ), 3) AS pogodak_pct;
```

Vrednosti iznad 99% su dobre. Ispod 95% na serveru koji radi već neko vreme znači da pool nije dovoljan.

**Oprez:** ovo je kumulativna vrednost od starta servera. Odmah nakon restarta je beznačajna, jer je pool prazan. Merite tek posle nekoliko sati rada, i pratite trend, ne apsolutni broj (Modul 6).

**Slobodne stranice:**

```sql
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_%';
```

Ako je `Innodb_buffer_pool_pages_free` trajno velik broj, pool je veći nego što treba i memorija stoji neiskorišćena. Ako je stalno blizu nule, pool je pun — što je normalno, ali u kombinaciji sa niskim procentom pogodaka znači da treba više.

**Praktičan test:** povećajte pool i posmatrajte da li se prosečno vreme odziva popravlja i da li opada broj čitanja sa diska (`iostat`). Ako se ne menja ništa, imali ste dovoljno.

### Zagrevanje nakon restarta

```sql
SELECT @@innodb_buffer_pool_dump_at_shutdown,
       @@innodb_buffer_pool_load_at_startup,
       @@innodb_buffer_pool_dump_pct;
```

U MySQL 8 su prve dve podrazumevano uključene. Pri gašenju se u `ib_buffer_pool` upisuje spisak stranica (ne podaci, samo spisak), a pri startu se te stranice unapred učitavaju.

Bez ovoga, server nakon restarta radi sporo dok se pool ne napuni — na velikim bazama to može trajati satima, a korisnici to osećaju.

Ručno, pred planiran restart:

```sql
SET GLOBAL innodb_buffer_pool_dump_now = ON;
```

`innodb_buffer_pool_dump_pct` podrazumevano iznosi 25 — snima se spisak četvrtine najkorišćenijih stranica. Za brže zagrevanje možete podići na 50 ili 75, uz duži start.

---

## 34. Koliko RAM-a MySQL zaista troši

Ovo je poglavlje koje sprečava klasu problema u kojoj server bez očiglednog razloga ode u swap ili ga ubije OOM killer.

### Dve vrste bafera

**Globalni baferi** — alociraju se jednom, pri startu, i dele ih sve konekcije.

**Baferi po konekciji** — alociraju se po potrebi, za svaku konekciju posebno. Ovo je deo koji ljudi potcene.

### Globalni deo

```sql
SELECT
  @@innodb_buffer_pool_size / 1024 / 1024 AS buffer_pool_mb,
  @@innodb_log_buffer_size / 1024 / 1024 AS log_buffer_mb,
  @@key_buffer_size / 1024 / 1024 AS key_buffer_mb,
  @@tmp_table_size / 1024 / 1024 AS tmp_table_mb;
```

- **`innodb_buffer_pool_size`** — glavnina. Dodajte ~5% za upravljačke strukture samog pool-a.
- **`innodb_log_buffer_size`** — podrazumevano 16 MB, retko treba dirati.
- **`key_buffer_size`** — keš za **MyISAM** indekse. Ako nemate MyISAM tabela (proverite kao u Modulu 5), spustite na 8 MB. Podrazumevana vrednost često nepotrebno zauzima memoriju.
- **`performance_schema`** — troši značajno, ponekad nekoliko stotina megabajta. Vredi ga imati, ali ga uračunajte.

### Deo po konekciji

```sql
SELECT
  @@sort_buffer_size / 1024 AS sort_kb,
  @@join_buffer_size / 1024 AS join_kb,
  @@read_buffer_size / 1024 AS read_kb,
  @@read_rnd_buffer_size / 1024 AS read_rnd_kb,
  @@binlog_cache_size / 1024 AS binlog_cache_kb,
  @@thread_stack / 1024 AS thread_stack_kb,
  @@max_connections;
```

Ovi baferi se alociraju **po konekciji, a neki i više puta po upitu** — složen `JOIN` može alocirati više `join_buffer`-a odjednom.

Gruba procena najgoreg slučaja:

```
Ukupno ≈ buffer_pool × 1,05
       + log_buffer + key_buffer + performance_schema
       + max_connections × (sort + join + read + read_rnd + binlog_cache + thread_stack)
```

Primer sa podrazumevanim vrednostima i `max_connections = 500`:

```
po konekciji ≈ 256K + 256K + 128K + 256K + 32K + 1M ≈ 1,9 MB
500 konekcija ≈ 950 MB
```

Skoro gigabajt, pored buffer pool-a.

**Budite iskreni prema ovoj formuli: ona je provera zdravog razuma, ne predviđanje.** Retko su svi baferi alocirani na maksimum istovremeno, pa je stvarna potrošnja obično znatno manja. Ali gornja granica može biti i veća od izračunate, jer jedan upit ume da alocira više bafera. Formulu koristite da uočite besmislenu konfiguraciju, a stvarnu potrošnju merite.

### Klasična greška iz "tuning" članaka

```ini
# NE RADITE OVO
sort_buffer_size = 256M
join_buffer_size = 256M
read_buffer_size = 64M
max_connections = 500
```

Teorijski maksimum ovoga je preko 250 GB. U praksi server će otići u swap i pasti pod umerenim opterećenjem.

**Pravilo: baferi po konekciji ostaju mali globalno.** Ako jedan konkretan posao (veliki izvoz, migracija, izveštaj) treba više, podignite ga **za tu sesiju**:

```sql
SET SESSION sort_buffer_size = 64 * 1024 * 1024;
-- ... veliki upit ...
```

Time jedan posao dobija resurse, a ostalih 499 konekcija ne.

### Merenje stvarne potrošnje

Ne pretpostavljajte — merite.

**Iz operativnog sistema:**

```bash
ps -o pid,rss,vsz,comm -p "$(pgrep -x mysqld)"
grep VmRSS /proc/"$(pgrep -x mysqld)"/status
```

`VmRSS` je stvarno zauzeta fizička memorija. To je broj koji vas zanima.

**Iz MySQL-a, sa razlaganjem:**

```sql
SELECT event_name,
       ROUND(current_alloc / 1024 / 1024, 1) AS mb
FROM sys.memory_global_by_current_bytes
ORDER BY current_alloc DESC
LIMIT 15;
```

Ovo je izuzetno korisno — pokazuje **gde** memorija odlazi, po podsistemima. Ako vidite nešto neočekivano visoko, tu je odgovor.

Po korisniku i po niti:

```sql
SELECT user, current_allocated, total_allocated FROM sys.memory_by_user_by_current_bytes;
SELECT * FROM sys.memory_by_thread_by_current_bytes LIMIT 10;
```

### Preporučena raspodela na namenskom serveru

Za server od 32 GB koji radi samo bazu:

```
Buffer pool             20 GB   (62%)
Ostali globalni baferi   1 GB
Konekcije (realno)       2 GB
Operativni sistem        2 GB
Rezerva / page cache     7 GB
```

Rezerva nije rasipanje. Ona pokriva: skokove u broju konekcija, `mysqldump` koji radi u dva ujutru, page cache za binlogove, i prostor da server preživi neočekivano.

**Server koji koristi 98% RAM-a nije dobro podešen — on je na ivici.**

### Kontejneri

Ako MySQL radi u Dockeru ili Kubernetesu, obavezno:

```bash
docker run -m 8g ...
```

i buffer pool računajte prema **tom** ograničenju, ne prema RAM-u hosta. MySQL ne čita cgroup ograničenje sam od sebe.

---

## 35. Konekcije i fajl deskriptori

### `max_connections` — više nije bolje

```sql
SELECT @@max_connections;
SHOW GLOBAL STATUS LIKE 'Max_used_connections';
SHOW GLOBAL STATUS LIKE 'Threads_%';
```

Podrazumevano je 151.

Svaka konekcija je jedna nit u operativnom sistemu. Nit troši memoriju, a veliki broj aktivnih niti troši i CPU na prebacivanje konteksta. U nekom trenutku dodavanje konekcija **smanjuje** ukupnu propusnost.

Podsetnik iz Modula 6: **`Threads_running` je važnija metrika od `Threads_connected`.** Dvesta otvorenih konekcija od kojih 195 spava je normalno stanje aplikacije sa poolom. Trideset konekcija koje sve istovremeno rade na serveru sa osam jezgara nije.

Kako odrediti razumnu vrednost:

```
max_connections = zbir maksimuma svih aplikacionih poolova
                + rezerva za backup, monitoring i administratora
                + ~20% rezerve
```

Ako imate četiri aplikaciona servera sa poolom od po 50, to je 200, plus 10 za servisne naloge, plus rezerva — oko 260. Ne 1000 "za svaki slučaj", jer taj "svaki slučaj" znači da server pokušava da opsluži 1000 niti i pada.

Ako redovno udarate u limit, pravi problem su gotovo uvek upiti koji se ne završavaju, a ne broj konekcija (Modul 10).

### Rezervni administrativni ulaz — funkcija koju treba uključiti

MySQL 8 ima mogućnost koju malo ko koristi, a spašava situaciju: **zaseban administrativni port sa sopstvenom niti**, nezavisan od `max_connections`.

```ini
[mysqld]
admin_address = 127.0.0.1
admin_port = 33062
create_admin_listener_thread = ON
```

Nakon restarta:

```bash
mysql -h 127.0.0.1 -P 33062 -u root
```

Poenta: kada server odbija konekcije zbog `Too many connections`, vi se i dalje možete povezati i videti šta se dešava. Bez ovoga, u tom trenutku ostajete napolju baš kad vam je pristup najpotrebniji.

Naloga koji ovo koristi treba `SERVICE_CONNECTION_ADMIN` privilegiju (Modul 3). Port držite na `127.0.0.1` i pristupajte kroz SSH tunel (Modul 4).

**Ovo uključite na svakom produkcijskom serveru.** Košta jedan restart, a vredi u tačno onom trenutku kad je najgore.

### Keš niti

```sql
SHOW GLOBAL STATUS LIKE 'Threads_created';
SELECT @@thread_cache_size;
```

Ako `Threads_created` brzo raste, server neprekidno pravi i uništava niti, što je nepotreban trošak. To je znak da aplikacija otvara novu konekciju za svaki zahtev umesto da koristi pool.

```ini
thread_cache_size = 100
```

Ovo ublažava simptom. Pravo rešenje je connection pooling u aplikaciji — i to je nalaz koji prosleđujete developeru.

### Fajl deskriptori — lanac od tri karike

Ovo je tema koja spaja Modul 2 i praktične ispade.

MySQL otvara fajl za skoro svaku tabelu (`innodb_file_per_table`), plus logove, plus socket po konekciji. Na serveru sa nekoliko hiljada tabela to su hiljade deskriptora.

Lanac ograničenja:

```
systemd LimitNOFILE  →  proces mysqld  →  @@open_files_limit
```

**`/etc/security/limits.conf` ne važi za systemd servise.** Ovo je najčešća zamka: čovek podigne limit u `limits.conf`, restartuje MySQL, i ništa se ne promeni.

Provera cele tri karike:

```bash
systemctl show mysql -p LimitNOFILE
cat /proc/"$(pgrep -x mysqld)"/limits | grep -i "open files"
mysql -e "SELECT @@open_files_limit, @@table_open_cache, @@max_connections;"
```

Ako se vrednosti razlikuju, MySQL je sam smanjio svoje ograničenje da stane u ono što mu je OS dao — i pritom je verovatno tiho smanjio i `table_open_cache`.

Simptom kada ovo ne štima:

```
[ERROR] [MY-011292] [Server] Can't open file: errno: 24 - Too many open files
```

Errno 24. Ne mešati sa errno 13 iz Modula 2, koji je AppArmor.

**Rešenje:**

```bash
sudo systemctl edit mysql
```

```ini
[Service]
LimitNOFILE=65535
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart mysql
cat /proc/"$(pgrep -x mysqld)"/limits | grep -i "open files"
```

### `table_open_cache`

```sql
SHOW GLOBAL STATUS LIKE 'Opened_tables';
SHOW GLOBAL STATUS LIKE 'Table_open_cache_%';
SELECT @@table_open_cache, @@table_definition_cache;
```

Ako `Opened_tables` neprekidno raste tokom rada, keš je premalen — tabele se stalno otvaraju i zatvaraju. Podrazumevanih 4000 je uglavnom dovoljno; podignite tek ako brojka to pokaže, i tek nakon što ste podigli `LimitNOFILE`.

---

## 36. Disk i MySQL

### Šta baza radi sa diskom

Tri toka upisa, sa različitim zahtevima:

1. **Redo log** — mali, sekvencijalni, **veoma osetljiv na latenciju**. Svaki commit čeka ovde.
2. **Data fajlovi** — nasumični upisi, dešavaju se u pozadini, tolerišu kašnjenje.
3. **Binlog** — sekvencijalni, veličina zavisi od opterećenja.

Ključna posledica: **za bazu je latencija važnija od propusnosti.** Disk koji daje 2 GB/s sekvencijalno, a ima 10 ms latenciju na `fsync`, biće spor za OLTP opterećenje. NVMe uređaj sa niskim `fsync` vremenom biće brz iako mu je sekvencijalna brzina manja.

### Merenje

```bash
sudo apt install sysstat
iostat -x 1 5
```

Kolone koje gledate:

| Kolona | Značenje | Kada je problem |
|---|---|---|
| `r_await`, `w_await` | prosečno vreme I/O operacije (ms) | > 10 ms na SSD-u |
| `%util` | zauzetost uređaja | ~100% trajno |
| `aqu-sz` | prosečna dužina reda | trajno > broja diskova |

**`%util` na 100% ne mora značiti problem** na NVMe uređajima, jer oni obrađuju više zahteva paralelno. Gledajte `await` — to je broj koji korisnik oseća.

Ko troši I/O:

```bash
sudo iotop -o -P
```

Iz same baze:

```sql
SELECT file_name, count_read, count_write,
       ROUND(sum_number_of_bytes_read / 1024 / 1024) AS mb_read,
       ROUND(sum_number_of_bytes_write / 1024 / 1024) AS mb_write
FROM performance_schema.file_summary_by_instance
ORDER BY sum_number_of_bytes_write DESC
LIMIT 10;
```

Ovo pokazuje **koji fajlovi** troše I/O — često otkrije da je krivac binlog ili jedna konkretna tabela.

### `innodb_flush_log_at_trx_commit` — odluka o riziku

Ovo je najvažniji parametar za brzinu upisa i on nije tehničko, nego poslovno pitanje.

```sql
SELECT @@innodb_flush_log_at_trx_commit, @@sync_binlog;
```

| Vrednost | Ponašanje | Gubitak pri padu |
|---|---|---|
| **1** (podrazumevano) | `fsync` pri svakom commit-u | ništa |
| **2** | upis u OS keš, `fsync` jednom u sekundi | ništa pri padu `mysqld`; do 1s pri padu OS-a ili nestanku struje |
| **0** | upis i `fsync` jednom u sekundi | do 1s i pri padu `mysqld` |

Uz to ide `sync_binlog`:

| Vrednost | Ponašanje |
|---|---|
| **1** (podrazumevano) | `fsync` binloga pri svakom commit-u |
| **0** | OS odlučuje kada |
| **N** | na svakih N commit-a |

Kombinacija `(1, 1)` znači potpunu izdržljivost i najsporiji upis. Kombinacija `(2, 0)` može biti nekoliko puta brža.

**Kako doneti odluku:** postavite pitanje "koliko nas košta gubitak poslednje sekunde transakcija pri nestanku struje?"

- Prodavnica, banka, sistem naplate → `(1, 1)`. Nema rasprave.
- Analitika, logovanje, keš, podaci koji se mogu ponovo generisati → `(2, 0)` je razuman kompromis.
- **Ako imate replike, `(1, 1)` na primarnom je gotovo obavezno**, jer u suprotnom replika može otići dalje od primarnog nakon pada, što razbija replikaciju.

Odluku donosite zajedno sa vlasnikom sistema i **zapišite je**, zajedno sa obrazloženjem. Ovo je parametar koji će neko za dve godine promeniti "da bude brže" ne znajući šta menja.

Privremeno spuštanje tokom restore-a je legitimno i pomenuto je u Modulu 5.

### `innodb_flush_method`

```ini
[mysqld]
innodb_flush_method = O_DIRECT
```

Podrazumevano na Linuxu je `fsync`, što znači da podaci prolaze kroz page cache operativnog sistema — pa se isti podaci keširaju **dvaput**: u buffer pool-u i u page cache-u. To je čisto trošenje memorije.

`O_DIRECT` zaobilazi page cache za data fajlove. Preporučeno u gotovo svim slučajevima na namenskom serveru.

Izuzetak: ZFS. Tamo ostavite `fsync` i umesto toga podesite `primarycache=metadata` na strani ZFS-a (Modul 5).

### Veličina redo loga

```sql
SELECT @@innodb_redo_log_capacity / 1024 / 1024 AS mb;   -- MySQL 8.0.30+
-- starije verzije:
SELECT @@innodb_log_file_size / 1024 / 1024 AS mb, @@innodb_log_files_in_group;
```

Podrazumevanih 100 MB je malo za server sa intenzivnim upisom. Kada je redo log mali, InnoDB mora često da radi checkpoint — dakle da prazni prljave stranice na disk — što stvara talase I/O opterećenja i neujednačen odziv.

Preporuka: dovoljno da primi oko sat vremena upisa.

Merenje koliko upisujete:

```bash
mysql -e "SHOW ENGINE INNODB STATUS\G" | grep "Log sequence number"
sleep 60
mysql -e "SHOW ENGINE INNODB STATUS\G" | grep "Log sequence number"
```

Razlika, podeljena sa 60, daje bajtove u sekundi. Pomnožite sa 3600 i to je vaša ciljna veličina.

```ini
[mysqld]
innodb_redo_log_capacity = 4G
```

Cena: **duži crash recovery.** Veći redo log znači više toga da se primeni pri startu nakon pada (Modul 2). To je razmena koju svesno birate.

Od MySQL 8.0.30 ovaj parametar je dinamičan, što je velika olakšica.

### `innodb_io_capacity`

```sql
SELECT @@innodb_io_capacity, @@innodb_io_capacity_max;
```

Ovim govorite InnoDB-u koliko I/O operacija u sekundi vaš disk podnosi, da bi znao koliko agresivno da prazni stranice u pozadini.

Podrazumevanih 200/2000 potiče iz vremena rotacionih diskova.

| Uređaj | `io_capacity` | `io_capacity_max` |
|---|---|---|
| Rotacioni disk | 200 | 2000 |
| SATA SSD | 1000–2000 | 4000 |
| NVMe | 4000–10000 | 20000 |

Ne preterujte. Previsoke vrednosti teraju InnoDB da troši I/O na pozadinsko pražnjenje umesto na korisničke upite.

### Fajl sistem i montiranje

- **ext4 ili XFS.** Oba su dobra; XFS se blago bolje ponaša sa velikim fajlovima i paralelnim upisom.
- **`noatime`** u `/etc/fstab` (Modul 2).
- **Izbegavajte mrežno skladište** za `datadir` ako imate izbor. NFS i slična rešenja unose latenciju upravo tamo gde najviše smeta.

### I/O raspoređivač

```bash
cat /sys/block/nvme0n1/queue/scheduler
```

Za NVMe uređaje `none` je obično najbolji izbor — uređaj sam raspoređuje bolje od kernela. Za SATA SSD `mq-deadline`.

```bash
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler
```

Trajno, kroz udev pravilo ili kernel parametar.

---

## 37. Kernel podešavanja

### Swap

```bash
free -h
cat /proc/sys/vm/swappiness
```

**MySQL i swap se ne slažu.** Kada deo buffer pool-a završi u swap-u, pristup podacima koji bi trebalo da traje mikrosekunde traje milisekundama. Server izgleda kao da ima dovoljno memorije, a radi katastrofalno.

```bash
sudo sysctl -w vm.swappiness=1
echo "vm.swappiness=1" | sudo tee -a /etc/sysctl.d/99-mysql.conf
```

**Vrednost 1, ne 0.** Sa nulom kernel praktično nikad ne koristi swap, pa u kriznoj situaciji radije poziva OOM killer — koji ubija `mysqld` kao najveći proces. Vrednost 1 ostavlja swap kao poslednju odbranu.

Bolje od podešavanja `swappiness` je da uopšte ne dođete u tu situaciju — dakle da buffer pool bude realno dimenzionisan (poglavlje 34).

### Transparent Huge Pages

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

Ako piše `[always]`, isključite.

THP dodeljuje memoriju u blokovima od 2 MB umesto 4 KB. Za baze to donosi neujednačenu latenciju i nepotrebno trošenje memorije, jer se za male alokacije rezervišu veliki blokovi.

Trajno, kroz GRUB:

```bash
sudo nano /etc/default/grub
```

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet transparent_hugepage=never"
```

```bash
sudo update-grub
sudo reboot
```

Bez restarta, kroz systemd:

```ini
# /etc/systemd/system/disable-thp.service
[Unit]
Description=Iskljuci Transparent Huge Pages
Before=mysql.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### NUMA

```bash
numactl --hardware
```

Ako izlaz pokazuje više čvorova, server ima više fizičkih procesora i memorija je podeljena među njima.

Problem koji se javlja: Linux podrazumevano alocira memoriju na čvoru gde proces radi. `mysqld` pokuša da alocira ceo buffer pool na jednom čvoru, taj čvor se popuni, i kernel počne da radi swap — **iako je ukupno slobodne memorije napretek.** Ovo je poznato pod imenom "swap insanity" i simptom je zbunjujuć: `free -h` pokazuje slobodnu memoriju, a server swapuje.

Rešenje:

```ini
[mysqld]
innodb_numa_interleave = ON
```

Ovim se buffer pool ravnomerno raspoređuje po svim čvorovima.

Na jednoprocesorskom serveru ovo nije potrebno — a to je većina servera koje ćete videti.

### Prljave stranice

```bash
sysctl vm.dirty_ratio vm.dirty_background_ratio
```

Podrazumevane vrednosti (20 i 10) znače da se do 20% RAM-a može nagomilati kao neupisani podaci, a onda se sve odjednom prazni na disk. Na serveru sa 64 GB to je do 12 GB odjednom — talas koji zaustavi sve ostalo.

```bash
echo "vm.dirty_background_ratio = 5" | sudo tee -a /etc/sysctl.d/99-mysql.conf
echo "vm.dirty_ratio = 10"           | sudo tee -a /etc/sysctl.d/99-mysql.conf
sudo sysctl --system
```

Manje vrednosti znače češće, ali manje talase — ujednačeniji odziv.

### OOM killer

```bash
cat /proc/"$(pgrep -x mysqld)"/oom_score
cat /proc/"$(pgrep -x mysqld)"/oom_score_adj
```

Kada sistemu ponestane memorije, kernel bira žrtvu po veličini — a `mysqld` je gotovo uvek najveći proces.

```ini
# systemctl edit mysql
[Service]
OOMScoreAdjust=-600
```

Ovo smanjuje verovatnoću da MySQL bude izabran.

**Ali budite jasni sami sa sobom:** ovo je ublažavanje simptoma. Ako OOM killer dolazi po vaš MySQL, prava dijagnoza je da je memorija loše dimenzionisana. Vratite se na poglavlje 34.

### Regulator frekvencije procesora

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

Ako je `powersave`, procesor ostaje na niskoj frekvenciji dok se opterećenje ne prepozna — što unosi kašnjenje kod kratkih, čestih upita.

```bash
sudo apt install linux-tools-common linux-tools-generic
sudo cpupower frequency-set -g performance
```

Efekat je skroman, ali merljiv na latencijski osetljivim opterećenjima.

### Sve na jednom mestu

```bash
sudo tee /etc/sysctl.d/99-mysql.conf > /dev/null <<'EOF'
# Swap samo kao poslednja opcija
vm.swappiness = 1

# Ujednačeniji upis na disk
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# Mrežni bafferi za veliki broj konekcija
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 4096
EOF

sudo sysctl --system
```

---

## 38. Kada problem nije u bazi

Ovo poglavlje verovatno vredi više od svih prethodnih zajedno.

Situacija je uvek ista: aplikacija je spora, neko kaže "baza je spora", i vi treba ili da to popravite ili da pokažete da nije tako. Bez brojki, taj razgovor se ne dobija.

### Lanac dokaza

**Korak 1 — da li je sam server pod pritiskom?**

```bash
uptime
vmstat 1 5
free -h
iostat -x 1 5
```

Ako su `load average`, CPU, memorija i I/O u redu, server nije usko grlo. Već ste na pola puta.

**Korak 2 — da li MySQL uopšte radi nešto?**

```bash
mysqladmin extended-status -i 10 -r | grep -E 'Questions|Threads_running|Slow_queries|Innodb_rows_read'
```

Opcija `-r` prikazuje **razlike** između merenja, ne kumulativne vrednosti. To je ono što vam treba.

**Ako je `Threads_running` stalno 1–2, a aplikacija je spora, baza nije uzrok.** Ona sedi i čeka. Ovo je najčešći ishod cele analize.

**Korak 3 — koliko traju upiti, mereno u bazi?**

```sql
SELECT ROUND(SUM(total_latency) / 1000000000000, 2) AS ukupno_sek,
       SUM(exec_count) AS izvrsavanja
FROM sys.statement_analysis;

SELECT query, exec_count, avg_latency
FROM sys.statement_analysis
ORDER BY total_latency DESC LIMIT 10;
```

**Korak 4 — uporedite sa onim što meri aplikacija.**

Ovo je ključni korak. Ako aplikacioni monitoring kaže da "upit ka bazi traje 800 ms", a `sys.statement_analysis` kaže da isti upit traje 4 ms, razlika od 796 ms **nije u bazi**. Ona je u:

- uspostavljanju konekcije,
- mrežnoj latenciji,
- drajveru i ORM-u,
- serijalizaciji rezultata,
- čekanju na slobodnu konekciju u poolu.

**Korak 5 — koliko košta uspostavljanje konekcije?**

```bash
for i in $(seq 1 20); do
  /usr/bin/time -f "%e" mysql -h 10.0.1.10 -u app -p'...' -e "SELECT 1;" 2>&1 >/dev/null
done
```

Ako svaka konekcija traje 200 ms, a aplikacija otvara novu za svaki HTTP zahtev, to je vaš odgovor.

Potvrda iz baze:

```sql
SHOW GLOBAL STATUS LIKE 'Threads_created';
SHOW GLOBAL STATUS LIKE 'Connections';
```

Odnos `Threads_created / Connections` blizak jedinici znači da poola nema.

**Korak 6 — problem N+1.**

Klasičan ORM obrazac: umesto jednog upita sa `JOIN`-om, aplikacija izvršava jedan upit za listu pa još po jedan za svaki red.

```bash
mysqladmin extended-status -i 10 -r | grep -E '^\| Questions|^\| Com_select'
```

Podelite broj upita brojem zahteva koje aplikacija obradi u istom periodu. Ako jedna stranica generiše 400 upita, nijedno podešavanje servera to neće rešiti.

Svaki upit je brz. Zbir je katastrofa. Ovo je aplikacioni problem i to je nalaz koji predajete.

### `pt-stalk` za povremene probleme

Najgori slučaj je problem koji traje dva minuta jednom dnevno, uvek dok vi ne gledate.

```bash
sudo pt-stalk \
  --function status \
  --variable Threads_running \
  --threshold 40 \
  --daemonize \
  --dest /var/log/pt-stalk
```

`pt-stalk` sedi u pozadini, prati uslov, i **kada se uslov ispuni sam prikupi kompletnu dijagnostiku**: process listu, `SHOW ENGINE INNODB STATUS`, `vmstat`, `iostat`, `top`, mrežnu statistiku.

Sledećeg jutra imate snimak tačno onog trenutka koji vam je nedostajao. Ovo je jedan od najkorisnijih alata u celom kursu za probleme koji izmiču.

### Kako izgleda izveštaj

Vaš nalaz treba da bude ovakav, sa brojkama umesto stavova:

```
NALAZ — sporost aplikacije, 2026-08-30

Server:
  load average 0.8 na 8 jezgara — nije opterećen
  RAM: 20/32 GB, bez swap aktivnosti
  disk: w_await 0.4 ms, %util 12% — nije opterećen

MySQL:
  Threads_running: 1–3 u proseku (limit 200)
  Ukupno vreme upita: 4,2 s po minutu rada
  Najsporiji upit: 12 ms prosečno

Merenja aplikacije:
  Prosečno vreme "baza" po zahtevu: 640 ms
  Broj upita po zahtevu: 312

Zaključak:
  Baza obrađuje upite za ~12 ms i troši 7% svog kapaciteta.
  Jedan HTTP zahtev generiše 312 odvojenih upita, svaki sa
  uspostavljanjem konekcije (Threads_created ≈ Connections).

  Usko grlo je broj upita po zahtevu i nepostojanje
  connection poola, ne performanse baze.

Preporuka developerskom timu:
  1. Uvesti connection pool.
  2. Rešiti N+1 obrazac na stranici /narudzbine (312 → ~5 upita).

Prilozi: pt-query-digest izveštaj, pt-stalk snimak 14:23.
```

Ovo je dokument koji zatvara raspravu. Nije odbrana — to je dijagnoza sa merenjima.

I to je, na kraju, ono što ovaj kurs pokušava da vas nauči: ne da postanete DBA, nego da o bazi umete da govorite brojkama.

---

## Kontrolna lista na kraju modula

```bash
# 1. Buffer pool je realno dimenzionisan
mysql -e "SELECT @@innodb_buffer_pool_size/1024/1024/1024 AS gb;"
free -h

# 2. Stvarna potrošnja memorije je izmerena, ne pretpostavljena
grep VmRSS /proc/"$(pgrep -x mysqld)"/status
mysql -e "SELECT event_name, ROUND(current_alloc/1024/1024) AS mb
          FROM sys.memory_global_by_current_bytes
          ORDER BY current_alloc DESC LIMIT 10;"

# 3. Baferi po konekciji nisu naduvani
mysql -e "SELECT @@sort_buffer_size, @@join_buffer_size, @@max_connections;"

# 4. Fajl deskriptori štimaju kroz sve tri karike
systemctl show mysql -p LimitNOFILE
cat /proc/"$(pgrep -x mysqld)"/limits | grep -i "open files"
mysql -e "SELECT @@open_files_limit;"

# 5. Administrativni port je uključen
mysql -e "SELECT @@admin_port;" 2>/dev/null || echo "NIJE UKLJUCEN"

# 6. Odluka o fsync politici je doneta i zapisana
mysql -e "SELECT @@innodb_flush_log_at_trx_commit, @@sync_binlog;"

# 7. Redo log je dovoljno velik
mysql -e "SELECT @@innodb_redo_log_capacity/1024/1024 AS mb;"

# 8. io_capacity odgovara tipu diska
mysql -e "SELECT @@innodb_io_capacity, @@innodb_io_capacity_max;"

# 9. Kernel je podešen
sysctl vm.swappiness vm.dirty_ratio
cat /sys/kernel/mm/transparent_hugepage/enabled

# 10. Server ne swapuje
vmstat 1 5   # kolone si i so moraju biti 0
```

---

## Vežbe

**Vežba 1 — Uticaj buffer pool-a, izmeren**
Napravite tabelu veću od trenutnog buffer pool-a. Izmerite trajanje punog skeniranja. Zatim podignite pool `SET GLOBAL` naredbom tako da tabela stane, ponovite dva puta i uporedite sva tri rezultata. Objasnite zašto je drugo merenje sporo, a treće brzo.

**Vežba 2 — Dinamička promena i zaokruživanje**
Postavite `innodb_buffer_pool_size` na 10,5 GB i proverite stvarnu vrednost. Objasnite razliku preko `chunk_size` i `instances`. Zatim izračunajte koju vrednost treba tražiti da biste dobili tačno 12 GB.

**Vežba 3 — Računica memorije naspram stvarnosti**
Izračunajte teorijski maksimum potrošnje po formuli iz poglavlja 34. Zatim opteretite server sa 50 paralelnih konekcija i izmerite `VmRSS`. Uporedite i objasnite razliku.

**Vežba 4 — Lanac fajl deskriptora**
Postavite `LimitNOFILE=1024` u override fajlu, restartujte i proverite šta se desilo sa `open_files_limit` i `table_open_cache`. Zatim pokušajte da otvorite mnogo tabela i pročitajte grešku. Popravite i uporedite.

**Vežba 5 — Rezervni administrativni port**
Uključite `admin_port`. Zatim namerno iscrpite `max_connections` skriptom koja otvara konekcije i ne pušta ih. Potvrdite da se preko običnog porta ne možete povezati, a preko administrativnog možete. Ovu vežbu uradite pre nego što vam zatreba.

**Vežba 6 — Cena `fsync`-a**
Izmerite broj `INSERT`-a u sekundi sa `(1, 1)`, pa sa `(2, 0)`. Zabeležite razliku. Zatim za svaku kombinaciju odgovorite na pitanje šta biste izgubili pri nestanku struje i kome bi to smetalo.

**Vežba 7 — Swap i buffer pool**
Na test mašini namerno postavite buffer pool na 90% RAM-a i opteretite server. Pratite `vmstat 1` i posmatrajte kolone `si`/`so`. Izmerite kako se odziv menja kada server počne da swapuje. Ovo je vežba koja se pamti.

**Vežba 8 — Dokaz da nije baza**
Napišite jednostavnu aplikaciju koja za jedan zahtev otvara novu konekciju i izvršava 200 sitnih upita. Izmerite: vreme koje aplikacija prijavljuje, vreme koje meri `sys.statement_analysis`, i `Threads_created`. Napišite izveštaj po obrascu iz poglavlja 38.

**Vežba 9 — `pt-stalk` za povremeni problem**
Podesite `pt-stalk` sa pragom na `Threads_running`. Zatim, u nasumičnom trenutku, izazovite skok opterećenja. Sledećeg dana analizirajte prikupljeni snimak i utvrdite šta se dešavalo, bez da ste bili prisutni.

---

## Šta sledi

U **Modulu 8** postavljamo repliku.

Obradićemo master–replica setup od nule u dvadesetak minuta, održavanje replikacije u praksi — zaostajanje, `SHOW REPLICA STATUS`, prekinuta replikacija i kako je vratiti — upotrebu replike kao izvora za backup i kao read-only servera za izveštaje, i kratak, iskren pregled HA opcija: Galera, InnoDB Cluster, ProxySQL, uz odgovor na pitanje koje se retko postavlja — **kada vam HA uopšte ne treba.**

Jedna stvar iz ovog modula ide direktno tamo: ako ste odlučili da vam je `innodb_flush_log_at_trx_commit = 2` prihvatljiv, ta odluka se menja onog trenutka kada dodate repliku.
