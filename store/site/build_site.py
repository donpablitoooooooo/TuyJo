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
    desc="Tuijo è la chat per due persone: messaggi, promemoria condivisi, ricordi e chiamate, cifrati end-to-end. Nessun account, nessun numero di telefono.",
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
        ('Quando scrivere non basta', 'Un tocco e <span class="serif-em">vi sentite.</span>',
         "La cornetta è dentro la chat: un tocco e parte la chiamata, peer-to-peer, diretta da un telefono all'altro.",
         'La schermata di chiamata vocale di Tuijo con durata e qualità della connessione.'),
        ('Primo avvio', 'Si comincia con <span class="serif-em">un QR.</span>',
         "Ognuno mostra il suo codice e inquadra quello dell'altro. Niente email, niente numero di telefono, niente password: da lì in poi esistete solo voi due.",
         'La schermata di abbinamento di Tuijo con il codice QR.'),
    ],
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
        ("Ho perso il telefono, o ne ho comprato uno nuovo. Recupero la chat?", "Sì. Sul telefono nuovo apri Impostazioni → Recupera i messaggi e scegli da dove: dal telefono del partner o dal tuo vecchio telefono. Il telefono nuovo mostra un QR che vale dieci minuti, l'altro lo inquadra da Impostazioni → Aiuta il partner a recuperare (oppure Trasferisci), e il certificato arriva cifrato solo per quel dispositivo: la chat si ricompone da sola."),
        ("Come si cancellano i messaggi?", "Da Impostazioni → Elimina Messaggi, a tre livelli: solo da questo telefono, solo dal telefono del partner, oppure da tutti e due e anche dal server. I primi due lasciano la chat sul server, quindi rifacendo il pairing torna; l'ultimo è irreversibile."),
    ],
    cta='Scaricatela e abbinate i telefoni.',
    foot_privacy='Privacy', foot_support='Supporto', foot_tag='tu i jo, tu e io',
    reels={2: ["La galleria di Tuijo con le foto raccolte per mese.", "La scheda dei link salvati nella chat, con titolo e dominio.", "La scheda dei documenti condivisi, con peso e data."], 3: ["La chat di Tuijo con la cornetta accanto al menù.", "Il dito che tocca la cornetta dentro la chat.", "La schermata di chiamata vocale di Tuijo."]},
    scene=dict(steps=('Uno inquadra', "L'altro inquadra", 'Siete in chat'), alt_qr="Il telefono che mostra il proprio codice QR.", alt_scan="Lo scanner di Tuijo mentre inquadra il telefono dell'altra persona.", alt_lock="Il codice QR dell'altro telefono a fuoco dentro lo scanner.", alt_done="Il passo completato, con la conferma dell'app.", alt_chat="La chat aperta sul primo telefono, ad abbinamento fatto.", alt_chat2="La stessa chat vista dal secondo telefono, con il messaggio che l'altra persona sta scrivendo."),
    hero_alt='Due telefoni affiancati: la chat di Tuijo e il calendario dei promemoria condivisi.',
)

T['en'] = dict(
    lang='en', title='Tuijo — For two. The private end-to-end encrypted chat',
    desc="Tuijo is the chat for two people: messages, shared reminders, memories and calls, encrypted end-to-end. No account, no phone number.",
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
        ('When writing is not enough', 'One tap and <span class="serif-em">you hear each other.</span>',
         "The handset sits inside the chat: one tap and the call starts, peer-to-peer, straight from one phone to the other.",
         'The Tuijo voice call screen with duration and connection quality.'),
        ('Getting started', 'It starts with <span class="serif-em">a QR code.</span>',
         "Each of you shows their code and scans the other's. No email, no phone number, no password: from then on it is just the two of you.",
         'The Tuijo pairing screen with the QR code.'),
    ],
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
        ("I lost my phone, or I bought a new one. Can I get the chat back?", "Yes. On the new phone open Settings → Recover messages and choose where from: your partner's phone, or your own old phone. The new phone shows a QR code valid for ten minutes, the other one scans it from Settings → Help your partner (or Transfer), and the certificate arrives encrypted for that device only: the chat rebuilds itself."),
        ("How do I delete messages?", "Settings → Delete Messages, at three levels: from this phone only, from your partner's phone only, or from both phones and the server as well. The first two leave the chat on the server, so pairing again brings it back; the last one cannot be undone."),
    ],
    cta='Download it and pair your phones.',
    foot_privacy='Privacy', foot_support='Support', foot_tag='tu i jo — you and me',
    reels={2: ["The Tuijo gallery with photos gathered by month.", "The tab with the links saved in the chat, with title and domain.", "The tab with the shared documents, with size and date."], 3: ["The Tuijo chat with the handset button next to the menu.", "A finger tapping the handset inside the chat.", "The Tuijo voice call screen."]},
    scene=dict(steps=('One scans', 'The other scans', 'You are in the chat'), alt_qr="The phone showing its own QR code.", alt_scan="The Tuijo scanner framing the other person's phone.", alt_lock="The other phone's QR code in focus inside the scanner.", alt_done="The step completed, with the app's confirmation.", alt_chat="The chat open on the first phone, once paired.", alt_chat2="The same chat seen from the second phone, with the message the other person is typing."),
    hero_alt='Two phones side by side: the Tuijo chat and the shared reminders calendar.',
)

T['es'] = dict(
    lang='es', title='Tuijo — Para dos. El chat privado cifrado de extremo a extremo',
    desc="Tuijo es el chat para dos personas: mensajes, recordatorios compartidos, recuerdos y llamadas, cifrados de extremo a extremo. Sin cuenta y sin número de teléfono.",
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
        ('Cuando escribir no basta', 'Un toque y <span class="serif-em">os oís.</span>',
         "El teléfono está dentro del chat: un toque y sale la llamada, peer-to-peer, directa de un móvil al otro.",
         'La pantalla de llamada de voz de Tuijo con duración y calidad de conexión.'),
        ('Primer inicio', 'Se empieza con <span class="serif-em">un QR.</span>',
         "Cada uno muestra su código y escanea el del otro. Sin correo, sin número de teléfono, sin contraseña: a partir de ahí estáis solo vosotros dos.",
         'La pantalla de emparejamiento de Tuijo con el código QR.'),
    ],
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
        ("He perdido el móvil, o tengo uno nuevo. ¿Recupero el chat?", "Sí. En el móvil nuevo abre Ajustes → Recuperar los mensajes y elige de dónde: del móvil de tu pareja o de tu móvil antiguo. El nuevo muestra un QR válido diez minutos, el otro lo escanea desde Ajustes → Ayudar a tu pareja (o Transferir), y el certificado llega cifrado solo para ese dispositivo: el chat se recompone solo."),
        ("¿Cómo se borran los mensajes?", "En Ajustes → Eliminar mensajes, con tres niveles: solo de este móvil, solo del móvil de tu pareja, o de los dos y también del servidor. Los dos primeros dejan el chat en el servidor, así que al volver a emparejaros reaparece; el último es irreversible."),
    ],
    cta='Descargadla y emparejad los móviles.',
    foot_privacy='Privacidad', foot_support='Soporte', foot_tag='tu i jo — tú y yo',
    reels={2: ["La galería de Tuijo con las fotos reunidas por mes.", "La pestaña de los enlaces guardados en el chat, con título y dominio.", "La pestaña de los documentos compartidos, con peso y fecha."], 3: ["El chat de Tuijo con el botón de llamada junto al menú.", "Un dedo tocando el botón de llamada dentro del chat.", "La pantalla de llamada de voz de Tuijo."]},
    scene=dict(steps=('Uno escanea', 'El otro escanea', 'Estáis en el chat'), alt_qr="El móvil que muestra su propio código QR.", alt_scan="El escáner de Tuijo enfocando el móvil de la otra persona.", alt_lock="El código QR del otro móvil enfocado dentro del escáner.", alt_done="El paso completado, con la confirmación de la app.", alt_chat="El chat abierto en el primer móvil, una vez emparejados.", alt_chat2="El mismo chat visto desde el segundo móvil, con el mensaje que la otra persona está escribiendo."),
    hero_alt='Dos móviles uno al lado del otro: el chat de Tuijo y el calendario de recordatorios compartidos.',
)

T['ca'] = dict(
    lang='ca', title='Tuijo — Per a dos. El xat privat xifrat d\'extrem a extrem',
    desc="Tuijo és el xat per a dues persones: missatges, recordatoris compartits, records i trucades, xifrats d'extrem a extrem. Sense compte i sense número de telèfon.",
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
        ("Quan escriure no n'hi ha prou", 'Un toc i <span class="serif-em">us sentiu.</span>',
         "L'auricular és dins el xat: un toc i surt la trucada, peer-to-peer, directa d'un mòbil a l'altre.",
         'La pantalla de trucada de veu de Tuijo amb durada i qualitat de connexió.'),
        ('Primer inici', 'Es comença amb <span class="serif-em">un QR.</span>',
         "Cadascú mostra el seu codi i escaneja el de l'altre. Sense correu, sense número de telèfon, sense contrasenya: a partir d'aquí només hi sou vosaltres dos.",
         "La pantalla d'aparellament de Tuijo amb el codi QR."),
    ],
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
        ("He perdut el mòbil, o en tinc un de nou. Recupero el xat?", "Sí. Al mòbil nou obre Configuració → Recupera els missatges i tria d'on: del mòbil de la parella o del teu mòbil antic. El nou mostra un QR que val deu minuts, l'altre l'escaneja des de Configuració → Ajuda la teva parella (o Transfereix), i el certificat arriba xifrat només per a aquell dispositiu: el xat es recompon sol."),
        ("Com se suprimeixen els missatges?", "A Configuració → Suprimeix els missatges, amb tres nivells: només d'aquest mòbil, només del mòbil de la parella, o de tots dos i també del servidor. Els dos primers deixen el xat al servidor, així que en tornar-vos a aparellar torna; l'últim és irreversible."),
    ],
    cta='Baixeu-la i aparelleu els mòbils.',
    foot_privacy='Privacitat', foot_support='Suport', foot_tag='tu i jo',
    reels={2: ["La galeria de Tuijo amb les fotos recollides per mes.", "La pestanya dels enllaços desats al xat, amb títol i domini.", "La pestanya dels documents compartits, amb pes i data."], 3: ["El xat de Tuijo amb el botó de trucada al costat del menú.", "Un dit tocant el botó de trucada dins el xat.", "La pantalla de trucada de veu de Tuijo."]},
    scene=dict(steps=('Un escaneja', "L'altre escaneja", 'Sou al xat'), alt_qr="El mòbil que mostra el seu propi codi QR.", alt_scan="L'escàner de Tuijo enfocant el mòbil de l'altra persona.", alt_lock="El codi QR de l'altre mòbil enfocat dins l'escàner.", alt_done="El pas completat, amb la confirmació de l'app.", alt_chat="El xat obert al primer mòbil, un cop aparellats.", alt_chat2="El mateix xat vist des del segon mòbil, amb el missatge que l'altra persona està escrivint."),
    hero_alt="Dos mòbils l'un al costat de l'altre: el xat de Tuijo i el calendari de recordatoris compartits.",
)

SEC_IDS = ['chat', 'sicurezza', 'faq']   # ancore uguali in tutte le lingue

# Impianto di ciascuna delle sei sezioni prodotto, nell'ordine.
#   split      → testo a sinistra, immagine a destra
#   split rev  → immagine a sinistra, testo a destra
#   center     → immagine grande centrata, poggiata sul bordo inferiore
#   cardshot   → ritaglio largo dell'interfaccia, centrato sotto al testo
#   reel       → più schermate che si alternano da sole quando la sezione è in vista
#   scene      → i due telefoni che si abbinano mentre si scorre (sticky)
# 'sec' è l'indice nel blocco dei testi: l'ordine visivo si cambia qui, non lì.
# 'img' dice quale file usare: il telefono (0N) o il ritaglio a scheda (card-0N).
LAYOUT = [
    dict(sec=4, cls='scene',     shot=6, img='scene', dark=True),                     # abbinamento
    dict(sec=0, cls='split',     shot=1, img='phone', dark=False),                    # chat
    dict(sec=1, cls='split rev', shot=4, img='phone', dark=True),                     # promemoria
    dict(sec=2, cls='cardshot',  img='reel', card=True, shots=[(5, 2600), (11, 2600), (12, 2600)],
         dark=False),                                                                 # galleria: foto, link, documenti
    dict(sec=3, cls='split',     img='reel', shots=[(1, 1700), (13, 700), (2, 2600)],
         dark=True),                                                                  # chiamate: chat, tocco, chiamata
]


def img_size(path):
    """Larghezza e altezza di un PNG o di un WebP, lette dall'header.

    Serve a scrivere width/height nel markup (niente salti di layout mentre
    l'immagine carica) senza tirarsi dietro una libreria di immagini.
    """
    with open(path, 'rb') as fh:
        d = fh.read(32)
    if d[:8] == b'\x89PNG\r\n\x1a\n':
        return int.from_bytes(d[16:20], 'big'), int.from_bytes(d[20:24], 'big')
    if d[:4] == b'RIFF' and d[8:12] == b'WEBP':
        kind = d[12:16]
        if kind == b'VP8X':      # esteso (è il caso dei file con trasparenza)
            return (int.from_bytes(d[24:27], 'little') + 1,
                    int.from_bytes(d[27:30], 'little') + 1)
        if kind == b'VP8 ':      # lossy semplice
            return (int.from_bytes(d[26:28], 'little') & 0x3FFF,
                    int.from_bytes(d[28:30], 'little') & 0x3FFF)
        if kind == b'VP8L':      # lossless
            bits = int.from_bytes(d[21:25], 'little')
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    raise ValueError('formato non riconosciuto: %s' % path)

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

    hero_w, hero_h = img_size(os.path.join(OUT, 'assets', 'shots', code, f'pair-01-{code}.webp'))

    stages = []
    for i, lay in enumerate(LAYOUT, start=1):
        eyebrow, h2, lead, alt = t['sections'][lay['sec']]
        if lay['img'] == 'scene':
            sn = t['scene']
            steps = ''.join(f'<li>{x}</li>' for x in sn['steps'])
            # Il racconto in tre battute, tutto con schermate vere dell'app:
            #   1. il telefono di destra inquadra il codice di sinistra
            #   2. si scambiano i ruoli: sinistra inquadra destra
            #   3. abbinati, tutti e due nella stessa chat
            # --in e --out dicono a site.css quando ogni fotogramma entra ed esce.
            LEFT = [(6, -1, .42, sn['alt_qr']), (7, .40, .58, sn['alt_scan']),
                    (8, .56, .74, sn['alt_lock']), (9, .72, .86, sn['alt_done']),
                    (1, .84, 2, sn['alt_chat'])]
            RIGHT = [(7, -1, .18, sn['alt_scan']), (8, .16, .36, sn['alt_lock']),
                     (9, .34, .86, sn['alt_done']), (10, .84, 2, sn['alt_chat2'])]

            def frames(spec):
                out = []
                for shot, fin, fout, alt_txt in spec:
                    w, h = img_size(os.path.join(OUT, 'assets', 'shots', code, f'{shot:02d}-{code}.webp'))
                    out.append(
                        f'\n            <img class="fr" style="--in:{fin};--out:{fout}" '
                        f'src="assets/shots/{code}/{shot:02d}-{code}.webp" width="{w}" height="{h}" '
                        f'loading="lazy" alt="{alt_txt}">')
                return ''.join(out)

            stages.append(f"""
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
          <span class="beam beam-1" style="--in:.04;--out:.36"></span>
          <span class="beam beam-2" style="--in:.44;--out:.74"></span>
          <span class="ph ph-l">{frames(LEFT)}
            <span class="flash" style="--in:.18;--out:.34"></span>
          </span>
          <span class="ph ph-r">{frames(RIGHT)}
            <span class="flash" style="--in:.56;--out:.74"></span>
          </span>
          <span class="scene-link"></span>
        </div>
      </div>
    </div>
  </div>
</section>""")
            continue
        if lay['img'] == 'reel':
            pre = 'card-' if lay.get('card') else ''
            alts = t['reels'][lay['sec']]
            imgs = []
            for n, (shot, hold) in enumerate(lay['shots']):
                name = f'{pre}{shot:02d}-{code}.webp'
                w, h = img_size(os.path.join(OUT, 'assets', 'shots', code, name))
                imgs.append(
                    f'\n        <img class="fr{" on" if n == 0 else ""}" data-hold="{hold}" '
                    f'src="assets/shots/{code}/{name}" width="{w}" height="{h}" '
                    f'loading="lazy" alt="{alts[n]}">')
            stages.append(f'''
<section class="stage {lay['cls']}{' dark' if lay['dark'] else ''}">
  <div class="wrap">
    <div class="copy">
      <span class="eyebrow reveal">{eyebrow}</span>
      <h2 class="reveal">{h2}</h2>
      <p class="lead reveal d1">{lead}</p>
    </div>
    <div class="shot reel reveal d1" data-reel>{''.join(imgs)}
    </div>
  </div>
</section>''')
            continue
        card = lay['img'] == 'card'
        name = f"{'card-' if card else ''}{lay['shot']:02d}-{code}.webp"
        w, h = img_size(os.path.join(OUT, 'assets', 'shots', code, name))
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
      <img src="assets/shots/{code}/pair-01-{code}.webp" width="{hero_w}" height="{hero_h}" data-move="16" alt="{t['hero_alt']}" fetchpriority="high">
    </div>
  </div>
</header>
{''.join(stages)}

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
