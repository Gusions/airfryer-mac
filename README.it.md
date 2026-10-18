# Airfryer Mac

Una piccola app nativa per macOS (barra dei menu + finestra) per controllare dal Mac una **Philips Airfryer serie 5000 Connected**: imposta temperatura e durata, avvia, metti in pausa, ferma, accendi e spegni, e ricevi una notifica a fine cottura.

> **Progetto non ufficiale.** Non affiliato, approvato o sponsorizzato da Philips o Versuni. *Philips*, *Airfryer*, *HomeID* e *NutriU* sono marchi dei rispettivi proprietari. Questo repository non include loghi né immagini di prodotto Philips.

> **Sicurezza.** Una friggitrice ad aria è un elettrodomestico che scalda. Non lasciarla mai in funzione senza sorveglianza e non usare questa app come dispositivo di sicurezza. Il software è fornito "così com'è" (vedi [LICENSE](LICENSE)).

[English](README.md)

## Come funziona

L'app non parla direttamente con la friggitrice. Usa [Home Assistant](https://www.home-assistant.io/) e l'integrazione della comunità [Philips HomeID](https://github.com/renaudallard/homeassistant_philips_homeid):

```
Airfryer Mac  ──REST──▶  Home Assistant  ──▶  integrazione Philips HomeID  ──▶  friggitrice
 (questa app)             (locale, Docker)     (rete locale o cloud Philips)
```

I firmware recenti (per esempio **4.0.0 / 0.6.8** sull'HD9255) sono solo cloud: i comandi passano dal cloud Philips e servono internet e il tuo account HomeID. Con firmware più vecchi potrebbe essere possibile il controllo locale; se ne occupa l'integrazione, non questa app.

## Funzioni

- Temperatura e durata con pulsanti +/− entro i limiti dichiarati dall'apparecchio, più programmi rapidi (patatine, pollo, verdure, riscalda).
- Avvio (con conferma), pausa, arresto e tasto di accensione.
- Stato, tempo rimanente (anche nella barra dei menu durante la cottura) e notifica di fine cottura.
- Associazione automatica delle entità della friggitrice, modificabile a mano.
- Icona nella barra dei menu e finestra normale con icona nel Dock (utile se il notch nasconde le icone).
- Immagine di intestazione facoltativa (per esempio la foto della tua friggitrice), salvata solo sul tuo Mac.
- Tradotta in 29 lingue, segue la lingua di sistema.

## Requisiti

- Mac Apple Silicon, macOS 14 o successivo.
- Xcode Command Line Tools per compilare: `xcode-select --install`. Se la compilazione dice che sono troppo vecchi per il tuo macOS, aggiornali da Impostazioni di Sistema → Generale → Aggiornamento Software.
- Un'istanza di Home Assistant (2025.3 o successivo) con l'integrazione Philips HomeID e la friggitrice già abbinata nell'app Philips ufficiale.
- Docker Desktop, se vuoi eseguire Home Assistant sullo stesso Mac con il file compose incluso.

## Installazione

Compilazione dai sorgenti:

```bash
git clone https://github.com/<tuo-utente>/airfryer-mac.git
cd airfryer-mac
./Installa.command        # oppure: bash Tools/build.sh
```

L'app viene creata in `build/Airfryer Mac.app`: trascinala in Applicazioni. Gli archivi di rilascio hanno firma ad-hoc e **non sono notarizzati**: al primo avvio fai clic destro sull'app e scegli Apri.

## Configurazione

1. **Home Assistant.** `cd homeassistant && docker compose up -d`, poi apri <http://localhost:8123> e crea il tuo utente. Salta questo passo se hai già Home Assistant.
2. **Integrazione.** Installa *Philips HomeID* con HACS, oppure copia `custom_components/philips_homeid` dal suo repository in `homeassistant/config/custom_components/` e riavvia Home Assistant. Aggiungila da Impostazioni → Dispositivi e servizi e accedi con l'email del tuo account HomeID (ricevi un codice monouso).
3. **Token.** In Home Assistant apri il profilo → Sicurezza → *Token di accesso a lunga durata* → Crea token. Copialo subito e non condividerlo mai.
4. **App.** Apri Airfryer Mac, inserisci nelle Impostazioni l'indirizzo di Home Assistant (per esempio `http://localhost:8123`) e incolla il token, poi *Salva e collega*. Le sette entità vengono associate in automatico: controllale in *Entità associate*.

## Sicurezza e privacy

- Il token è salvato nel Portachiavi di macOS, legato all'indirizzo del server. Puoi revocarlo in qualsiasi momento da Home Assistant.
- Con HTTP semplice il token viaggia in chiaro: usalo solo su una rete fidata, oppure usa HTTPS.
- L'app non segue i redirect, non accetta certificati TLS non validi e non invia telemetria. Parla solo con l'indirizzo di Home Assistant che configuri.
- `homeassistant/config/` contiene database, log e token di accesso: è escluso da git, non farne mai il commit.

## Sviluppo

```bash
bash Tests/run.sh                          # test della logica contro un finto Home Assistant
python3 Tools/l10n/generate.py             # valida le traduzioni e rigenera Resources/*.lproj
python3 Tools/l10n/check_code.py           # ogni stringa dell'interfaccia nel codice ha una chiave
swiftc -O Tools/make_icon.swift -o build/make_icon && build/make_icon build/icon   # icone app e barra dei menu
bash Tools/make_release.sh                 # dist/AirfryerMac-<versione>.zip
```

### Traduzioni

Le chiavi sono le frasi inglesi del codice; le traduzioni stanno in `Tools/l10n/lang_*.py`. Sono state scritte con un modello di intelligenza artificiale e **non sono state riviste da madrelingua**: le correzioni via pull request sono molto gradite.

## Stato e limiti

- Sviluppata su una Philips Airfryer serie 5000 (HD9255, firmware 4.0.0 / 0.6.8). Altri modelli e firmware non sono stati provati.
- Verificati su quell'apparecchio: collegamento, associazione automatica delle entità e accensione/spegnimento. Impostazione dei valori, avvio, pausa e arresto sono implementati tramite le entità dell'integrazione e coperti da test su un server finto; verificali sulla tua friggitrice prima di farci affidamento.
- "Successo" significa che Home Assistant ha ricevuto il comando, non che l'apparecchio l'ha eseguito: controlla sempre la friggitrice.
- Non notarizzata; nessun aggiornamento automatico.

## Licenza

Airfryer Mac è software libero, rilasciato sotto la [GNU General Public License v3.0 o successiva](LICENSE) (GPL-3.0-or-later): puoi usarlo, studiarlo, condividerlo e modificarlo; ogni versione modificata distribuita deve restare sotto la stessa licenza con il sorgente disponibile. L'integrazione Philips HomeID è un progetto separato con la propria licenza e non è inclusa.
