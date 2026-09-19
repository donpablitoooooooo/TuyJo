# Foto della galleria

Le schermate della galleria (`mediaScreen`) disegnano per default dei riquadri
astratti a gradiente. I file che stanno qui li sostituiscono, in ordine
alfabetico: le prime sei finiscono nel mese in alto, quelle che si vedono nel
sito. Le tessere che avanzano tornano ai gradienti.

Due convenzioni sui nomi:

- un file che contiene **`chat`** nel nome è anche la foto che compare dentro la
  conversazione, nel messaggio delle 21:08;
- un file che comincia con **`_`** viene ignorato: sta qui ma non finisce da
  nessuna parte.

## Cosa c'è adesso

| File | Soggetto | Dove si vede | Autore (Pexels) |
|---|---|---|---|
| `01-coppia-prato.jpg` | Coppia sdraiata sull'erba | prima tessera | Habib Hosseini |
| `02-chat-pizza.jpg` | Pizza al tavolo | seconda tessera **e foto in chat** | Valeriya |
| `03-venezia.jpg` | Canale di Venezia | terza tessera | Aisha Serafini |
| `04-deserto.jpg` | Dune | quarta tessera | Lost Boy |
| `05-colosseo.jpg` | Colosseo fra i pini | quinta tessera | Maurits Bausenhart |
| `06-cascate.jpg` | Cascate | sesta tessera | Ali Soheil |
| `07-geroglifici.jpg` | Geroglifici | mese di agosto | M. Abnodey |
| `08-festa.jpg` | Festa con palloncini | mese di agosto | Jonathan Valdés |
| `_torta-bambini.jpg` | Bambine con la torta | **non usata** | Ivan S |

L'ultima è esclusa apposta. Sono minori riconoscibili: la licenza Pexels
copre l'uso commerciale dell'immagine, ma dei volti di bambini nella pagina
promozionale di un prodotto sono il caso più delicato che ci sia, e la foto non
aggiunge niente che le altre non diano già. Se la vuoi, togli l'underscore dal
nome.

## Requisiti

| Voce | Valore |
|---|---|
| Formato | JPEG, PNG o WebP (niente HEIC: il renderer non lo apre) |
| Taglio | quadrato o quasi: le tessere sono 1:1 e il resto viene tagliato al centro |
| Dimensione | 800 × 800 px bastano; nel sito una tessera sta in ~100 px |

Dopo aver aggiunto o cambiato i file:

```bash
cd store/screenshots/src
node render.js --target web --shot 1,5 --out ../../../public/assets
node webp.js ../../../public/assets/shots
python3 ../../site/build_site.py
```

## Licenza

Le foto qui sono di [Pexels](https://www.pexels.com/license/): uso commerciale
libero, attribuzione non richiesta — la tabella qui sopra la tiene lo stesso,
perché fra sei mesi nessuno si ricorda da dove veniva un file.

Se ne aggiungi altre prese da fuori, ricordati che la licenza copre l'immagine,
non la persona ritratta: un volto riconoscibile nella pagina di vendita di un
prodotto può richiedere una liberatoria (in Italia: art. 96-97 legge 633/1941).
Le foto vostre sono sempre la strada semplice.
