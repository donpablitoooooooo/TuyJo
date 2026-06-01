import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Scheda di creazione todo in stile Apple (campi essenziali del nostro model).
///
/// Restituisce, via [Navigator.pop], una mappa:
///   { 'title': String, 'start': DateTime, 'end': DateTime?, 'alertHours': int? }
/// oppure `null` se l'utente annulla. Il chiamante (ChatScreen) usa questi dati
/// con il percorso di invio esistente (cifratura E2E + Firestore).
class TodoCreationSheet extends StatefulWidget {
  final DateTime initialDay;
  final String initialTitle;
  final int attachmentCount;
  const TodoCreationSheet({
    super.key,
    required this.initialDay,
    this.initialTitle = '',
    this.attachmentCount = 0,
  });

  @override
  State<TodoCreationSheet> createState() => _TodoCreationSheetState();
}

class _TodoCreationSheetState extends State<TodoCreationSheet> {
  static const Color _teal = Color(0xFF3BA8B0);

  final TextEditingController _titleController = TextEditingController();
  late DateTime _start;
  bool _hasEnd = false;
  late DateTime _end;
  int? _alertHours = 2;

  static const List<(String, int?)> _alertOptions = [
    ('Nessuno', null),
    ('1 ora', 1),
    ('2 ore', 2),
    ('1 giorno', 24),
    ('1 settimana', 168),
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.initialDay;
    _start = DateTime(d.year, d.month, d.day, 10, 0);
    _end = _start.add(const Duration(hours: 1));
    _titleController.text = widget.initialTitle;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      DateFormat('EEE d MMM yyyy', 'it').format(d);
  String _fmtTime(DateTime d) => DateFormat('HH:mm').format(d);

  Future<void> _pickDate({required bool isEnd}) async {
    final base = isEnd ? _end : _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    setState(() {
      final t = isEnd ? _end : _start;
      final updated = DateTime(picked.year, picked.month, picked.day, t.hour, t.minute);
      if (isEnd) {
        _end = updated;
      } else {
        _start = updated;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickTime({required bool isEnd}) async {
    final base = isEnd ? _end : _start;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null) return;
    setState(() {
      final t = isEnd ? _end : _start;
      final updated = DateTime(t.year, t.month, t.day, picked.hour, picked.minute);
      if (isEnd) {
        _end = updated;
      } else {
        _start = updated;
      }
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un titolo')),
      );
      return;
    }
    Navigator.pop(context, {
      'title': title,
      'start': _start,
      'end': _hasEnd ? _end : null,
      'alertHours': _alertHours,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F2F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                _buildCard([
                  TextField(
                    controller: _titleController,
                    autofocus: widget.initialTitle.isEmpty,
                    decoration: const InputDecoration(
                      hintText: 'Nome todo',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 18),
                  ),
                  if (widget.attachmentCount > 0) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_file, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            widget.attachmentCount == 1
                                ? '1 allegato'
                                : '${widget.attachmentCount} allegati',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ]),
                _buildCard([
                  _buildDateTimeRow('Inizio', _start, isEnd: false),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: _teal,
                    title: const Text('Imposta fine'),
                    value: _hasEnd,
                    onChanged: (v) => setState(() => _hasEnd = v),
                  ),
                  if (_hasEnd) ...[
                    const Divider(height: 1),
                    _buildDateTimeRow('Fine', _end, isEnd: true),
                  ],
                ]),
                _buildCard([
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Avviso',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: _alertOptions.map((opt) {
                      final selected = _alertHours == opt.$2;
                      return ChoiceChip(
                        label: Text(opt.$1),
                        selected: selected,
                        selectedColor: _teal.withValues(alpha: 0.2),
                        onSelected: (_) => setState(() => _alertHours = opt.$2),
                      );
                    }).toList(),
                  ),
                ]),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          const Spacer(),
          const Text('Nuovo todo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          TextButton(
            onPressed: _save,
            child: const Text('Salva',
                style: TextStyle(color: _teal, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildDateTimeRow(String label, DateTime value, {required bool isEnd}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          _pill(_fmtDate(value), () => _pickDate(isEnd: isEnd)),
          const SizedBox(width: 8),
          _pill(_fmtTime(value), () => _pickTime(isEnd: isEnd)),
        ],
      ),
    );
  }

  Widget _pill(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFE9E9EF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
