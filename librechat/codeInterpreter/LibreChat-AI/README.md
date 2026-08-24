# Code Interpreter – Variante LibreChat-AI

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-code--interpreter-181717?style=for-the-badge&logo=github)](https://github.com/LibreChat-AI/code-interpreter)

[![Isolation](https://img.shields.io/badge/Isolation-MicroVM%20%2B%20NsJail-2E7D32?style=flat-square)](https://github.com/LibreChat-AI/code-interpreter#security-disclaimer)
[![Auth](https://img.shields.io/badge/Auth-JWT%20EdDSA-2E7D32?style=flat-square)](#absicherung-per-jwt)
[![Ports](https://img.shields.io/badge/Host--Ports-keine-2E7D32?style=flat-square)](#sicherheit)
[![Getestet](https://img.shields.io/badge/Getestet-Debian%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)](#voraussetzungen)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)

Installiert `LibreChat-AI/code-interpreter` – einen Fork von
`ClickHouse/code-interpreter`, gepflegt vom LibreChat-Team – in voll gehärteter
Konfiguration hinter einem Nginx Proxy Manager.

> **Nicht verwechseln:** Der Ordnername „LibreChat-AI" bezeichnet die
> GitHub-Organisation, unter der dieses Interpreter-Projekt liegt. Es ist **nicht**
> LibreChat selbst, sondern eine Erweiterung dafür.

---

## Installation

Ein Befehl, root-Shell oder mit `sudo`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh)"
```

Das Skript führt durch alles Weitere und bricht mit einer verständlichen Meldung ab,
wenn etwas fehlt. Es überschreibt nichts Vorhandenes.

> **Nimm `tmux` oder `screen`.** Der Build dauert 10–30+ Minuten. Bricht die
> SSH-Verbindung ab, ist die Installation sonst mittendrin tot.

---

## Voraussetzungen

- **Debian 12 oder 13** mit Docker und Docker-Compose-Plugin (auf anderen
  Distributionen nicht getestet)
- laufender **Nginx Proxy Manager** und das Docker-Netzwerk **`shared_proxy`**
- `git` und `openssl`
- **mindestens 15 GB** freier Plattenplatz (ohne KVM: **20 GB**)
- `/dev/kvm` für die volle Härtung – siehe unten
- im Modus „lokal": eine bestehende LibreChat-Installation auf demselben Server

Alles davon wird vom Skript geprüft, bevor irgendetwas geschrieben wird.

---

## Was das Skript fragt

| Frage | Bedeutung |
|---|---|
| **Installationspfad** | Standard `/opt/avila-code-interpreter` |
| **Modus: lokal oder extern** | siehe nächster Abschnitt |
| **Pfad zu LibreChat** | nur im Modus „lokal", Standard `/opt/librechat` |
| **Domain** | nur im Modus „extern" |
| **Aufträge per JWT absichern?** | dringend empfohlen, Standard: ja |
| **Swap-Datei anlegen?** | nur falls kein Swap vorhanden |
| **Ohne KVM trotzdem weiter?** | nur falls `/dev/kvm` fehlt |

### Modus „lokal" oder „extern"

**Lokal** – LibreChat läuft auf **demselben** Server. Beide Container sprechen sich
direkt über den Container-Namen im Netzwerk `shared_proxy` an. Es wird **keine
Domain** und **kein Proxy Host** gebraucht. Das ist der einfachere und sicherere Weg.

**Extern** – LibreChat läuft auf einem **anderen** Server. Dann bekommt der
Interpreter eine eigene Domain über den Nginx Proxy Manager.

### Absicherung per JWT

Ohne JWT nimmt der Interpreter **jeden** Auftrag an, der ihn erreicht. Mit JWT
unterschreibt LibreChat jeden Auftrag mit einem privaten Schlüssel, der Interpreter
prüft die Unterschrift mit dem passenden öffentlichen Schlüssel. Das Schlüsselpaar
(Ed25519 / EdDSA) erzeugt das Skript automatisch.

Der **private Schlüssel gehört ausschließlich auf die LibreChat-Seite**. Im Modus
„lokal" trägt das Skript ihn auf Wunsch direkt in LibreChats `.env` ein und löscht
danach seine eigene Kopie. Im Modus „extern" legt es einen fertigen Textblock unter
`librechat-jwt-block.txt` ab, den du auf den LibreChat-Server überträgst – und dort
anschließend löschst.

### MicroVM oder NsJail

Findet das Skript ein nutzbares `/dev/kvm`, läuft die Sandbox im **MicroVM-Modus**:
jede Ausführung bekommt einen eigenen Gast-Kernel. Das ist die Konfiguration, die
die Projekt-Doku als angemessen abgesichert bezeichnet.

Fehlt KVM, bleibt nur der **NsJail-Modus**, der sich den Kernel mit dem Host teilt.
Laut Projekt-Doku ist das für lokale Tests geeignet, **nicht** für produktive
Systeme mit unbekannten Nutzern. Das Skript zeigt diesen Hinweis und fragt
ausdrücklich nach, bevor es fortfährt.

---

## Was das Skript einrichtet

- klont das Repository nach `/opt/avila-code-interpreter`
- erzeugt alle Secrets und ein Ed25519-Schlüsselpaar für signierte Ausführungs-Manifeste
- schreibt eine `.env` mit `chmod 600`
- legt ein `docker-compose.override.yml` an: feste Container-Namen (`avila-*`),
  Anbindung an `shared_proxy`, **alle Host-Ports entfernt**
- baut die Images lokal und startet den Stack
- im NsJail-Modus zusätzlich: erzeugt die Laufzeitumgebungen (Python, Node, Bun,
  Bash) unter `data/pkgs` und spielt drei Korrekturen für bekannte Upstream-Fehler
  per schreibgeschütztem Volume-Mount ein – das geklonte Repo bleibt unverändert
- prüft am Ende, dass wirklich kein Container einen öffentlichen Port hat

---

## Nach der Installation

### Modus „lokal"

In LibreChats `.env` steht dann (bzw. wird vom Skript eingetragen):

```
LIBRECHAT_CODE_BASEURL=http://avila-api:3112/v1
```

Danach LibreChat **stoppen und starten**:

```bash
docker stop LibreChat && docker start LibreChat
```

### Modus „extern"

1. A-Record der Domain auf diesen Server setzen (das Skript zeigt die IP an)
2. Proxy Host im Nginx Proxy Manager anlegen:

   | Feld | Wert |
   |---|---|
   | Domain | deine Interpreter-Domain |
   | Scheme | `http` |
   | Forward Hostname | `avila-api` |
   | Forward Port | `3112` |
   | Websockets Support | an |
   | SSL | Let's Encrypt, Force SSL, HTTP/2, HSTS |

3. Den Block aus `librechat-jwt-block.txt` auf den LibreChat-Server übertragen und
   dort in die `.env` eintragen. Danach LibreChat stoppen und starten.
4. Empfohlen: in NPM eine **Access List** anlegen, die nur die IP des
   LibreChat-Servers erlaubt.

---

## Bekannte Fallstricke

**`docker restart` reicht nicht.** Ein reiner Neustart liest die `.env` **nicht**
neu ein. Es braucht `docker stop` und `docker start` – oder im Admin-Tool
„Anwendungssteuerung → LibreChat → erst Stoppen, dann Starten".

**In der `.env` gewinnt die letzte Zuweisung.** Stehen weiter unten noch alte Zeilen
mit `LIBRECHAT_CODE_BASEURL=` oder `CODEAPI_` von einem früheren Interpreter,
überschreiben sie die neuen Werte. Typisches Fehlerbild: `unknown_kid`, weil noch
die alte Schlüssel-Kennung gilt. Alte Zeilen entfernen oder auskommentieren.

**Fehler `<runtime> is unknown`** bei jeder Codeausführung im NsJail-Modus bedeutet
fehlende Laufzeitumgebungen unter `data/pkgs`, nicht ein Problem der Anfrage. Das
Skript erzeugt sie und prüft das Ergebnis – die Meldung sollte also nicht auftreten.

**Der Build wird ohne Meldung abgeschossen.** Das ist ein OOM-Kill durch zu wenig
RAM. Deshalb bietet das Skript vorher eine 4-GB-Swap-Datei an.

---

## Wichtige Befehle

```bash
cd /opt/avila-code-interpreter

docker compose ps          # Status
docker compose logs -f     # Logs, Abbruch mit Strg+C
docker compose logs -f api # Logs nur der API

# Update
git pull && docker compose build && docker compose up -d
```

---

## Deinstallation

Reihenfolge beachten – die Anbindung wird zuerst gelöst, danach wird gelöscht.

**1. LibreChat vom Interpreter trennen.** In `/opt/librechat/.env` die Zeilen
`LIBRECHAT_CODE_BASEURL=` und alle Zeilen, die mit `CODEAPI_` beginnen, entfernen
oder auskommentieren. Diese Datei gehört zu LibreChat und bleibt selbstverständlich
bestehen – gelöscht wird gleich nur das Verzeichnis des Interpreters.

```bash
docker stop LibreChat && docker start LibreChat
```

**2. Den Interpreter entfernen.**

```bash
cd /opt/avila-code-interpreter
docker compose down -v --rmi all
docker rmi avila-package-init
cd /opt && rm -rf avila-code-interpreter
```

Der Zusatz `--rmi all` löscht auch die Images. Hier lohnt sich das besonders: Sie
wurden lokal gebaut und belegen mehrere GB. Nutzt ein anderer Stack auf dem Server
zufällig dasselbe Image, lehnt Docker das Löschen von sich aus ab und sagt das auch –
es kann nichts kaputtgehen.

Das Image `avila-package-init` entsteht nur im NsJail-Modus und gehört nicht zum
Compose-Projekt, deshalb der eigene Befehl. Gab es keinen NsJail-Modus, meldet Docker
schlicht, dass es das Image nicht kennt – auch das ist in Ordnung.

Ob noch etwas übrig ist, zeigt:

```bash
docker images | grep -i -E 'avila|code-interpreter'
```

**3. Nur im Modus „extern": Proxy Host aufräumen.** Im Nginx Proxy Manager den
Proxy Host der Interpreter-Domain löschen – und beim Domain-Provider den A-Record,
falls die Domain nicht anderweitig gebraucht wird. Im Modus „lokal" entfällt das,
dort gab es beides nie.

**4. Optional: Swap-Datei.** Hat das Skript eine angelegt, bleibt sie bestehen und
schadet nicht. Wird sie nicht mehr gebraucht:

```bash
swapoff /swapfile-avila-code-interpreter
sed -i '\|^/swapfile-avila-code-interpreter |d' /etc/fstab
rm /swapfile-avila-code-interpreter
```

---

## Sicherheit

- Kein Container bindet einen Port öffentlich am Host – geprüft am Ende der Installation
- Redis und MinIO hängen nicht im `shared_proxy`-Netz und sind ausschließlich
  containerintern erreichbar
- Ausführungs-Manifeste sind signiert (Ed25519)
- Egress-Gateway und Hardened Mode sind aktiviert
- Die `.env` steht auf `chmod 600` und enthält Secrets – nicht in ein Git-Repo legen

---

<sub>Dieses Skript wurde unter Einsatz von KI-Modellen recherchiert, erstellt und
iterativ überarbeitet. Alle technischen Aussagen wurden gegen die offizielle
Projekt-Dokumentation und den Quellcode geprüft. Vor produktivem Einsatz bitte
eigenverantwortlich prüfen.</sub>

<sub>[← Zurück zur Übersicht](../)</sub>