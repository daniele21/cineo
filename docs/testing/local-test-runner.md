# Cineo: prova sul tuo Mac con un solo script

**Punto d'ingresso:** `scripts/test-cineo.sh` (dal repository, nella cartella principale).

## Preparazione

Servono macOS con Xcode 26 o superiore, Swift, Python 3 e Git. Per il test interattivo serve una **identità Apple Development** configurata in Xcode; il Team ID rimane soltanto nel tuo ambiente.

```bash
git clone https://github.com/daniele21/cineo.git
cd cineo
bash scripts/test-cineo.sh --preflight
```

Se hai già clonato il repository, aggiorna prima il codice con `git pull --ff-only origin main` sulla copia di lavoro pulita.

## Modalità

| Cosa vuoi verificare | Comando | Cosa dimostra |
| --- | --- | --- |
| Toolchain | `bash scripts/test-cineo.sh --preflight` | Swift, Xcode, architettura, presenza identità di firma; non compila |
| Logica indipendente | `bash scripts/test-cineo.sh --quick` | Test `CineoDirector`, `CineoProject`, `CineoEditPlanner` |
| App nativa / geometria | `bash scripts/test-cineo.sh --native` | Recupera Orbit al commit fissato, applica overlay Cineo, compila **senza firma**, esegue test con eventi sintetici su Camera Director / CameraPath / TimeMap |
| App funzionante da collaudare | `CINEO_APPLE_TEAM=YOUR10CHARID bash scripts/test-cineo.sh --interactive` | Compila e verifica firma locale, apre `Cineo.app` e mostra checklist; i test capture/export si eseguono manualmente |
| MP4 esportati | `bash scripts/test-cineo.sh --exports --landscape "/path/to/16x9.mp4" --portrait "/path/to/9x16.mp4"` | Verifica localmente struttura file, H.264, dimensioni, durata; aggiungi `--require-audio` per richiedere una traccia audio |

`--native` può impiegare tempo la prima volta perché scarica il repository e le dipendenze al commit bloccato; il build viene preparato in una cartella temporanea indipendente da Cineo. **Non modificare il codice dentro lo staging:** il successivo bootstrap esegue un reset per mantenere la riproducibilità.

## Primo collaudo che raccomandiamo

1. Esegui `--preflight`, quindi `--quick`.
2. Lancia `--native` se vuoi verificare build, adattatore click → zoom, fluidezze matematiche e conversioni dei tagli. Non apre l'app.
3. Quando vuoi provarla visivamente, usa `--interactive` con il tuo Team ID. Il comando `open` apre l'app firmata senza simulare i permessi del sistema. **Autorizza Screen Recording solo tramite l'interfaccia di macOS** e prova a registrare una finestra di test.
4. Dal menu **Smart Zooms**, seleziona prima Subtle, poi Balanced, poi Dynamic; confronta inquadrature e conservazione degli zoom manuali.
5. Esporta un file 1920×1080 e uno 1080×1920 H.264, poi passa i loro percorsi a `--exports`.

Questi controlli non inviano video al cloud né leggono dati personali del tuo account. I controlli di movimento usano input sintetici. La modalità `--interactive` **non attesta automaticamente** la riuscita del video reale e un MP4 strutturalmente valido **non prova** sincronizzazione audio, nitidezza, flicker o crop corretto.

Per il collaudo completo vedi [protocollo registrazione/edit/export](native-smoke.md), [sonda MP4](export-probe.md).

### Se qualcosa non funziona

Condividi il nome della modalità, l'ultimo errore (senza credenziali né percorsi privati) e il nome dello step. I log di compilazione locali, se necessari, sono in `${CINEO_NATIVE_ROOT:-${TMPDIR:-/tmp}/cineo-p1-native}/logs/`. Evita di incollare l'intero log se include percorsi del computer o informazioni private.
