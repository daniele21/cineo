# Testare Cineo senza Xcode.app

**Requisiti locali:** macOS 15+, Apple Command Line Tools installati (`xcode-select --install`), Swift e macOS SDK compresi nei CLT. **Non serve Xcode.app, né un account Apple Developer** per questa versione di acquisizione.

## Comandi predefiniti

```bash
cd ~/Personal/cineo
git switch main
git pull --ff-only origin main

bash scripts/test-cineo.sh --preflight
bash scripts/test-cineo.sh --quick
bash scripts/test-cineo.sh --native
bash scripts/test-cineo.sh --interactive
```

| Comando | Cosa fa | Evidenza |
| --- | --- | --- |
| `--preflight` | Controlla l'SDK CLT, Swift e la presenza del framework Testing | Diagnostica senza Xcode |
| `--quick` | Esegue le suite `CineoDirector`, `CineoProject` e `CineoEditPlanner` con search path CLT per Swift Testing | Test unitari senza Xcode |
| `--native` | Compila `Apps/Cineo` con SwiftPM, crea `Cineo.app` e la firma ad hoc | Build nativa senza `xcodebuild` |
| `--interactive` | Ricompila la stessa app e la apre | **Test manuale** Screen Recording e MP4 |
| `--exports` | Ispeziona un MP4 H.264 già esportato con AVFoundation | Codec/risoluzione/durata, non qualità percepita |

`--native` e `--interactive` usano ora la **nuova Cineo Capture Alpha costruita senza Xcode**. Gli script basati su Orbit restano temporaneamente disponibili solo con `--legacy-orbit-native` e `--legacy-orbit-interactive` e richiedono Xcode completo: non utilizzarli per verificare l'architettura CLT-only.

## Prima prova interattiva

1. Lancia `bash scripts/test-cineo.sh --interactive`. La compilazione usa `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, `swift build` e `codesign --sign -`; non chiede account, Team ID o credenziali.
2. Nell'app clicca **Record main display**. macOS potrà chiedere di autorizzare Screen Recording; segui l'UI di sistema ed eventualmente riavvia Cineo.
3. Registra una schermata di test per 10–30 secondi, poi clicca **Stop recording**. Attendi la dicitura `MP4 finalized`.
4. Clicca **Show recordings**. I file sono nella cartella `~/Movies/Cineo/`, senza upload o API.
5. Apri il file con QuickTime o un altro lettore e verifica che sia riproducibile.

**Limitazioni reali:** questa prima app cattura il display principale con cursore, 30 fps, H.264 MP4 e **non registra audio**. Non offre ancora l'editor Orbit né Smart Zooms; questi moduli esistono nel codice ma la loro UI/render integration appartiene ancora alla build legacy. L'uso di una firma ad hoc può causare nuove richieste TCC quando cambia il binario: non eliminare o aggirare le protezioni del sistema.

### Verificare il file registrato

Lo strumento preesistente di ispezione consente di controllare un output con dimensioni specifiche, per esempio:

```bash
bash scripts/test-cineo.sh --exports \
  --landscape "$HOME/Movies/Cineo/IL-TUO-VIDEO.mp4"
```

La modalità `--exports` richiede esplicitamente 1920×1080 per il video landscape; **non usarla su risoluzioni diverse** finché non hai configurato un export a quel formato. Per il primo test della Capture Alpha è sufficiente aprire l'MP4 reale in QuickTime.

## Swift Testing con CLT

Su alcune installazioni di Command Line Tools SwiftPM non trova `Testing.framework` e il comando `swift test` fallisce con `no such module 'Testing'`. `scripts/swift-test-clt.sh` rileva il framework installato nei CLT e configura percorsi `-F` e `-rpath` per compilazione ed esecuzione senza Xcode. Questa soluzione richiede comunque un CLT installato correttamente.

## Stato di verifica

La CI macOS può verificare **compilazione**, firme ad hoc e test Swift isolati con `DEVELOPER_DIR=/Library/Developer/CommandLineTools`. Non verifica permessi TCC, acquisizione reale, validità effettiva di un file prodotto dall'app o qualità video. Sono i test manuali da eseguire sul Mac fisico.

Vedi [decisione CLT-only](../decisions/0002-xcode-free-build.md) e [test prodotto completo](native-smoke.md).
