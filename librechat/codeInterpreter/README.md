# Code Interpreter für LibreChat

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat)

Installations-Skripte für einen **selbst gehosteten Code Interpreter**, den LibreChat
statt des kostenpflichtigen Dienstes von LibreChat.ai nutzen kann.

---

## Teil der Blogreihe „Die Spielecke"

Diese Skripte gehören zur Reihe auf **[pc-fee.com](https://pc-fee.com/blog/)** und
bauen auf dem Server auf, der dort Schritt für Schritt entsteht. Wer die Reihe
mitgemacht hat, hat bereits alles beisammen, was hier vorausgesetzt wird:

1. [Docker & Docker Compose](https://pc-fee.com/2026/05/03/docker-compose/)
2. [Nginx Proxy Manager](https://pc-fee.com/2026/05/03/nginx-proxy-manager/) samt
   Docker-Netzwerk `shared_proxy`
3. [LibreChat installieren](../install/)

Der Code Interpreter ist der nächste Baustein darauf. Quereinsteiger arbeiten die
drei Punkte am besten vorher ab – sonst brechen die Skripte gleich zu Beginn mit
einem entsprechenden Hinweis ab.

---

## Was macht ein Code Interpreter?

Fragt jemand im Chat „rechne mir das aus" oder „erstelle ein Diagramm aus dieser
CSV-Datei", schreibt das Sprachmodell dafür ein kleines Programm. Ausgeführt wird
dieses Programm nicht von LibreChat selbst, sondern von einem separaten Dienst –
dem Code Interpreter. LibreChat schickt den Code hin und bekommt das Ergebnis zurück.

Diese Trennung hat einen Grund: Hier läuft Programmcode, den vorher niemand gelesen
hat. Beide Varianten unten schirmen ihn deshalb vom übrigen Server ab – sie
unterscheiden sich darin, wie weit sie dabei gehen.

---

## Zwei Varianten zur Auswahl

| | [LibreChat-AI](./LibreChat-AI/) | [usnavy13](./usnavy13/) |
|---|---|---|
| **Projekt** | `LibreChat-AI/code-interpreter` | `usnavy13/LibreCodeInterpreter` |
| **Herkunft** | Fork von ClickHouse, gepflegt vom LibreChat-Team | Community-Projekt |
| **Abschirmung** | MicroVM mit eigenem Gast-Kernel (libkrun) + NsJail, wahlweise NsJail allein | NsJail: Namespaces, Seccomp, Cgroup-Limits, Nicht-root |
| **Zugangsschutz** | Signierte Aufträge per JWT (EdDSA) | API-Key |
| **Dein Aufwand** | ein Befehl, ein paar Fragen | ein Befehl, zwei Fragen |
| **Rechenzeit des Servers** | Images werden lokal gebaut, 10–30+ Min. | fertige Images werden geladen, wenige Minuten |
| **Plattenplatz** | Skript verlangt 15 GB frei (20 GB ohne KVM) | rund 9 GB an Images |
| **Eigene Domain nötig** | nur im Modus „extern" | ja |
| **Voraussetzung Server** | `/dev/kvm` für die stärkste Abschirmung | keine besondere |

In beiden Fällen tippst du **einen** Befehl, beantwortest ein paar Fragen und lässt
den Rest laufen. Der Unterschied bei der Zeit liegt nicht bei dir, sondern beim
Server: Die LibreChat-AI-Variante kompiliert ihre Images selbst, deshalb der lange
Balken. Nutze dafür `tmux` oder `screen`, dann übersteht die Installation auch einen
Abbruch der SSH-Verbindung.

---

## Welche passt zu dir?

**[LibreChat-AI](./LibreChat-AI/)** ist die weiter gehende Variante. Bietet dein
Server `/dev/kvm` an, läuft jede Codeausführung in einer eigenen kleinen virtuellen
Maschine mit eigenem Kernel. Das ist die Konfiguration, die die Projekt-Doku als
angemessen abgesichert bezeichnet, und die richtige Wahl für eine Instanz, die auch
andere Menschen nutzen.

So prüfst du in einem Befehl, ob dein Server das kann:

```bash
[ -r /dev/kvm ] && [ -w /dev/kvm ] && echo "KVM verfügbar" || echo "kein KVM"
```

Bei günstigen VPS – besonders bei OpenVZ- oder LXC-basierten Angeboten – ist KVM oft
nicht durchgereicht. Dann fällt das Skript auf den **NsJail-Modus** zurück, der sich
den Kernel mit dem Host teilt. Die Projekt-Doku ordnet diesen Modus als geeignet für
lokale Tests ein, nicht für produktive Systeme mit unbekannten Nutzern. Zum
Ausprobieren und für den eigenen Gebrauch ist er also durchaus brauchbar – das
Skript weist auf den Unterschied hin und fragt einmal nach, bevor es weitermacht.

**[usnavy13](./usnavy13/)** ist die schlanke Variante: fertige Images, in wenigen
Minuten fertig, genügsam beim Plattenplatz. Auch hier läuft der Code in
NsJail-Sandboxen – mit getrennten Namespaces, Seccomp-Filtern, Cgroup-Limits und
als Nicht-root-Nutzer. In Sachen Abschirmung liegt diese Variante damit auf einer
Stufe mit dem NsJail-Modus der LibreChat-AI-Variante. Was fehlt, ist die MicroVM-
Ebene darüber. Eine gute Wahl, wenn dein Server kein KVM anbietet, klein ist oder du
die Funktion erst einmal kennenlernen willst.

Der eigentliche Unterschied schrumpft damit auf eine Frage: **eigener Gast-Kernel
oder nicht.** Den gibt es nur bei LibreChat-AI und nur mit KVM. Alles andere –
Aufwand, Plattenplatz, Zugangsschutz – sind Abwägungen ohne richtige oder falsche
Antwort.

Beide Varianten führen fremden Code aus. Für beide gilt derselbe nüchterne Rat, der
für jeden Dienst auf einem Server gilt: ein aktuelles Backup schadet nie. Für
LibreChat gibt es dafür das [Admin-Tool](../maintenance/).

---

## Gemeinsame Voraussetzungen

- **Debian 12 oder 13** mit **Docker** und dem **Docker-Compose-Plugin** (auf
  anderen Distributionen nicht getestet)
- ein laufender **Nginx Proxy Manager**
- das externe Docker-Netzwerk **`shared_proxy`**
- `git` und `openssl`
- root-Rechte bzw. `sudo`

Beide Skripte prüfen das vollständig, bevor sie irgendetwas schreiben, und bringen
bei jedem fehlenden Punkt einen konkreten Hinweis mit. Kein Skript bindet jemals
einen Port öffentlich an den Host – aller Zugriff läuft über Docker-Netzwerke bzw.
den Nginx Proxy Manager.

---

## Weiter geht es hier

- **[LibreChat-AI/](./LibreChat-AI/)** – MicroVM bzw. NsJail, Aufträge per JWT signiert
- **[usnavy13/](./usnavy13/)** – schlank, fertige Images, API-Key

---

<sub>Die Skripte in diesem Ordner wurden unter Einsatz von KI-Modellen recherchiert,
erstellt und iterativ überarbeitet. Alle technischen Aussagen wurden gegen die
jeweilige Projekt-Dokumentation und den Quellcode geprüft. Vor produktivem Einsatz
bitte eigenverantwortlich prüfen.</sub>