import 'package:flutter/material.dart';

class DefenseStudentSelector extends StatefulWidget {
  final Map<String, String> students;
  final Set<String> notifiedStudents;
  const DefenseStudentSelector({
    super.key,
    required this.students,
    required this.notifiedStudents,
  });

  @override
  State<DefenseStudentSelector> createState() => _DefenseStudentSelectorState();
}

class _DefenseStudentSelectorState extends State<DefenseStudentSelector> {
  final Map<String, String> _selected = {};
  bool _selectAll = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择答辩学生'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: const Text('全选',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              value: _selectAll,
              onChanged: (v) {
                setState(() {
                  _selectAll = v ?? false;
                  if (_selectAll) {
                    _selected.addAll(widget.students);
                  } else {
                    _selected.clear();
                  }
                });
              },
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.students.entries.map((e) {
                  final isNotified = widget.notifiedStudents.contains(e.key);
                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Text(e.value),
                        if (isNotified) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle,
                                    size: 12, color: Colors.green),
                                SizedBox(width: 2),
                                Text(
                                  '已通知',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(e.key, style: const TextStyle(fontSize: 11)),
                    value: _selected.containsKey(e.key),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected[e.key] = e.value;
                        } else {
                          _selected.remove(e.key);
                        }
                        _selectAll =
                            _selected.length == widget.students.length;
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text('确定 (${_selected.length})'),
        ),
      ],
    );
  }
}
