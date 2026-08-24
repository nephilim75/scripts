# Code Interpreter – Variante usnavy13

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-LibreCodeInterpreter-181717?style=for-the-badge&logo=github)](https://github.com/usnavy13/LibreCodeInterpreter)

[![Isolation](https://img.shields.io/badge/Sandbox-NsJail-2E7D32?style=flat-square)](#sicherheit)
[![Auth](https://img.shields.io/badge/Auth-API--Key-2E7D32?style=flat-square)](#der-master_api_key)
[![Ports](https://img.shields.io/badge/Host--Ports-keine-2E7D32?style=flat-square)](#sicherheit)
[![Getestet](https://img.shields.io/badge/Getestet-Debian%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)](#voraussetzungen)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)

Installiert `usnavy13/LibreCodeInterpreter` hinter einem Nginx Proxy Manager – die
schlanke Variante: fertige Images, wenige Minuten Installationszeit, kein
Kompilieren.

> **Zur Einordnung:** Der Code läuft hier in NsJail-Sandboxen – getrennte
> Namespaces, Seccomp-Filter, Cgroup-Limits, Ausführung als Nicht-root-Nutzer. Das
> entspricht dem NsJail-Modus der [MicroVM-Variante](../LibreChat-AI/); was dort
> zusätzlich möglich ist, ist ein eigener Gast-Kernel pro Ausführung. Siehe
> [Entscheidungshilfe](../).

---

## Installation

Ein Befehl, root-Shell oder mit `sudo`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh)"
```

Das Skript prüft zuerst alle Voraussetzungen und bricht mit einer verständlichen
Meldung ab, wenn etwas fehlt. Es überschreibt nichts Vorhandenes.

---

## Voraussetzungen

- **Debian 12 oder 13** mit Docker und Docker-Compose-Plugin (auf anderen
  Distributionen nicht getestet)
- laufender **Nginx Proxy Manager** und das Docker-Netzwerk **`shared_proxy`**
- `git` und `openssl`
- eine **Domain**, die auf diesen Server zeigt
- `/opt/LibreCodeInterpreter` darf noch nicht existieren

---

## Was das Skript fragt

| Frage | Bedeutung |
|---|---|
| **Docker-Netzwerk des NPM** | Standard `shared_proxy`, wird auf Existenz geprüft |
| **Domain** | z. B. `code.example.de` |

Mehr nicht. Alles Weitere passiert automatisch.

---

## Was das Skript einrichtet

- klont das Repository nach `/opt/LibreCodeInterpreter`
- erzeugt einen zufälligen **`MASTER_API_KEY`** (32 Byte, hex) – damit meldest du
  dich am Admin-Dashboard an
- schreibt die `.env` mit `chmod 600` und setzt `PORT=127.0.0.1:8000` – der Port ist
  damit **nicht** öffentlich am Host gebunden
- legt ein `docker-compose.override.yml` an, das den API-Container zusätzlich ins
  Netzwerk des Nginx Proxy Managers hängt
- lädt die Images und startet den Stack (`redis`, `garage`, `api`)
- prüft am Ende, dass kein Container öffentlich erreichbar ist

---

## Nach der Installation

### 1. DNS

Einen A-Record für deine Domain auf diesen Server setzen. Das Skript zeigt die
ermittelte öffentliche IP an.

### 2. Proxy Host im Nginx Proxy Manager

**Reiter Details**

| Feld | Wert |
|---|---|
| Domain | deine Interpreter-Domain |
| Scheme | `http` |
| Forward Hostname | `code-interpreter-api` |
| Forward Port | `8000` |
| Websockets Support | an |

**Reiter SSL** – Let's Encrypt anfordern, Force SSL, HTTP/2 und HSTS aktivieren.

> Den exakten Container-Namen gibt das Skript am Ende aus, falls er abweicht.

### 3. Prüfen

| Zweck | URL |
|---|---|
| Health-Check | `https://DEINE-DOMAIN/health` |
| Admin-Dashboard | `https://DEINE-DOMAIN/admin-dashboard` |

### 4. Eigenen API-Key im Dashboard erzeugen

**Das ist der Schritt, den man leicht überspringt.** Der `MASTER_API_KEY` aus der
Installation ist **nicht** der Schlüssel, mit dem LibreChat sich anmeldet. Er dient
allein dazu, dich am Admin-Dashboard anzumelden. Trägst du ihn in LibreChat ein,
funktioniert die Anbindung nicht.

Der Schlüssel für LibreChat wird im Dashboard erzeugt:

1. `https://DEINE-DOMAIN/admin-dashboard` öffnen
2. mit dem `MASTER_API_KEY` anmelden
3. dort einen neuen API-Key anlegen
4. den angezeigten Key kopieren – er ist in der Regel nur **einmal** vollständig
   sichtbar

Der Vorteil dieser Trennung: Du kannst diesen einen Key später zurückziehen oder
ersetzen, ohne den Zugang zum Dashboard anzufassen.

### 5. Anbindung an LibreChat

In `/opt/librechat/.env` **eine einzige Zeile**:

```
LIBRECHAT_CODE_BASEURL=https://<der Key aus dem Dashboard>@DEINE-DOMAIN
```

Beispiel mit `code.example.de` und einem Key `abc123`:

```
LIBRECHAT_CODE_BASEURL=https://abc123@code.example.de
```

Danach LibreChat **stoppen und starten**:

```bash
docker stop LibreChat && docker start LibreChat
```

Ein reines `docker restart` liest die `.env` **nicht** neu ein. Ob die Werte
angekommen sind, zeigt:

```bash
docker exec LibreChat env | grep LIBRECHAT_CODE
```

#### Warum der Key in der URL steht

Naheliegend wäre die dokumentierte Variante mit zwei getrennten Zeilen und
`LIBRECHAT_CODE_API_KEY`. Die funktioniert hier **nicht**: In LibreChat v0.8.8-rc1
wird diese Variable nirgends ausgelesen. Ohne aktive JWT-Authentifizierung sendet
LibreChat schlicht keine Auth-Header, der Interpreter antwortet mit 401, und im
Chat erscheint „Code execution is not authorized". Der Key in der URL ist deshalb
kein Notbehelf, sondern der einzige Weg, der derzeit trägt.

Zwei Dinge, die man dabei leicht übersieht:

- **Kein `/v1` am Ende.** Die Adresse endet mit der Domain, sonst nichts. Wer aus
  Gewohnheit `/v1` anhängt, bekommt Fehler 404.
- **Der Key landet in den Access-Logs des Nginx Proxy Managers**, weil er Teil der
  URL ist. Wer diese Logs archiviert oder weitergibt, sollte das wissen. Ist der Key
  einmal draußen, ziehst du ihn im Dashboard zurück und legst einen neuen an.

> Für diesen Schritt ist im [Admin-Tool](../../maintenance/) eine Option vorgesehen,
> die den Key abfragt und die Zeile selbst in die `.env` schreibt. Bis dahin trägst
> du sie von Hand ein.

---

## Die zwei Schlüssel – nicht verwechseln

| | wofür | woher |
|---|---|---|
| **`MASTER_API_KEY`** | Anmeldung am Admin-Dashboard | erzeugt das Skript, steht in der `.env` |
| **API-Key** | Anmeldung von LibreChat am Interpreter | erzeugst du selbst im Dashboard |

Der Master-Key ist der Generalschlüssel: Wer ihn hat, kommt ins Dashboard und kann
dort beliebig viele API-Keys anlegen. Er gehört deshalb **nirgendwo** in LibreChats
Konfiguration – dort steht ausschließlich der im Dashboard erzeugte Key.

Das Skript zeigt den Master-Key am Ende einmal an. Er steht außerdem dauerhaft in
`/opt/LibreCodeInterpreter/.env` und lässt sich jederzeit auslesen:

```bash
grep MASTER_API_KEY /opt/LibreCodeInterpreter/.env
```

Behandle beide Schlüssel wie Passwörter.

---

## Wichtige Befehle

```bash
cd /opt/LibreCodeInterpreter

docker compose ps            # Status
docker compose logs -f api   # Logs, Abbruch mit Strg+C

# Update
docker compose pull && docker compose up -d
```

---

## Deinstallation

Reihenfolge beachten – die Anbindung wird zuerst gelöst, danach wird gelöscht.

**1. LibreChat vom Interpreter trennen.** In `/opt/librechat/.env` die Zeile
`LIBRECHAT_CODE_BASEURL=` entfernen oder auskommentieren. Diese Datei gehört zu
LibreChat und bleibt bestehen – gelöscht wird gleich nur das Verzeichnis des
Interpreters unter `/opt/LibreCodeInterpreter`.

```bash
docker stop LibreChat && docker start LibreChat
```

**2. Den Interpreter entfernen.** Damit verschwinden Container, Volumes, Images und
die `.env` mit dem Master-Key. Im Dashboard erzeugte API-Keys sind danach ebenfalls
weg, ein Zurückziehen einzelner Keys erübrigt sich also.

```bash
cd /opt/LibreCodeInterpreter
docker compose down -v --rmi all
cd /opt && rm -rf LibreCodeInterpreter
```

Der Zusatz `--rmi all` löscht auch die heruntergeladenen Images – sonst belegen die
weiter Platz, obwohl nichts mehr läuft. Nutzt ein anderer Stack auf dem Server
zufällig dasselbe Image (etwa Redis), lehnt Docker das Löschen von sich aus ab und
sagt das auch. Es kann also nichts kaputtgehen.

**3. Proxy Host aufräumen.** Im Nginx Proxy Manager den Proxy Host der
Interpreter-Domain löschen – und beim Domain-Provider den A-Record, falls die Domain
nicht anderweitig gebraucht wird.

---

## Sicherheit

### Wie der Code abgeschirmt wird

Laut Projekt-Dokumentation läuft jede Ausführung in einer **NsJail-Sandbox**:

- getrennte Namespaces für Prozesse, Dateisystem und Netzwerk
- Seccomp-Filter, die die erlaubten Systemaufrufe einschränken
- Cgroup-Limits gegen das Ausreizen von CPU, Speicher und Prozessanzahl
- rlimits für Dateigrößen und offene Dateien
- Ausführung als Nicht-root-Nutzer (Standard-UID `1001`)
- Laufzeitumgebungen und Bibliotheken sind nur lesend eingehängt

### Wer drankommt

Die Domain ist öffentlich erreichbar – wer sie kennt, kann sie aufrufen. Nutzen kann
er den Dienst deshalb aber nicht: **alle Endpunkte verlangen einen API-Key**, das
Dashboard zusätzlich den Master-Key. Ohne Schlüssel gibt es nur eine Abweisung. Der
Schutz liegt also beim Key, nicht bei der Geheimhaltung der Adresse.

Daraus folgt der wichtigste praktische Punkt: **Behandle beide Schlüssel wie
Passwörter.** Gerät der Dashboard-Key in falsche Hände, ziehst du ihn im Dashboard
zurück und legst einen neuen an. Die `.env` steht auf `chmod 600` und enthält den
Master-Key – sie gehört in kein Git-Repo.

### Was das Skript zusätzlich tut

- Der Dienst lauscht nur auf `127.0.0.1:8000`, kein Container bindet einen Port
  öffentlich am Host – das prüft das Skript am Ende der Installation
- Der Zugriff von außen läuft ausschließlich über den Nginx Proxy Manager

### Access List – optional, kein Muss

In NPM lässt sich eine **Access List** anlegen, die nur bestimmte IP-Adressen
durchlässt. Das ist eine zusätzliche Hürde, kein Ersatz für den API-Key, und
sinnvoll vor allem dann, wenn **LibreChat auf einem anderen Server** läuft: dann ist
der Absender eine feste, bekannte IP, die du eintragen kannst.

Läuft LibreChat auf **demselben** Server, lass es besser bleiben. Die Anfragen von
LibreChat kommen dann aus dem Docker-Netz und tragen eine interne Adresse wie
`172.18.0.5`, nicht die öffentliche IP deines Servers. Eine Liste mit deiner eigenen
IP würde LibreChat aussperren – Dashboard erreichbar, Codeausführung tot. Ein
Fehlerbild, dessen Ursache man lange sucht.

> Weitere Details zur Absicherung stehen in der
> [Projekt-Dokumentation](https://github.com/usnavy13/LibreCodeInterpreter/blob/main/docs/SECURITY.md).

---

<sub>Dieses Skript wurde unter Einsatz von KI-Modellen recherchiert, erstellt und
iterativ überarbeitet. Alle technischen Aussagen wurden gegen die Projekt-
Dokumentation und den Quellcode geprüft. Vor produktivem Einsatz bitte
eigenverantwortlich prüfen.</sub>

<sub>[← Zurück zur Übersicht](../)</sub>