# -*- coding: utf-8 -*-
"""Genera le quattro homepage del sito Tuijo (it/en/es/ca) da un'unica
struttura di testi, così le lingue non divergono fra loro.

    python3 store/site/build_site.py

Scrive public/index.html, en.html, es.html, ca.html. Le pagine privacy non
vengono toccate: usano ancora styles.css e il loro markup.
"""
import io, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'public')

STORE = {
    'it': dict(apple='https://apps.apple.com/it/app/tuijo/id6757800731', badge='it-it', play='assets/google-play-it.svg', privacy='privacy-it-v1.1.html', page='index.html'),
    'en': dict(apple='https://apps.apple.com/us/app/tuijo/id6757800731', badge='en-us', play='assets/google-play-en.svg', privacy='privacy-en-v1.1.html', page='en.html'),
    'es': dict(apple='https://apps.apple.com/es/app/tuijo/id6757800731', badge='es-es', play='assets/google-play-es.svg', privacy='privacy-es-v1.1.html', page='es.html'),
    'ca': dict(apple='https://apps.apple.com/es/app/tuijo/id6757800731', badge='es-es', play='assets/google-play-ca.svg', privacy='privacy-ca-v1.1.html', page='ca.html'),
}
PLAY = 'https://play.google.com/store/apps/details?id=com.privatemessaging.private_messaging'
LOCALE = {'it': 'it_IT', 'en': 'en_US', 'es': 'es_ES', 'ca': 'ca_ES'}

T = {}

T['it'] = dict(
    lang='it', title='Tuijo — Per due. La chat privata cifrata end-to-end',
    desc="Tuijo è la chat per due persone: messaggi, chiamate, posizione, promemoria e ricordi cifrati end-to-end. Nessun account, nessun numero di telefono.",
    og_title='Tuijo. Per due.', og_desc='Una chat privata che vive solo sui vostri due telefoni.',
    nav=('Funzioni', 'Sicurezza', 'Domande'), nav_cta='Scarica',
    h1='Tuijo. Per due.', lead='Una chat privata che vive solo sui vostri due telefoni.',
    note='iPhone e Android · italiano, inglese, spagnolo, catalano',
    apple_alt='Scarica su App Store', play_alt='Disponibile su Google Play',
    sections=[
        ('Chat', 'Messaggi che restano <span class="serif-em">tra voi.</span>',
         "Ogni messaggio viene cifrato sul tuo telefono e si riapre solo sul suo. In mezzo non passa nessuno.",
         'La chat di Tuijo con i messaggi, la posizione condivisa e l\'indicatore "sta scrivendo".'),
        ('Chiamate', 'Voce a voce, <span class="serif-em">e nient\'altro.</span>',
         "L'audio viaggia peer-to-peer, direttamente da un telefono all'altro, con la schermata di chiamata nativa di iOS e Android.",
         'La schermata di chiamata vocale di Tuijo con durata, qualità della connessione e comandi.'),
        ('Posizione', 'Quanto manca, <span class="serif-em">momento per momento.</span>',
         "Condividi dove sei per un'ora o per otto: una freccia, la distanza aggiornata al metro, e poi si spegne da sola.",
         'La schermata della posizione live di Tuijo con la freccia di direzione e la distanza in metri.'),
        ('Promemoria', 'Le cose da fare, <span class="serif-em">in due.</span>',
         "Un impegno con data e ora compare nella chat di entrambi, e un'ora prima l'avviso arriva a tutti e due.",
         'Il calendario condiviso di Tuijo con i promemoria del giorno selezionato.'),
        ('Galleria', 'Tutto quello che vi siete mandati.',
         "Foto, video, link e documenti raccolti mese per mese, senza doverli ripescare nella conversazione.",
         'La galleria di Tuijo con le foto raccolte per mese e i filtri per link e documenti.'),
        ('Primo avvio', 'Si comincia con <span class="serif-em">un QR.</span>',
         "Niente email, niente numero di telefono, niente password. Un telefono mostra il codice, l'altro lo inquadra.",
         'La schermata di abbinamento di Tuijo con il codice QR da mostrare e il pulsante per scansionare.'),
    ],
    band=('Due telefoni, una conversazione.', 'Niente gruppi, niente contatti, niente feed: Tuijo si collega a una persona sola.'),
    sec_eyebrow='Sicurezza', sec_h2='Nemmeno noi possiamo leggervi.',
    sec_lead="Non è una promessa commerciale: è il modo in cui l'app è costruita.",
    sec_items=[
        ('01 · LE CHIAVI', 'Restano sul telefono', "La chiave privata nasce sul dispositivo al primo avvio e non lo lascia mai. Sui nostri server non arriva, quindi non può essere consegnata a nessuno."),
        ('02 · I MESSAGGI', 'Una chiave nuova ogni volta', "Ogni messaggio usa una chiave AES-256 usa e getta, chiusa a sua volta con la chiave pubblica di entrambi i dispositivi."),
        ('03 · IL SERVER', 'Vede solo dati cifrati', "Nel cloud transita testo illeggibile. Anche le coordinate della posizione viaggiano cifrate e la sessione scade da sola."),
    ],
    sec_foot='RSA-2048 + AES-256 · nessun account e nessun numero di telefono · <b>zero-knowledge</b>',
    faq_h2='Domande',
    faq=[
        ('Su quali dispositivi funziona?', "Su iPhone tramite App Store e su Android tramite Google Play. L'interfaccia è disponibile in italiano, inglese, spagnolo e catalano."),
        ('Serve un account?', "No. Non c'è registrazione: i due telefoni si riconoscono scambiandosi le chiavi pubbliche con un codice QR, e da quel momento la conversazione esiste solo tra loro."),
        ('La posizione condivisa è davvero privata?', "Le coordinate vengono cifrate con una chiave dedicata alla sessione, che dura una o otto ore e poi scade. Sul server non resta una posizione leggibile."),
        ('Si può usare in tre?', "No, ed è una scelta di progetto: un dispositivo si abbina a un altro dispositivo. Non ci sono gruppi né rubrica."),
    ],
    cta='Scaricatela e abbinate i telefoni.',
    foot_privacy='Privacy', foot_support='Supporto', foot_tag='tu i jo, tu e io',
    hero_alt='Due telefoni affiancati: la chat di Tuijo e la schermata della posizione condivisa.',
)

T['en'] = dict(
    lang='en', title='Tuijo — For two. The private end-to-end encrypted chat',
    desc="Tuijo is the chat for two people: messages, calls, location, reminders and memories, encrypted end-to-end. No account, no phone number.",
    og_title='Tuijo. For two.', og_desc='A private chat that lives only on your two phones.',
    nav=('Features', 'Security', 'Questions'), nav_cta='Download',
    h1='Tuijo. For two.', lead='A private chat that lives only on your two phones.',
    note='iPhone and Android · English, Italian, Spanish, Catalan',
    apple_alt='Download on the App Store', play_alt='Get it on Google Play',
    sections=[
        ('Chat', 'Messages that stay <span class="serif-em">between you.</span>',
         "Every message is encrypted on your phone and only opens again on theirs. Nothing passes in between.",
         'The Tuijo chat with messages, shared location and the typing indicator.'),
        ('Calls', 'Voice to voice, <span class="serif-em">nothing else.</span>',
         "Audio travels peer-to-peer, straight from one phone to the other, with the native call screen on iOS and Android.",
         'The Tuijo voice call screen with duration, connection quality and controls.'),
        ('Location', 'How far, <span class="serif-em">moment by moment.</span>',
         "Share where you are for one hour or eight: an arrow, the distance updated to the metre, and then it switches itself off.",
         'The Tuijo live location screen with the direction arrow and the distance in metres.'),
        ('Reminders', 'Things to do, <span class="serif-em">for two.</span>',
         "A reminder with date and time shows up in both chats, and an hour before, the alert reaches you both.",
         'The Tuijo shared calendar with the reminders of the selected day.'),
        ('Gallery', 'Everything you have sent each other.',
         "Photos, videos, links and files gathered month by month, with no digging through the conversation.",
         'The Tuijo gallery with photos gathered by month and filters for links and files.'),
        ('Getting started', 'It starts with <span class="serif-em">a QR code.</span>',
         "No email, no phone number, no password. One phone shows the code, the other scans it.",
         'The Tuijo pairing screen with the QR code to show and the button to scan.'),
    ],
    band=('Two phones, one conversation.', 'No groups, no contacts, no feed: Tuijo connects to a single person.'),
    sec_eyebrow='Security', sec_h2='Not even we can read you.',
    sec_lead="It is not a marketing promise: it is how the app is built.",
    sec_items=[
        ('01 · THE KEYS', 'They stay on the phone', "The private key is created on the device at first launch and never leaves it. It never reaches our servers, so it cannot be handed over to anyone."),
        ('02 · THE MESSAGES', 'A new key every time', "Every message uses a single-use AES-256 key, which is itself sealed with the public key of both devices."),
        ('03 · THE SERVER', 'Only sees encrypted data', "Unreadable text is all that travels through the cloud. Location coordinates are encrypted too, and the session expires on its own."),
    ],
    sec_foot='RSA-2048 + AES-256 · no account and no phone number · <b>zero-knowledge</b>',
    faq_h2='Questions',
    faq=[
        ('Which devices does it work on?', "On iPhone through the App Store and on Android through Google Play. The interface is available in English, Italian, Spanish and Catalan."),
        ('Do we need an account?', "No. There is no sign-up: the two phones recognise each other by exchanging public keys through a QR code, and from then on the conversation exists only between them."),
        ('Is the shared location really private?', "Coordinates are encrypted with a key dedicated to the session, which lasts one or eight hours and then expires. No readable location is left on the server."),
        ('Can three people use it?', "No, and that is by design: one device pairs with one other device. There are no groups and no address book."),
    ],
    cta='Download it and pair your phones.',
    foot_privacy='Privacy', foot_support='Support', foot_tag='tu i jo — you and me',
    hero_alt='Two phones side by side: the Tuijo chat and the shared location screen.',
)

T['es'] = dict(
    lang='es', title='Tuijo — Para dos. El chat privado cifrado de extremo a extremo',
    desc="Tuijo es el chat para dos personas: mensajes, llamadas, ubicación, recordatorios y recuerdos cifrados de extremo a extremo. Sin cuenta y sin número de teléfono.",
    og_title='Tuijo. Para dos.', og_desc='Un chat privado que vive solo en vuestros dos móviles.',
    nav=('Funciones', 'Seguridad', 'Preguntas'), nav_cta='Descargar',
    h1='Tuijo. Para dos.', lead='Un chat privado que vive solo en vuestros dos móviles.',
    note='iPhone y Android · español, italiano, inglés, catalán',
    apple_alt='Consíguelo en el App Store', play_alt='Disponible en Google Play',
    sections=[
        ('Chat', 'Mensajes que se quedan <span class="serif-em">entre vosotros.</span>',
         "Cada mensaje se cifra en tu móvil y solo se vuelve a abrir en el suyo. Por el medio no pasa nadie.",
         'El chat de Tuijo con los mensajes, la ubicación compartida y el indicador de escritura.'),
        ('Llamadas', 'De voz a voz, <span class="serif-em">y nada más.</span>',
         "El audio viaja peer-to-peer, directo de un móvil al otro, con la pantalla de llamada nativa de iOS y Android.",
         'La pantalla de llamada de voz de Tuijo con duración, calidad de conexión y controles.'),
        ('Ubicación', 'Cuánto falta, <span class="serif-em">momento a momento.</span>',
         "Comparte dónde estás durante una hora u ocho: una flecha, la distancia al metro, y después se apaga sola.",
         'La pantalla de ubicación en directo de Tuijo con la flecha de dirección y la distancia en metros.'),
        ('Recordatorios', 'Las cosas por hacer, <span class="serif-em">entre dos.</span>',
         "Un recordatorio con fecha y hora aparece en el chat de ambos, y una hora antes el aviso llega a los dos.",
         'El calendario compartido de Tuijo con los recordatorios del día seleccionado.'),
        ('Galería', 'Todo lo que os habéis enviado.',
         "Fotos, vídeos, enlaces y documentos reunidos mes a mes, sin rebuscar en la conversación.",
         'La galería de Tuijo con las fotos reunidas por mes y los filtros de enlaces y documentos.'),
        ('Primer inicio', 'Se empieza con <span class="serif-em">un QR.</span>',
         "Sin correo, sin número de teléfono, sin contraseña. Un móvil muestra el código, el otro lo escanea.",
         'La pantalla de emparejamiento de Tuijo con el código QR y el botón para escanear.'),
    ],
    band=('Dos móviles, una conversación.', 'Sin grupos, sin contactos, sin feed: Tuijo se conecta con una sola persona.'),
    sec_eyebrow='Seguridad', sec_h2='Ni siquiera nosotros podemos leeros.',
    sec_lead="No es una promesa comercial: es como está hecha la app.",
    sec_items=[
        ('01 · LAS CLAVES', 'Se quedan en el móvil', "La clave privada nace en el dispositivo al primer inicio y nunca sale de él. No llega a nuestros servidores, así que no se le puede entregar a nadie."),
        ('02 · LOS MENSAJES', 'Una clave nueva cada vez', "Cada mensaje usa una clave AES-256 de un solo uso, cerrada a su vez con la clave pública de ambos dispositivos."),
        ('03 · EL SERVIDOR', 'Solo ve datos cifrados', "Por la nube circula texto ilegible. Las coordenadas de la ubicación también viajan cifradas y la sesión caduca sola."),
    ],
    sec_foot='RSA-2048 + AES-256 · sin cuenta y sin número de teléfono · <b>zero-knowledge</b>',
    faq_h2='Preguntas',
    faq=[
        ('¿En qué dispositivos funciona?', "En iPhone desde la App Store y en Android desde Google Play. La interfaz está disponible en español, italiano, inglés y catalán."),
        ('¿Hace falta una cuenta?', "No. No hay registro: los dos móviles se reconocen intercambiando las claves públicas con un código QR, y desde ese momento la conversación existe solo entre ellos."),
        ('¿La ubicación compartida es realmente privada?', "Las coordenadas se cifran con una clave dedicada a la sesión, que dura una u ocho horas y luego caduca. En el servidor no queda una ubicación legible."),
        ('¿Se puede usar entre tres?', "No, y es una decisión de diseño: un dispositivo se empareja con otro dispositivo. No hay grupos ni agenda."),
    ],
    cta='Descargadla y emparejad los móviles.',
    foot_privacy='Privacidad', foot_support='Soporte', foot_tag='tu i jo — tú y yo',
    hero_alt='Dos móviles uno al lado del otro: el chat de Tuijo y la pantalla de ubicación compartida.',
)

T['ca'] = dict(
    lang='ca', title='Tuijo — Per a dos. El xat privat xifrat d\'extrem a extrem',
    desc="Tuijo és el xat per a dues persones: missatges, trucades, ubicació, recordatoris i records xifrats d'extrem a extrem. Sense compte i sense número de telèfon.",
    og_title='Tuijo. Per a dos.', og_desc='Un xat privat que viu només als vostres dos mòbils.',
    nav=('Funcions', 'Seguretat', 'Preguntes'), nav_cta='Baixa-la',
    h1='Tuijo. Per a dos.', lead='Un xat privat que viu només als vostres dos mòbils.',
    note='iPhone i Android · català, italià, anglès, castellà',
    apple_alt="Baixa-la a l'App Store", play_alt='Disponible a Google Play',
    sections=[
        ('Xat', 'Missatges que es queden <span class="serif-em">entre vosaltres.</span>',
         "Cada missatge es xifra al teu mòbil i només es torna a obrir al seu. Pel mig no hi passa ningú.",
         "El xat de Tuijo amb els missatges, la ubicació compartida i l'indicador d'escriptura."),
        ('Trucades', 'De veu a veu, <span class="serif-em">i res més.</span>',
         "L'àudio viatja peer-to-peer, directe d'un mòbil a l'altre, amb la pantalla de trucada nativa d'iOS i Android.",
         'La pantalla de trucada de veu de Tuijo amb durada, qualitat de connexió i controls.'),
        ('Ubicació', 'Quant falta, <span class="serif-em">moment a moment.</span>',
         "Comparteix on ets durant una hora o vuit: una fletxa, la distància al metre, i després s'apaga sola.",
         'La pantalla d\'ubicació en directe de Tuijo amb la fletxa de direcció i la distància en metres.'),
        ('Recordatoris', 'Les coses per fer, <span class="serif-em">entre dos.</span>',
         "Un recordatori amb data i hora apareix al xat de tots dos, i una hora abans l'avís arriba als dos.",
         'El calendari compartit de Tuijo amb els recordatoris del dia seleccionat.'),
        ('Galeria', 'Tot el que us heu enviat.',
         "Fotos, vídeos, enllaços i documents recollits mes a mes, sense haver-los de buscar dins la conversa.",
         'La galeria de Tuijo amb les fotos recollides per mes i els filtres d\'enllaços i documents.'),
        ('Primer inici', 'Es comença amb <span class="serif-em">un QR.</span>',
         "Sense correu, sense número de telèfon, sense contrasenya. Un mòbil mostra el codi, l'altre l'escaneja.",
         "La pantalla d'aparellament de Tuijo amb el codi QR i el botó per escanejar."),
    ],
    band=('Dos mòbils, una conversa.', 'Sense grups, sense contactes, sense feed: Tuijo es connecta amb una sola persona.'),
    sec_eyebrow='Seguretat', sec_h2='Ni tan sols nosaltres us podem llegir.',
    sec_lead="No és una promesa comercial: és com està feta l'app.",
    sec_items=[
        ('01 · LES CLAUS', 'Es queden al mòbil', "La clau privada neix al dispositiu al primer inici i no en surt mai. No arriba als nostres servidors, així que no es pot lliurar a ningú."),
        ('02 · ELS MISSATGES', 'Una clau nova cada cop', "Cada missatge fa servir una clau AES-256 d'un sol ús, tancada al seu torn amb la clau pública dels dos dispositius."),
        ('03 · EL SERVIDOR', 'Només veu dades xifrades', "Pel núvol hi circula text il·legible. Les coordenades de la ubicació també viatgen xifrades i la sessió caduca sola."),
    ],
    sec_foot='RSA-2048 + AES-256 · sense compte i sense número de telèfon · <b>zero-knowledge</b>',
    faq_h2='Preguntes',
    faq=[
        ('En quins dispositius funciona?', "A l'iPhone des de l'App Store i a Android des de Google Play. La interfície està disponible en català, italià, anglès i castellà."),
        ('Cal un compte?', "No. No hi ha registre: els dos mòbils es reconeixen intercanviant les claus públiques amb un codi QR, i des d'aquell moment la conversa només existeix entre ells."),
        ('La ubicació compartida és realment privada?', "Les coordenades es xifren amb una clau dedicada a la sessió, que dura una o vuit hores i després caduca. Al servidor no hi queda cap ubicació llegible."),
        ('Es pot fer servir entre tres?', "No, i és una decisió de disseny: un dispositiu s'aparella amb un altre dispositiu. No hi ha grups ni agenda."),
    ],
    cta='Baixeu-la i aparelleu els mòbils.',
    foot_privacy='Privacitat', foot_support='Suport', foot_tag='tu i jo',
    hero_alt="Dos mòbils l'un al costat de l'altre: el xat de Tuijo i la pantalla d'ubicació compartida.",
)

SEC_IDS = ['chat', 'sicurezza', 'faq']   # ancore uguali in tutte le lingue

# Impianto di ciascuna delle sei sezioni prodotto, nell'ordine.
#   split      → testo a sinistra, immagine a destra
#   split rev  → immagine a sinistra, testo a destra
#   center     → immagine grande centrata, poggiata sul bordo inferiore
#   cardshot   → ritaglio largo dell'interfaccia, centrato sotto al testo
# 'img' dice quale file usare: il telefono (0N) o il ritaglio a scheda (card-0N).
LAYOUT = [
    dict(cls='split',        img='phone', dark=False),
    dict(cls='split rev',    img='phone', dark=True),
    dict(cls='center',       img='phone', dark=False),
    dict(cls='split',        img='phone', dark=True),
    dict(cls='cardshot',     img='card',  dark=False),
    dict(cls='split rev',    img='card',  dark=True),
]


def png_size(path):
    """Larghezza e altezza di un PNG, lette dall'header (niente dipendenze)."""
    with open(path, 'rb') as fh:
        head = fh.read(24)
    return int.from_bytes(head[16:20], 'big'), int.from_bytes(head[20:24], 'big')

def badges(t, s, cls):
    return f'''<div class="badges {cls}">
      <a href="{s['apple']}" target="_blank" rel="noopener noreferrer">
        <img src="https://toolbox.marketingtools.apple.com/api/badges/download-on-the-app-store/black/{s['badge']}?size=250x83" alt="{t['apple_alt']}">
      </a>
      <a href="{PLAY}" target="_blank" rel="noopener noreferrer">
        <img src="{s['play']}" alt="{t['play_alt']}">
      </a>
    </div>'''

def build(code):
    t, s = T[code], STORE[code]
    langs = ''
    for c in ('it', 'en', 'es', 'ca'):
        on = ' class="on"' if c == code else ''
        langs += '\n        <a href="%s"%s>%s</a>' % (STORE[c]['page'], on, c.upper())

    hero_w, hero_h = png_size(os.path.join(OUT, 'assets', 'shots', code, f'pair-01-{code}.png'))

    stages = []
    for i, (eyebrow, h2, lead, alt) in enumerate(t['sections'], start=1):
        lay = LAYOUT[i - 1]
        card = lay['img'] == 'card'
        name = f"{'card-' if card else ''}{i:02d}-{code}.png"
        w, h = png_size(os.path.join(OUT, 'assets', 'shots', code, name))
        stages.append(f'''
<section class="stage {lay['cls']}{' dark' if lay['dark'] else ''}"{' id="chat"' if i == 1 else ''}>
  <div class="wrap">
    <div class="copy">
      <span class="eyebrow reveal">{eyebrow}</span>
      <h2 class="reveal">{h2}</h2>
      <p class="lead reveal d1">{lead}</p>
    </div>
    <div class="shot{' wide' if card and 'split' in lay['cls'] else ''} reveal d1">
      <img src="assets/shots/{code}/{name}" width="{w}" height="{h}" loading="lazy" data-move="{20 if card else 26}" alt="{alt}">
    </div>
  </div>
</section>''')

    sec_items = ''.join(
        f'''
      <div class="sec-item reveal{' d' + str(n) if n else ''}">
        <span class="n">{num}</span>
        <h3>{head}</h3>
        <p>{body}</p>
      </div>''' for n, (num, head, body) in enumerate(t['sec_items']))

    faq = ''.join(
        f'''
      <details class="faq">
        <summary>{q}</summary>
        <p>{a}</p>
      </details>''' for q, a in t['faq'])

    return f'''<!DOCTYPE html>
<html lang="{t['lang']}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{t['title']}</title>
<meta name="description" content="{t['desc']}">
<link rel="canonical" href="https://tuyjo.com/{'' if code == 'it' else s['page']}">
<meta property="og:type" content="website">
<meta property="og:title" content="{t['og_title']}">
<meta property="og:description" content="{t['og_desc']}">
<meta property="og:image" content="https://tuyjo.com/assets/og-{code}.png">
<meta property="og:locale" content="{LOCALE[code]}">
<meta name="twitter:card" content="summary_large_image">
<link rel="alternate" hreflang="it" href="https://tuyjo.com/">
<link rel="alternate" hreflang="en" href="https://tuyjo.com/en.html">
<link rel="alternate" hreflang="es" href="https://tuyjo.com/es.html">
<link rel="alternate" hreflang="ca" href="https://tuyjo.com/ca.html">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Hanken+Grotesk:wght@400;600;700&family=Instrument+Serif:ital@0;1&display=swap" rel="stylesheet">
<link rel="icon" type="image/png" href="assets/icon-1024.png">
<link rel="stylesheet" href="site.css">
</head>
<body>

<nav class="nav">
  <div class="wrap nav-inner">
    <a class="brand" href="#top"><img src="assets/cherries.png" alt=""><span>Tuijo</span></a>
    <div class="nav-links">
      <a href="#chat">{t['nav'][0]}</a>
      <a href="#sicurezza">{t['nav'][1]}</a>
      <a href="#faq">{t['nav'][2]}</a>
    </div>
    <div class="nav-right">
      <div class="lang">{langs}
      </div>
      <a class="nav-cta" href="#scarica">{t['nav_cta']}</a>
    </div>
  </div>
</nav>

<!-- ============ HERO ============ -->
<header class="hero" id="top">
  <div class="wrap">
    <h1 class="reveal">{t['h1']}</h1>
    <p class="lead reveal d1">{t['lead']}</p>
    <span id="scarica"></span>
    {badges(t, s, 'reveal d2')}
    <p class="hero-note reveal d2">{t['note']}</p>
    <div class="hero-shot reveal d2">
      <img src="assets/shots/{code}/pair-01-{code}.png" width="{hero_w}" height="{hero_h}" data-move="16" alt="{t['hero_alt']}" fetchpriority="high">
    </div>
  </div>
</header>
{''.join(stages)}

<!-- ============ BANDA FOTOGRAFICA ============ -->
<section class="band">
  <img src="assets/photo/couple.jpg" alt="" loading="lazy">
  <div class="band-copy">
    <p>{t['band'][0]}<span>{t['band'][1]}</span></p>
  </div>
</section>

<!-- ============ SICUREZZA ============ -->
<section class="security" id="sicurezza">
  <div class="wrap">
    <span class="eyebrow reveal">{t['sec_eyebrow']}</span>
    <h2 class="reveal">{t['sec_h2']}</h2>
    <p class="lead reveal d1">{t['sec_lead']}</p>
    <div class="sec-grid">{sec_items}
    </div>
    <p class="sec-foot reveal">{t['sec_foot']}</p>
  </div>
</section>

<!-- ============ DOMANDE ============ -->
<section class="faq-sec" id="faq">
  <div class="wrap">
    <h2 class="reveal">{t['faq_h2']}</h2>
    <div class="faq-list reveal d1">{faq}
    </div>
  </div>
</section>

<!-- ============ CTA ============ -->
<section class="cta">
  <div class="wrap">
    <h2 class="reveal">{t['cta']}</h2>
    {badges(t, s, 'reveal d1')}
  </div>
</section>

<footer class="foot">
  <div class="wrap">
    <div class="foot-nav">
      <a href="#chat">{t['nav'][0]}</a>
      <a href="#sicurezza">{t['nav'][1]}</a>
      <a href="#faq">{t['nav'][2]}</a>
      <a href="{s['privacy']}">{t['foot_privacy']}</a>
      <a href="mailto:support@tuyjo.com">{t['foot_support']}</a>
      <a href="{s['apple']}" target="_blank" rel="noopener noreferrer">App Store</a>
      <a href="{PLAY}" target="_blank" rel="noopener noreferrer">Google Play</a>
    </div>
    <div class="foot-bottom">© <span id="year">2026</span> Tuijo · {t['foot_tag']}</div>
  </div>
</footer>

<script src="site.js"></script>
</body>
</html>
'''

for code in ('it', 'en', 'es', 'ca'):
    path = os.path.join(OUT, STORE[code]['page'])
    io.open(path, 'w', encoding='utf-8').write(build(code))
    print('scritto', path)
