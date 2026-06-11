import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Calendario a scorrimento verticale continuo (stile Apple), senza frecce.
///
/// Mostra una lista verticale di mesi; ogni mese ha l'intestazione (nome + anno)
/// e una griglia di giorni con la settimana che inizia di lunedì. I giorni con
/// almeno un todo hanno un pallino sotto il numero. Il tap su un giorno chiama
/// [onDaySelected]. All'apertura scorre automaticamente al mese corrente.
class VerticalCalendar extends StatefulWidget {
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDaySelected;
  final bool Function(DateTime day) hasEvents;
  final int monthsBefore;
  final int monthsAfter;

  const VerticalCalendar({
    super.key,
    required this.selectedDay,
    required this.onDaySelected,
    required this.hasEvents,
    this.monthsBefore = 12,
    this.monthsAfter = 24,
  });

  @override
  State<VerticalCalendar> createState() => _VerticalCalendarState();
}

class _VerticalCalendarState extends State<VerticalCalendar> {
  static const double _rowHeight = 44;
  static const double _monthLabelHeight = 44;
  double get _monthBlockHeight => _monthLabelHeight + _rowHeight * 6;

  late final ScrollController _controller;
  late final DateTime _firstMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _firstMonth = DateTime(now.year, now.month - widget.monthsBefore);
    _controller = ScrollController(
      initialScrollOffset: widget.monthsBefore * _monthBlockHeight,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime _addMonths(DateTime base, int months) =>
      DateTime(base.year, base.month + months);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<String> _weekdayLabels(String locale) {
    final df = DateFormat.E(locale);
    // 2024-01-01 è un lunedì → genera Lun..Dom e prendi l'iniziale.
    final monday = DateTime(2024, 1, 1);
    return List.generate(7, (i) {
      final s = df.format(monday.add(Duration(days: i)));
      return s.isNotEmpty ? s[0].toUpperCase() : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final weekdays = _weekdayLabels(locale);

    return Column(
      children: [
        // Intestazione fissa giorni della settimana (L M M G V S D)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: weekdays
                .map((w) => Expanded(
                      child: Center(
                        child: Text(
                          w,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _controller,
            itemExtent: _monthBlockHeight,
            itemCount: widget.monthsBefore + widget.monthsAfter + 1,
            itemBuilder: (context, i) =>
                _buildMonth(_addMonths(_firstMonth, i), locale),
          ),
        ),
      ],
    );
  }

  Widget _buildMonth(DateTime month, String locale) {
    final monthLabel = _capitalize(DateFormat.yMMMM(locale).format(month));
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leadingBlanks = firstOfMonth.weekday - 1; // lunedì=1 → 0 vuoti
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();

    final weeks = <Widget>[];
    for (int row = 0; row < 6; row++) {
      final cells = <Widget>[];
      for (int col = 0; col < 7; col++) {
        final cellIndex = row * 7 + col;
        final dayNum = cellIndex - leadingBlanks + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
          cells.add(const Expanded(child: SizedBox()));
          continue;
        }
        final day = DateTime(month.year, month.month, dayNum);
        final isSelected =
            widget.selectedDay != null && _sameDay(day, widget.selectedDay!);
        final isToday = _sameDay(day, today);
        final hasEv = widget.hasEvents(day);
        cells.add(Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onDaySelected(day),
            child: Center(
              child: SizedBox(
                width: 38,
                height: 38,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Colors.white
                        : (isToday
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.transparent),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF145A60)
                              : Colors.white,
                          fontWeight: (isToday || isSelected)
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 15,
                        ),
                      ),
                      if (hasEv)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? const Color(0xFF145A60)
                                : Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
      }
      weeks.add(SizedBox(height: _rowHeight, child: Row(children: cells)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _monthLabelHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              monthLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        ...weeks,
      ],
    );
  }
}
