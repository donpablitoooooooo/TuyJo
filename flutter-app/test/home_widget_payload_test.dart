import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import 'package:private_messaging/models/message.dart';
import 'package:private_messaging/services/home_widget_service.dart';

Message todo(
  String id, {
  required DateTime due,
  int? alertHours,
  DateTime? rangeEnd,
  String text = 'Todo',
}) {
  return Message(id: id, senderId: 'partner', timestamp: DateTime(2026, 10, 1))
    ..messageType = 'todo'
    ..decryptedContent = text
    ..dueDate = due
    ..alertHours = alertHours
    ..rangeEnd = rangeEnd
    ..isReminder = false;
}

void main() {
  late AppLocalizations l10n;
  // Giovedì 8 ottobre 2026, 21:00
  final now = DateTime(2026, 10, 8, 21);

  setUpAll(() async {
    await initializeDateFormatting('it');
    l10n = lookupAppLocalizations(const Locale('it'));
  });

  List<Map<String, dynamic>> build(List<Message> todos) =>
      (buildWidgetPayload(todos: todos, now: now, l10n: l10n, locale: 'it')['todos'] as List)
          .cast<Map<String, dynamic>>();

  test('con anticipo compare dall\'avviso e sparisce alla scadenza', () {
    final due = DateTime(2026, 10, 10, 20); // sabato 20:00
    final item = build([todo('a', due: due, alertHours: 48)]).single;

    expect(item['start'], DateTime(2026, 10, 8, 20).millisecondsSinceEpoch);
    expect(item['end'], due.millisecondsSinceEpoch);
    expect(item['alert'], '2g');
    expect(item['labels'], {
      '2026-10-08': 'Sabato 20:00',
      '2026-10-09': 'Domani 20:00',
      '2026-10-10': 'Oggi 20:00',
    });
  });

  test('senza anticipo compare dall\'inizio del giorno di scadenza', () {
    final item = build([todo('b', due: DateTime(2026, 10, 12, 9, 30))]).single;
    expect(item['start'], DateTime(2026, 10, 12).millisecondsSinceEpoch);
    expect(item.containsKey('alert'), isFalse);
  });

  test('un todo già scaduto non è nel widget', () {
    expect(build([todo('c', due: DateTime(2026, 10, 8, 20, 59))]), isEmpty);
  });

  test('un todo su più giorni resta fino alla fine dell\'ultimo giorno', () {
    final item = build([
      todo('d', due: DateTime(2026, 10, 5, 10), rangeEnd: DateTime(2026, 10, 9)),
    ]).single;
    expect(item['end'], DateTime(2026, 10, 10).millisecondsSinceEpoch);
    expect(item['label'], 'dal 5 al 9 ottobre');
    expect(item.containsKey('labels'), isFalse);
  });

  test('i todo sono ordinati per scadenza', () {
    final items = build([
      todo('late', due: DateTime(2026, 10, 20, 8)),
      todo('soon', due: DateTime(2026, 10, 9, 8)),
    ]);
    expect(items.map((i) => i['id']), ['soon', 'late']);
  });

  test('le frasi arrivano nella lingua del telefono', () {
    final strings = buildWidgetPayload(todos: const [], now: now, l10n: l10n, locale: 'it')['strings'] as Map;
    expect(strings['unreadOther'], '%d messaggi nuovi');
    expect(strings['partner'], 'Il mio amore');
  });
}
