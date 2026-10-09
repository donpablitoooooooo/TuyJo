import 'package:intl/intl.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';

/// Etichette di data dei todo, condivise tra chat e widget.
///
/// Sono funzioni pure: `now` è un parametro, così il widget può calcolare in
/// anticipo come apparirà la data nei giorni successivi.

/// Data colloquiale (Oggi, Ieri, Domani, giorno della settimana, "9 ottobre"),
/// con l'ora se [includeTime].
String formatTodoDate(
  AppLocalizations l10n,
  String locale,
  DateTime date, {
  DateTime? now,
  bool includeTime = true,
}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));
  final messageDate = DateTime(date.year, date.month, date.day);

  String dateLabel;
  if (messageDate == today) {
    dateLabel = l10n.dateSeparatorToday;
  } else if (messageDate == yesterday) {
    dateLabel = l10n.dateSeparatorYesterday;
  } else if (messageDate == tomorrow) {
    dateLabel = l10n.dateSeparatorTomorrow;
  } else {
    final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
    final endOfWeek = today.add(Duration(days: 7 - (today.weekday % 7)));

    if (messageDate.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
        messageDate.isBefore(endOfWeek.add(const Duration(days: 1)))) {
      dateLabel = _weekdayName(l10n, messageDate.weekday) ?? DateFormat('d MMMM', locale).format(date);
    } else {
      // Data senza anno per date oltre la settimana
      dateLabel = DateFormat('d MMMM', locale).format(date);
    }
  }

  if (includeTime) {
    return '$dateLabel ${DateFormat('HH:mm').format(date)}';
  }
  return dateLabel;
}

/// Intervallo di date:
/// - stesso mese: "dal 25 al 31 gennaio"
/// - mesi consecutivi: "dal 25 dicembre al 3"
/// - distanza maggiore: "dal 25 dicembre al 3 febbraio"
String formatTodoDateRange(AppLocalizations l10n, String locale, DateTime start, DateTime end) {
  final monthsDiff = (end.year - start.year) * 12 + (end.month - start.month);

  if (monthsDiff == 0) {
    final startDay = DateFormat('d', locale).format(start);
    final endDay = DateFormat('d', locale).format(end);
    final month = DateFormat('MMMM', locale).format(start);
    return '${l10n.dateRangeFrom} $startDay ${l10n.dateRangeTo} $endDay $month';
  } else if (monthsDiff == 1) {
    final startFormatted = DateFormat('d MMMM', locale).format(start);
    final endDay = DateFormat('d', locale).format(end);
    return '${l10n.dateRangeFrom} $startFormatted ${l10n.dateRangeTo} $endDay';
  } else {
    final startFormatted = DateFormat('d MMMM', locale).format(start);
    final endFormatted = DateFormat('d MMMM', locale).format(end);
    return '${l10n.dateRangeFrom} $startFormatted ${l10n.dateRangeTo} $endFormatted';
  }
}

/// Anticipo dell'avviso in forma breve ("2h", "1g").
String formatAlertShort(AppLocalizations l10n, int hours) {
  if (hours >= 24) return l10n.alertShortDays(hours ~/ 24);
  return l10n.alertShortHours(hours);
}

String? _weekdayName(AppLocalizations l10n, int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return l10n.dateSeparatorMonday;
    case DateTime.tuesday:
      return l10n.dateSeparatorTuesday;
    case DateTime.wednesday:
      return l10n.dateSeparatorWednesday;
    case DateTime.thursday:
      return l10n.dateSeparatorThursday;
    case DateTime.friday:
      return l10n.dateSeparatorFriday;
    case DateTime.saturday:
      return l10n.dateSeparatorSaturday;
    case DateTime.sunday:
      return l10n.dateSeparatorSunday;
  }
  return null;
}
