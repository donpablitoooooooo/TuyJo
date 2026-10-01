# Anteprime per la scheda dei link

Nella scheda "link" della galleria ogni card ha una miniatura: nell'app è
l'anteprima che il sito linkato pubblica (og:image), scaricata e cifrata come
gli altri allegati. Nel mock, per default, è disegnata — mare, casa, mappa,
tazzina, luci — perché da qui non si possono scaricare le immagini vere.

Se in questa cartella ci sono dei file, prendono il loro posto, in ordine
alfabetico, una per card:

```
store/screenshots/src/img/links/01.jpg → Hotel (booking.com)
                                02.jpg → Casa (airbnb)
                                03.jpg → Locale (maps.google.com)
                                04.jpg → Ricetta
                                05.jpg → Concerto
```

## Requisiti

| Voce | Valore |
|---|---|
| Formato | JPEG, PNG o WebP (niente HEIC: il renderer non lo apre) |
| Taglio | orizzontale; l'immagine viene ritagliata al centro nell'altezza della card |
| Dimensione | 600 px di larghezza bastano |

Le altezze delle card restano quelle fisse del mock (120, 96, 74, 108, 88 px):
sono loro a dare l'effetto masonry, come la `MasonryGridView` dell'app.

Dopo aver aggiunto i file:

```bash
cd store/screenshots/src
node render.js --target web --shot 11 --out ../../../public/assets
node webp.js ../../../public/assets/shots
```

## Attenzione

Se lo screenshot contiene la grafica o il logo del sito linkato, quella è roba
di qualcun altro: va bene dentro l'app (è il contenuto che l'utente ha
ricevuto), molto meno in una pagina promozionale. Per il sito è più prudente
un'immagine neutra — una foto del posto, non la pagina del servizio.
