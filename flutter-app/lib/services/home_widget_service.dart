import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';

import '../models/message.dart';
import '../utils/todo_date_format.dart';
import 'chat_service.dart';

/// Dati del widget della schermata Home (iOS WidgetKit e Android AppWidget).
///
/// Il widget non decifra nulla: questo servizio gli scrive dati già pronti.
/// - `tuyjo_widget`: JSON con i todo (testo, finestra di visibilità, etichette
///   di data già calcolate giorno per giorno) e le frasi nella lingua del telefono.
/// - `tuyjo_unread`: numero dei messaggi non letti, come stringa. Lo scrive
///   anche il push (estensione notifiche su iOS, gestore in background su Android).
///
/// Regole decise per il widget:
/// - un todo compare dall'anticipo dell'avviso (o dall'inizio del giorno di
///   scadenza, se non ha avviso) e sparisce alla scadenza; un todo su più
///   giorni resta fino alla fine dell'ultimo giorno; completato o eliminato
///   sparisce subito;
/// - dei messaggi si mostra solo quanti sono, mai il testo.
class HomeWidgetService with WidgetsBindingObserver {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  static const String appGroupId = 'group.com.privatemessaging.tuyjo';
  static const String iOSKind = 'TuyJoWidget';
  static const String androidProvider = 'com.privatemessaging.private_messaging.TuyJoWidgetProvider';
  static const String payloadKey = 'tuyjo_widget';
  static const String unreadKey = 'tuyjo_unread';
  static const MethodChannel _channel = MethodChannel('com.privatemessaging.tuyjo/widget');

  /// Quanti todo al massimo vengono passati al widget.
  static const int maxTodos = 20;

  /// Per quanti giorni si calcolano in anticipo le etichette ("Domani", "venerdì").
  static const int labelDays = 14;

  /// Ogni quanto si rileggono i todo da Firestore se nulla è cambiato.
  static const Duration _todoRefreshInterval = Duration(minutes: 15);

  ChatService? _chat;
  Timer? _debounce;
  bool _started = false;
  List<Message> _todos = const [];
  String _todoSignature = '';
  DateTime? _lastTodoFetch;
  bool _refreshing = false;
  bool _refreshAgain = false;

  /// Chiamato quando l'utente tocca la cornetta del widget.
  VoidCallback? onCallRequested;

  static bool get _supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> start(ChatService chat) async {
    if (!_supported || _started) return;
    _started = true;
    _chat = chat;

    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(appGroupId);
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'actionAvailable') await _takePendingAction();
    });

    WidgetsBinding.instance.addObserver(this);
    chat.addListener(_onChatChanged);

    await _takePendingAction();
    scheduleRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _takePendingAction();
      scheduleRefresh();
    } else if (state == AppLifecycleState.paused) {
      // Ultimo aggiornamento prima che il sistema sospenda l'app
      refresh();
    }
  }

  void _onChatChanged() => scheduleRefresh();

  /// Aggiorna il widget dopo un attimo, raggruppando le modifiche ravvicinate.
  void scheduleRefresh() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), refresh);
  }

  Future<void> refresh() async {
    final chat = _chat;
    if (chat == null) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final now = DateTime.now();
      final myId = chat.myDeviceId;
      final hasChat = chat.currentFamilyChatId != null && myId != null;

      // I todo si rileggono da Firestore solo se in chat è cambiato qualcosa
      // che li riguarda, o se l'ultima lettura è vecchia.
      final signature = _signatureOf(chat.messages);
      final stale = _lastTodoFetch == null || now.difference(_lastTodoFetch!) > _todoRefreshInterval;
      if (!hasChat) {
        _todos = const [];
      } else if (signature != _todoSignature || stale) {
        try {
          _todos = await chat.fetchOpenTodosForWidget();
          _todoSignature = signature;
          _lastTodoFetch = now;
        } catch (e) {
          if (kDebugMode) print('⚠️ [WIDGET] Lettura todo fallita: $e');
        }
      }

      final unread = hasChat ? _unreadCount(chat.messages, myId, now) : 0;
      final payload = buildWidgetPayload(todos: _todos, now: now, l10n: _l10n, locale: _localeName);

      await HomeWidget.saveWidgetData<String>(payloadKey, jsonEncode(payload));
      await HomeWidget.saveWidgetData<String>(unreadKey, '$unread');
      await HomeWidget.updateWidget(iOSName: iOSKind, qualifiedAndroidName: androidProvider);
    } catch (e) {
      if (kDebugMode) print('⚠️ [WIDGET] Aggiornamento fallito: $e');
    } finally {
      _refreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        scheduleRefresh();
      }
    }
  }

  /// Push ricevuto con l'app in background (Android): aggiorna solo il numero.
  /// Gira nell'isolate del gestore FCM, senza ChatService.
  static Future<void> saveUnreadFromPush(Object? value) async {
    if (!_supported || value == null) return;
    final count = int.tryParse('$value');
    if (count == null) return;
    try {
      if (Platform.isIOS) await HomeWidget.setAppGroupId(appGroupId);
      await HomeWidget.saveWidgetData<String>(unreadKey, '$count');
      await HomeWidget.updateWidget(iOSName: iOSKind, qualifiedAndroidName: androidProvider);
    } catch (e) {
      if (kDebugMode) print('⚠️ [WIDGET] Aggiornamento da push fallito: $e');
    }
  }

  Future<void> _takePendingAction() async {
    try {
      final action = await _channel.invokeMethod<String>('takePendingAction');
      if (action == 'call') onCallRequested?.call();
    } on MissingPluginException {
      // Piattaforma senza il canale del widget
    } catch (e) {
      if (kDebugMode) print('⚠️ [WIDGET] Azione non letta: $e');
    }
  }

  /// Cambia quando compare, sparisce, si completa o si elimina un todo in memoria.
  String _signatureOf(List<Message> messages) {
    final buffer = StringBuffer();
    for (final m in messages) {
      if (m.messageType == 'todo' || m.messageType == 'todo_completed') {
        buffer
          ..write(m.id)
          ..write(m.action?.type ?? '')
          ..write(m.deleted == true ? 'd' : '')
          ..write(m.decryptedContent?.hashCode ?? 0)
          ..write(';');
      }
    }
    return buffer.toString();
  }

  /// Messaggi ricevuti e non letti, con lo stesso filtro della chat
  /// (niente completamenti, niente promemoria non ancora arrivati).
  int _unreadCount(List<Message> messages, String myId, DateTime now) {
    return messages.where((m) {
      if (m.senderId == myId) return false;
      if (m.read == true || m.deleted == true) return false;
      if (m.messageType == 'todo_completed') return false;
      if (m.timestamp.isAfter(now)) return false;
      return true;
    }).length;
  }

  /// Lingua del telefono, con inglese se non è tra quelle dell'app.
  static AppLocalizations get _l10n => lookupAppLocalizations(ui.Locale(_localeName));

  static String get _localeName {
    final sys = ui.PlatformDispatcher.instance.locale;
    final supported = AppLocalizations.supportedLocales.any((l) => l.languageCode == sys.languageCode);
    return supported ? sys.languageCode : 'en';
  }
}

/// Dati per il widget, calcolati a partire dai todo aperti.
///
/// Funzione pura (niente piattaforma), così le regole di visibilità si testano.
Map<String, dynamic> buildWidgetPayload({
  required List<Message> todos,
  required DateTime now,
  required AppLocalizations l10n,
  required String locale,
}) {
  final dayKey = DateFormat('yyyy-MM-dd');
  final today = DateTime(now.year, now.month, now.day);

  final items = <Map<String, dynamic>>[];
  final sorted = [...todos]..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  for (final todo in sorted) {
    final due = todo.dueDate!;
    final dueDay = DateTime(due.year, due.month, due.day);
    final alertHours = todo.alertHours;
    final hasAlert = alertHours != null && alertHours > 0;
    final rangeEnd = todo.rangeEnd;

    final start = hasAlert ? due.subtract(Duration(hours: alertHours)) : dueDay;
    final end =
        rangeEnd != null ? DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day).add(const Duration(days: 1)) : due;
    if (!end.isAfter(now)) continue;

    final item = <String, dynamic>{
      'id': todo.id,
      'text': todo.decryptedContent ?? '',
      'due': due.millisecondsSinceEpoch,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      if (hasAlert) 'alert': formatAlertShort(l10n, alertHours),
    };

    if (rangeEnd != null) {
      // L'intervallo non dipende dal giorno in cui lo si guarda
      item['label'] = formatTodoDateRange(l10n, locale, due, rangeEnd);
    } else {
      // "Domani 20:00" cambia ogni giorno: etichette pronte per ogni giorno
      // fino alla scadenza, così il widget è giusto anche con l'app chiusa.
      final labels = <String, String>{};
      final startDay = DateTime(start.year, start.month, start.day);
      var day = startDay.isAfter(today) ? startDay : today;
      for (var i = 0; i < HomeWidgetService.labelDays && !day.isAfter(dueDay); i++) {
        labels[dayKey.format(day)] = formatTodoDate(l10n, locale, due, now: day.add(const Duration(hours: 12)));
        day = DateTime(day.year, day.month, day.day + 1);
      }
      item['labels'] = labels;
      item['label'] = '${DateFormat('d MMMM', locale).format(due)} ${DateFormat('HH:mm').format(due)}';
    }

    items.add(item);
    if (items.length >= HomeWidgetService.maxTodos) break;
  }

  return {
    'v': 1,
    'generatedAt': now.millisecondsSinceEpoch,
    'strings': {
      'todo': l10n.widgetTodoTitle,
      'partner': l10n.widgetPartnerName,
      'unreadOne': l10n.widgetUnreadOne,
      'unreadOther': l10n.widgetUnreadOther,
      'allRead': l10n.widgetAllRead,
    },
    'todos': items,
  };
}
