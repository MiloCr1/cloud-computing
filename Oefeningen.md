# Oefeningen — Cloud computing (MGN13A)

# Labo 1 — Je eerste containers
### 1. Waarom stopte de `hello-world`-container vanzelf, terwijl `nginx` blijft draaien?

Een container leeft zolang zijn hoofdproces (PID 1) draait. `hello-world` print een tekst en eindigt de container. nginx start een master-proces dat in de foreground blijft luisteren en nooit vanzelf eindigt.

### 2. Je draaide `docker run hello-world` twee keer. Wat was er de tweede keer anders?

De regels `Unable to find image ... locally` en `Pulling from library/hello-world` waren weg. Het image stond na de eerste keer in de lokale image cache en hoefde niet opnieuw bij Docker Hub opgehaald te worden.

### 3. Bij `ps aux` in de container zag je maar een paar processen. Verklaar dat.

PID-namespace-isolatie. De container heeft zijn eigen procestabel en ziet alleen zijn eigen processen.

### 4. `/etc/os-release` toont een andere distributie dan de laptop. Hoe kan dat?

Een container deelt de kernel van de host maar brengt zijn eigen bibliotheken, shell, pakketbeheer en configuratiebestanden mee. Een distributie is vrijwel volledig userland, dus dat kan verschillen zolang de kernel compatibel is.

### 5. Twee nginx-containers tegelijk, elk op een andere poort

```powershell
docker run -d --name web1 -p 127.0.0.1:8080:80 nginx
docker run -d --name web2 -p 127.0.0.1:8081:80 nginx
```

Twee keer dezelfde hostpoort kan niet: een TCP-poort op een interface kan door maar één socket tegelijk gebonden worden. De tweede poging faalt met `bind: address already in use`. De containerpoort mag wel twee keer 80 zijn.

### 6. Verschil tussen `docker stop` en `docker kill`

`stop` wacht standaard 10 seconden zodat het proces netjes kan afsluiten. `kill` stuurt meteen SIGKILL, wat niet op te vangen is.

### 7. Hoeveel plaats nemen de images samen in?

```powershell
docker system df
docker system df -v
```
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          14        4         2.812GB   2.049GB (72%)
Containers      4         3         114.7kB   77.82kB (67%)
Local Volumes   7         2         180.3MB   114.7MB (63%)
Build Cache     58        0         2.072GB   51.53MB

## Verdieping labo 1

### V1. `traefik/whoami`

```powershell
docker run -d --name whoami -p 127.0.0.1:8080:80 traefik/whoami
```

Toont de request in platte tekst terug:

- **Hostname** — de container-ID.
- **IP** — het adres van de container in het bridge-netwerk.
- **RemoteAddr** — de gateway van de bridge, niet het IP van de laptop

### V2. Waarom start `postgres` niet zomaar zoals nginx?

Nginx werkt out of the box, postgres heeft een paswoord nodig. Nginx is stateless, postgres schrijft naar een directory, zonder volume is dit weg na een "rm". Nginx gebruikt HTTP, postgres een eigen wire protocol op 5432 die een client vereist.

### V3. Zelf een naam geven

De optie is `--name`.

---

# Labo 2 — Je eigen image

Tijd van eerste build is 9,5158186s.
Daarna 2,0619943s
Na aanpssing app.py 3,2577839s
Na tweede aapassing app.py 3,1193835s

Grootte image = 220MB

Na restart is melding er nog
Na herinstallatie niet
Logisch omdat de data nergens buiten de cotainer wordt opgeslagen.

### 1. Waarom staat `COPY requirements.txt` apart, vóór de `COPY` van de rest?

Elke instructie maakt een laag, en Docker hergebruikt een laag alleen als die laag
en alles erboven ongewijzigd is. `requirements.txt` verandert bijna nooit. Door dat bestand apart te kopiëren hangt de pip-laag alleen af van de dependencies, en blijft die gecached bij een codewijziging.

### 2. Wat doet de punt op het einde van `docker build -t storingsmelder .` ?

Dat is de build context: de map die naar de Docker-daemon gestuurd wordt. Alleen bestanden binnen die context kunnen met `COPY` of `ADD` in het image. De punt betekent "de map waarin ik nu sta".

### 3. Verschil tussen `RUN` en `CMD`

`RUN` draait tijdens de build en legt het resultaat vast in een laag.
`CMD` draait niet tijdens de build; het is het default-commando bij `docker run`.

### 4. Haal `EXPOSE` weg en bouw opnieuw. Werkt de applicatie nog?

Ja. `EXPOSE` opent geen poort en publiceert niets, het is metadata die documenteert op welke poort de applicatie luistert.

### 5. Wat doet `pip install --no-cache-dir`, en waarom wil je dat in een image?

pip bewaart gedownloade wheels standaard in `~/.cache/pip`. In een image is dat dode ballast: nooit meer gebruikt, maar permanent aanwezig in de laag waar pip in draaide.

### 6. De container overleefde een herstart, maar niet het verwijderen. Waar stond de melding?

In de writable layer van die ene container. Een image is read-only; bij `docker run` legt Docker daar een schrijfbare laag bovenop (copy-on-write).

De applicatie schrijft naar `/data/storingen.db`. Dat pad zit niet in het image, de Dockerfile maakt alleen de lege map en niet op de laptop, maar in die containerlaag. `restart` hergebruikt hetzelfde containerobject inclusief die laag, `rm` gooit hem weg en `run` maakt een verse aan.

### 7. Welk base image en waarom?

`python:3.14-slim`. Alpine gaf geen werkende build omdat `psycopg[binary]` geen musl-wheel heeft en pip dan libpq ter plekke wil compileren. De volle `python:3.14` is honderden MB groter zonder dat er iets van die extra inhoud gebruikt wordt. Slim is de kleinste variant die out of the box werkt, en het kleinere attack surface, minder shells en tooling, minder CVE's in een scan.

## Verdieping labo 2

### V4. Multi-stage build

Resultaat: geen winst. De tweede stage vertrekt opnieuw van `python:3.14-slim`, inclusief de pip die daarin zit — die 12 MB verdwijnt dus niet.

Multi-stage loont wanneer er build-only gereedschap is dat in stage 1 achterblijft: een compiler voor C-extensies, `build-essential`, een Go- of Rust-toolchain, node_modules voor een frontend-build. Deze applicatie heeft dat niet; Flask en psycopg komen als kant-en-klare wheels binnen, er is geen gcc in het spel.

---

# Labo 3 — Applicatie en database samen

melding nog aanwezig na down / up

na gewoon down staan ze er nog, na down -v niet meer

### 1. Waarom werkt `localhost` niet als host in de `DATABASE_URL`, en wat werkt wel?

`localhost` is binnen een container de container zelf, niet de laptop en niet een andere container. Elke container heeft een eigen network namespace met een eigen loopback-interface. Op poort 5432 van `web` luistert niets → `Connection refused`.

Wat wel werkt is de servicenaam `db`.

### 2. Je hebt nergens een netwerk aangemaakt, en toch vinden de containers elkaar

Compose maakt automatisch een user-defined bridge network voor het project (`cloud-computing_default`) en zet daar een embedded DNS-resolver op. Elke servicenaam is in dat netwerk een hostnaam.

### 3. Verschil tussen `docker compose down` en `docker compose down -v`

`down` verwijdert de containers en het netwerk van het project.
`down -v` verwijdert daarbovenop de named volumes.

### 4. Waarom publiceer je poort 5432 niet?

De applicatie bereikt de database via het interne netwerk en heeft geen gepubliceerde poort nodig.
Alles wat niet naar buiten hoeft, hoort ook niet naar buiten.

### 5. `depends_on` zorgde er niet voor dat de applicatie wachtte. Wat doet het dan wel?

In de korte vorm regelt `depends_on` alleen de startvolgorde: Compose start `db` voor `web`, en stopt ze in omgekeerde volgorde. Het zegt niets over of de dienst in die container klaar is om verbindingen aan te nemen.
Dat laatste vraagt de lange vorm met `condition: service_healthy`, plus een healthcheck op de database.

### 6. Aan welke map hangt het volume van de database, en waar gevonden?

`/var/lib/postgresql/18/docker`, niet het `/var/lib/postgresql/data` uit oudere voorbeelden. Sinds PostgreSQL 18 is dat pad gewijzigd.
Gevonden op hub.docker.com/_/postgres.

### 7. Een collega cloont de repo en doet `docker compose up`. Wat moet hij nog doen?

Een `.env` aanmaken met echte waardes. Die staat in `.gitignore` en komt dus niet mee. Zonder dat bestand zijn `${POSTGRES_USER}`, `${POSTGRES_PASSWORD}` en `${POSTGRES_DB}` leeg, en weigert PostgreSQL te initialiseren.

## Verdieping labo 3

### V1. Healthcheck en `condition: service_healthy`

Werkt nog na het verwijderen van de restart.

### V2. In de database kijken

```powershell
docker compose exec db psql -U storing -d storingen -c "SELECT * FROM meldingen;"
```

### V3. Tweede applicatiecontainer

```yaml
  web2:
    build: .
    ports:
      - "127.0.0.1:8001:8000"
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
    depends_on:
      db:
        condition: service_healthy
```
Meldingen die in de eerst binnenkomen worden ook gezien op de andere.

### V4. `docker compose down --rmi local`

`down --rmi local` verwijdert containers, netwerk, volumes, de images die Compose zelf gebouwd heeft

Je gebruikt het als je wilt dat de volgende build echt van 0 begint.