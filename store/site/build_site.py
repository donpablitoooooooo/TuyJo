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
        ('Tutto il giorno', 'Il filo diretto <span class="serif-em">tra voi due.</span>',
         "Ogni messaggio si cifra sul tuo telefono e si riapre solo sul suo. Una conversazione sola, che non finisce in mezzo ad altre venti.",
         'La chat di Tuijo con i messaggi della giornata e le spunte di lettura.'),
        ('La settimana', 'Le cose da fare, <span class="serif-em">le ricordate in due.</span>',
         "La cena di venerdì, il treno da prenotare, i fiori per sua madre: un promemoria con data e ora compare nella chat di tutti e due, e un'ora prima avvisa entrambi.",
         'Il calendario condiviso di Tuijo con i promemoria del giorno selezionato.'),
        ('Nel tempo', 'Un anno di cose vostre, <span class="serif-em">in ordine.</span>',
         "Le foto, i video, i link e i documenti che vi siete mandati si raccolgono mese per mese. Niente più scroll all'indietro per ritrovare quella foto di agosto.",
         'La galleria di Tuijo con le foto raccolte per mese.'),
        ('Quando scrivere non basta', 'Due tocchi e <span class="serif-em">vi sentite.</span>',
         "La chiamata parte dalla chat e viaggia peer-to-peer, diretta da un telefono all'altro.",
         'La schermata di chiamata vocale di Tuijo con durata e qualità della connessione.'),
        ('E quando uno dei due è in giro', 'Sapere quanto manca.',
         "Posizione live per un'ora o per otto, con la distanza al metro. Poi si spegne da sola.",
         'La schermata della posizione live di Tuijo con la distanza in metri.'),
        ('Primo avvio', 'Si comincia con <span class="serif-em">un QR.</span>',
         "Niente email, niente numero di telefono, niente password. Un telefono mostra il codice, l'altro lo inquadra: da lì in poi esistete solo voi due.",
         'La schermata di abbinamento di Tuijo con il codice QR.'),
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
    scene=dict(steps=('Mostra il codice', 'Inquadra', 'Abbinati'), alt_qr="Il telefono che mostra il codice QR da far inquadrare.", alt_scan="Lo scanner di Tuijo mentre inquadra il telefono dell'altra persona.", alt_lock="Il codice QR dell'altro telefono a fuoco dentro lo scanner.", alt_done="Il secondo passo dell'abbinamento completato, con la conferma dell'app."),
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
        ('All day', 'The direct line <span class="serif-em">between you two.</span>',
         "Every message is encrypted on your phone and only opens again on theirs. One conversation, not one more lost among twenty others.",
         'The Tuijo chat with the day\'s messages and the read receipts.'),
        ('The week', 'The things to do, <span class="serif-em">remembered by both.</span>',
         "Friday's dinner, the train to book, flowers for her mother: a reminder with date and time shows up in both chats, and an hour before it alerts you both.",
         'The Tuijo shared calendar with the reminders of the selected day.'),
        ('Over time', 'A year of your things, <span class="serif-em">in order.</span>',
         "The photos, videos, links and files you have sent each other are gathered month by month. No more scrolling back to find that photo from August.",
         'The Tuijo gallery with photos gathered by month.'),
        ('When writing is not enough', 'Two taps and <span class="serif-em">you hear each other.</span>',
         "The call starts from the chat and travels peer-to-peer, straight from one phone to the other.",
         'The Tuijo voice call screen with duration and connection quality.'),
        ('And when one of you is out', 'Knowing how far away they are.',
         "Live location for one hour or eight, with the distance to the metre. Then it switches itself off.",
         'The Tuijo live location screen with the distance in metres.'),
        ('Getting started', 'It starts with <span class="serif-em">a QR code.</span>',
         "No email, no phone number, no password. One phone shows the code, the other scans it: from then on it is just the two of you.",
         'The Tuijo pairing screen with the QR code.'),
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
    scene=dict(steps=('Show the code', 'Scan it', 'Paired'), alt_qr="The phone showing the QR code to be scanned.", alt_scan="The Tuijo scanner framing the other person's phone.", alt_lock="The other phone's QR code in focus inside the scanner.", alt_done="The second pairing step completed, with the app's confirmation."),
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
        ('Todo el día', 'El hilo directo <span class="serif-em">entre vosotros dos.</span>',
         "Cada mensaje se cifra en tu móvil y solo se vuelve a abrir en el suyo. Una sola conversación, que no se pierde entre otras veinte.",
         'El chat de Tuijo con los mensajes del día y los acuses de lectura.'),
        ('La semana', 'Las cosas por hacer, <span class="serif-em">las recordáis los dos.</span>',
         "La cena del viernes, el tren por reservar, las flores para su madre: un recordatorio con fecha y hora aparece en el chat de ambos, y una hora antes os avisa a los dos.",
         'El calendario compartido de Tuijo con los recordatorios del día seleccionado.'),
        ('Con el tiempo', 'Un año de cosas vuestras, <span class="serif-em">en orden.</span>',
         "Las fotos, los vídeos, los enlaces y los documentos que os habéis enviado se reúnen mes a mes. Se acabó rebuscar hacia atrás aquella foto de agosto.",
         'La galería de Tuijo con las fotos reunidas por mes.'),
        ('Cuando escribir no basta', 'Dos toques y <span class="serif-em">os oís.</span>',
         "La llamada sale del chat y viaja peer-to-peer, directa de un móvil al otro.",
         'La pantalla de llamada de voz de Tuijo con duración y calidad de conexión.'),
        ('Y cuando uno de los dos está fuera', 'Saber cuánto falta.',
         "Ubicación en directo durante una hora u ocho, con la distancia al metro. Después se apaga sola.",
         'La pantalla de ubicación en directo de Tuijo con la distancia en metros.'),
        ('Primer inicio', 'Se empieza con <span class="serif-em">un QR.</span>',
         "Sin correo, sin número de teléfono, sin contraseña. Un móvil muestra el código, el otro lo escanea: a partir de ahí estáis solo vosotros dos.",
         'La pantalla de emparejamiento de Tuijo con el código QR.'),
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
    scene=dict(steps=('Muestra el código', 'Escanea', 'Emparejados'), alt_qr="El móvil que muestra el código QR para escanear.", alt_scan="El escáner de Tuijo enfocando el móvil de la otra persona.", alt_lock="El código QR del otro móvil enfocado dentro del escáner.", alt_done="El segundo paso del emparejamiento completado, con la confirmación de la app."),
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
        ('Tot el dia', 'El fil directe <span class="serif-em">entre vosaltres dos.</span>',
         "Cada missatge es xifra al teu mòbil i només es torna a obrir al seu. Una sola conversa, que no es perd enmig d'altres vint.",
         "El xat de Tuijo amb els missatges del dia i les confirmacions de lectura."),
        ('La setmana', 'Les coses per fer, <span class="serif-em">les recordeu tots dos.</span>',
         "El sopar de divendres, el tren per reservar, les flors per a la seva mare: un recordatori amb data i hora apareix al xat de tots dos, i una hora abans us avisa als dos.",
         'El calendari compartit de Tuijo amb els recordatoris del dia seleccionat.'),
        ('Amb el temps', 'Un any de coses vostres, <span class="serif-em">en ordre.</span>',
         "Les fotos, els vídeos, els enllaços i els documents que us heu enviat es recullen mes a mes. S'ha acabat buscar enrere aquella foto d'agost.",
         'La galeria de Tuijo amb les fotos recollides per mes.'),
        ("Quan escriure no n'hi ha prou", 'Dos tocs i <span class="serif-em">us sentiu.</span>',
         "La trucada surt del xat i viatja peer-to-peer, directa d'un mòbil a l'altre.",
         'La pantalla de trucada de veu de Tuijo amb durada i qualitat de connexió.'),
        ('I quan un dels dos és fora', 'Saber quant falta.',
         "Ubicació en directe durant una hora o vuit, amb la distància al metre. Després s'apaga sola.",
         "La pantalla d'ubicació en directe de Tuijo amb la distància en metres."),
        ('Primer inici', 'Es comença amb <span class="serif-em">un QR.</span>',
         "Sense correu, sense número de telèfon, sense contrasenya. Un mòbil mostra el codi, l'altre l'escaneja: a partir d'aquí només hi sou vosaltres dos.",
         "La pantalla d'aparellament de Tuijo amb el codi QR."),
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
    scene=dict(steps=('Mostra el codi', 'Escaneja', 'Aparellats'), alt_qr="El mòbil que mostra el codi QR per escanejar.", alt_scan="L'escàner de Tuijo enfocant el mòbil de l'altra persona.", alt_lock="El codi QR de l'altre mòbil enfocat dins l'escàner.", alt_done="El segon pas de l'aparellament completat, amb la confirmació de l'app."),
    hero_alt="Dos mòbils l'un al costat de l'altre: el xat de Tuijo i la pantalla d'ubicació compartida.",
)

SEC_IDS = ['chat', 'sicurezza', 'faq']   # ancore uguali in tutte le lingue

# Impianto di ciascuna delle sei sezioni prodotto, nell'ordine.
#   split      → testo a sinistra, immagine a destra
#   split rev  → immagine a sinistra, testo a destra
#   center     → immagine grande centrata, poggiata sul bordo inferiore
#   cardshot   → ritaglio largo dell'interfaccia, centrato sotto al testo
#   scene      → due telefoni che si avvicinano man mano che si scorre (sticky)
# 'img' dice quale file usare: il telefono (0N) o il ritaglio a scheda (card-0N).
LAYOUT = [
    dict(cls='split',         shot=1, img='phone', dark=False),   # chat
    dict(cls='split rev',     shot=4, img='phone', dark=True),    # promemoria
    dict(cls='cardshot',      shot=5, img='card',  dark=False),   # galleria
    dict(cls='split',         shot=2, img='phone', dark=True),    # chiamate
    dict(cls='split rev compact', shot=3, img='phone', dark=False),  # posizione
    dict(cls='scene',         shot=6, img='scene', dark=True),    # abbinamento
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
        if lay['img'] == 'scene':
            sn = t['scene']
            qw, qh = png_size(os.path.join(OUT, 'assets', 'shots', code, f"{lay['shot']:02d}-{code}.png"))
            fw, fh = png_size(os.path.join(OUT, 'assets', 'shots', code, f'07-{code}.png'))
            steps = ''.join(f'<li>{x}</li>' for x in sn['steps'])
            # I tre fotogrammi sono schermate vere dell'app: lo scanner che cerca,
            # lo scanner che ha inquadrato, e il passo completato con la conferma.
            frames = ''.join(
                f'''
            <img class="fr fr{n}" src="assets/shots/{code}/{f:02d}-{code}.png" width="{fw}" height="{fh}" loading="lazy" alt="{a}">'''
                for n, (f, a) in enumerate([(7, sn['alt_scan']), (8, sn['alt_lock']), (9, sn['alt_done'])], start=1))
            stages.append(f'''
<section class="stage dark scene" data-scene data-step="2">
  <div class="scene-track">
    <div class="scene-sticky">
      <div class="wrap scene-inner">
        <div class="copy">
          <span class="eyebrow">{eyebrow}</span>
          <h2>{h2}</h2>
          <p class="lead">{lead}</p>
          <ol class="scene-steps">{steps}</ol>
        </div>
        <div class="scene-stage">
          <img class="ph ph-qr" src="assets/shots/{code}/{lay['shot']:02d}-{code}.png" width="{qw}" height="{qh}" loading="lazy" alt="{sn['alt_qr']}">
          <span class="ph ph-scan">{frames}
          </span>
          <span class="scene-glow"></span>
        </div>
      </div>
    </div>
  </div>
</section>''')
            continue
        card = lay['img'] == 'card'
        name = f"{'card-' if card else ''}{lay['shot']:02d}-{code}.png"
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
