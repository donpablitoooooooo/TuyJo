# Foto della banda del sito

Qui va **una sola foto**, usata a tutta larghezza fra le schermate e la sezione
Sicurezza, in tutte e quattro le lingue:

```
public/assets/photo/couple.jpg
```

Finché il file non c'è, la banda resta con il fondo teal pieno e il testo sopra:
`site.js` intercetta l'errore di caricamento e aggiunge la classe `no-photo`.
Il sito non si rompe, quindi si può pubblicare anche senza foto.

## Requisiti del file

| Voce | Valore |
|---|---|
| Nome | `couple.jpg` |
| Formato | JPEG (o `couple.webp` + `<source>`, se si aggiunge il `<picture>`) |
| Dimensione | 2400 × 1400 px circa, orizzontale |
| Peso | sotto i 400 KB (comprimere a qualità ~78) |
| Ritaglio | il soggetto **non** al centro: lì passa il testo bianco |

La banda scurisce già la foto con un gradiente (`.band::after`), quindi serve
un'immagine che regga il buio: niente scene già scurissime.

## Scelta del soggetto

Il testo sopra la foto dice "Due telefoni, una conversazione". La foto giusta è
quella che **non** mostra volti riconoscibili: mani, una schiena, due persone di
spalle, una silhouette controluce, un dettaglio fuori fuoco. Due motivi:

1. **Editoriale** — un'app che vende privacy con due facce sorridenti in posa da
   stock photo si contraddice da sola.
2. **Legale** — le licenze Unsplash e Pexels coprono l'uso commerciale
   dell'immagine, ma **non** danno diritti sulla persona ritratta. Una foto di
   persona identificabile usata sulla pagina di vendita di un prodotto può
   configurare un uso del ritratto che richiede una liberatoria (in Italia:
   art. 96-97 legge 633/1941). Con un soggetto non identificabile il problema
   non si pone.

## Dove prenderla

- **Unsplash** — <https://unsplash.com/license> (uso commerciale, niente
  attribuzione richiesta)
- **Pexels** — <https://www.pexels.com/license/>
- **Openverse** — <https://openverse.org> (filtrare su "uso commerciale"; qui la
  licenza va letta caso per caso, alcune CC chiedono attribuzione)

Termini di ricerca che funzionano: `couple hands`, `holding hands walking`,
`couple silhouette sunset`, `two people back view`, `hands phone`.

**Annota sempre la provenienza** aggiungendo una riga qui sotto quando aggiungi
il file, così fra sei mesi si sa da dove viene:

| File | Fonte | Autore | Licenza | Data |
|---|---|---|---|---|
| couple.jpg | — | — | — | — |
