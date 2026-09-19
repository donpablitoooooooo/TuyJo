# Foto vere per la galleria

Le schermate della galleria (`mediaScreen`) disegnano per default dei riquadri
astratti a gradiente: servono a far vedere la griglia senza inventare ricordi di
qualcun altro. Se in questa cartella ci sono delle immagini, `render.js` le passa
alla pagina e le prime tessere della griglia diventano **foto vere**.

```
store/screenshots/src/img/photos/01.jpg, 02.jpg, …
```

Vengono usate in ordine alfabetico: le prime sei finiscono nel mese in alto —
quelle che si vedono nel ritaglio usato dal sito. Le tessere rimaste tornano ai
gradienti, quindi anche tre o quattro foto bastano.

## Requisiti

| Voce | Valore |
|---|---|
| Formato | JPEG, PNG o WebP |
| Taglio | **quadrato** (le tessere sono 1:1, il resto viene tagliato al centro) |
| Dimensione | 800 × 800 px bastano: nel ritaglio finale una tessera sta in ~300 px |
| Soggetto | quello che si manderebbe davvero una coppia: un piatto, un cane, il mare, una serata |

Dopo averle messe qui, rigenera e rialleggerisci:

```bash
cd store/screenshots/src
node render.js --target web-card --shot 5 --out ../../../public/assets
node webp.js ../../../public/assets/shots
```

## Attenzione alle licenze

Non mettere qui foto prese da un motore di ricerca. Le licenze Unsplash e Pexels
coprono l'uso commerciale dell'immagine, ma **non** danno diritti sulla persona
ritratta: una faccia riconoscibile usata nella pagina di vendita di un prodotto
può richiedere una liberatoria (in Italia: art. 96-97 legge 633/1941). Per una
galleria di coppia la via semplice è ovvia — **foto vostre**, oppure immagini
senza volti riconoscibili.

Fonti con uso commerciale libero, se servono:

- **Unsplash** — <https://unsplash.com/license>
- **Pexels** — <https://www.pexels.com/license/>
- **Openverse** — <https://openverse.org> (filtra su "uso commerciale"; la
  licenza va letta caso per caso, alcune CC chiedono attribuzione)

Se prendi una foto da fuori, segnala qui sotto da dove viene:

| File | Fonte | Autore | Licenza | Data |
|---|---|---|---|---|
| — | — | — | — | — |
