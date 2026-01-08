import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/chat_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Map<DateTime, List<Message>> _todosByDate = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTodos();
  }

  /// Carica tutti i TODO e li raggruppa per data
  void _loadTodos() {
    final chatService = Provider.of<ChatService>(context, listen: false);
    _todosByDate.clear();

    for (final message in chatService.messages) {
      // Considera solo i TODO non completati
      if (message.messageType == 'todo' && message.dueDate != null) {
        // Verifica se è completato
        final isCompleted = chatService.messages.any((m) =>
            m.messageType == 'todo_completed' &&
            m.originalTodoId == message.id);

        if (!isCompleted) {
          // Normalizza la data (solo giorno, senza ora)
          final date = DateTime(
            message.dueDate!.year,
            message.dueDate!.month,
            message.dueDate!.day,
          );

          if (!_todosByDate.containsKey(date)) {
            _todosByDate[date] = [];
          }
          _todosByDate[date]!.add(message);
        }
      }
    }
  }

  /// Ritorna i TODO per una specifica data
  List<Message> _getTodosForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _todosByDate[normalizedDay] ?? [];
  }

  /// Completa un TODO
  Future<void> _completeTodo(String todoId) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    await chatService.completeTodo(todoId);

    // Ricarica i TODO
    setState(() {
      _loadTodos();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    // Ricarica i TODO quando cambia lo stato del chatService
    final chatService = Provider.of<ChatService>(context);
    _loadTodos();

    final todosForSelectedDay = _selectedDay != null
        ? _getTodosForDay(_selectedDay!)
        : <Message>[];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.calendarTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Calendario
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TableCalendar(
                  locale: locale,
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  eventLoader: _getTodosForDay,
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: const Color(0xFF667eea).withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: const BoxDecoration(
                      color: Color(0xFF667eea),
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: const BoxDecoration(
                      color: Color(0xFF764ba2),
                      shape: BoxShape.circle,
                    ),
                    markersAlignment: Alignment.bottomCenter,
                    markersMaxCount: 3,
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Lista TODO per il giorno selezionato
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Titolo lista
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_note,
                              color: const Color(0xFF667eea),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.calendarTodosForDate(
                                  DateFormat('d MMMM yyyy', locale).format(_selectedDay ?? DateTime.now()),
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF667eea),
                                ),
                              ),
                            ),
                            if (todosForSelectedDay.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF667eea),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${todosForSelectedDay.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Lista TODO
                      Expanded(
                        child: todosForSelectedDay.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.event_available,
                                      size: 64,
                                      color: Colors.grey[300],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      l10n.calendarNoTodos,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l10n.calendarNoTodosDescription,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: todosForSelectedDay.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final todo = todosForSelectedDay[index];
                                  final timeFormat = DateFormat('HH:mm');

                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF667eea).withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      leading: Icon(
                                        todo.isReminder == true
                                            ? Icons.notifications_outlined
                                            : Icons.event_outlined,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      title: Text(
                                        todo.decryptedContent ?? l10n.chatTodoDefault,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.access_time,
                                                size: 14,
                                                color: Colors.white70,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                timeFormat.format(todo.dueDate!),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              if (todo.rangeEnd != null) ...[
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.arrow_forward,
                                                  size: 14,
                                                  color: Colors.white70,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  DateFormat('d MMM', locale).format(todo.rangeEnd!),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                      trailing: IconButton(
                                        onPressed: () => _completeTodo(todo.id),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          color: Colors.white,
                                        ),
                                        tooltip: l10n.calendarMarkAsCompleted,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
