import 'package:flutter/material.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/repositories/class_repository.dart';

/// DateTime.weekday 순서(1=월 … 7=일)와 맞춘다.
const _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];

const _nameError = '반 이름을 입력하세요';
const _timeError = '시작 시간을 HH:mm 형식으로 입력하세요 (예: 15:00)';
const _daysError = '운영 요일을 하나 이상 고르세요';

/// 시작 시간은 `HH:mm` 두 자리씩이어야 한다. `startDateTimeFor` 가 `:` 로 쪼개 `int.parse`
/// 하므로, 여기서 막지 않으면 결석 처리처럼 나중에 다른 곳에서 터진다.
final _startTimePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// 운영 요일을 `월·수·금` 처럼 월→일 순서로 보여준다.
String _daysLabel(Set<int> days) {
  if (days.isEmpty) return '없음';
  final sorted = days.toList()..sort();
  return sorted.map((d) => _dayLabels[d - 1]).join('·');
}

class ClassManagementScreen extends StatefulWidget {
  final ClassRepository classRepository;

  const ClassManagementScreen({super.key, required this.classRepository});

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  List<ClassModel> _classes = const [];

  /// 첫 로드가 끝나기 전에는 빈 안내 대신 로딩 표시를 그린다.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final classes = await widget.classRepository.getAll();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _loaded = true;
    });
  }

  Future<void> _openForm({ClassModel? existing}) async {
    final result = await showDialog<ClassModel>(
      context: context,
      builder: (_) => _ClassFormDialog(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await widget.classRepository.insert(result);
    } else {
      await widget.classRepository.update(result);
    }
    await _reload();
  }

  Future<void> _confirmDelete(ClassModel classModel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('반 삭제'),
        content: Text(
          '${classModel.name} 반을 삭제합니다. 이 반에 속한 회원은 삭제되지 않고 '
          '반 지정만 해제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.classRepository.delete(classModel.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('반 관리')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
          ? const Center(child: Text('등록된 반이 없습니다.'))
          : ListView(
              children: [
                for (final c in _classes)
                  ListTile(
                    title: Text(c.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('시작 시간: ${c.startTime}'),
                        Text('운영 요일: ${_daysLabel(c.operatingDays)}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '수정',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openForm(existing: c),
                        ),
                        IconButton(
                          tooltip: '삭제',
                          icon: const Icon(Icons.delete),
                          onPressed: () => _confirmDelete(c),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '반 추가',
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 반 추가·수정 양식. 저장하면 완성된 [ClassModel] 을 돌려주고, 쓰기는 호출한 화면이 한다.
class _ClassFormDialog extends StatefulWidget {
  final ClassModel? existing;

  const _ClassFormDialog({required this.existing});

  @override
  State<_ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<_ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _daysKey = GlobalKey<FormFieldState<Set<int>>>();
  late final TextEditingController _nameController;
  late final TextEditingController _timeController;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _timeController = TextEditingController(text: existing?.startTime ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ClassModel(
        id: widget.existing?.id,
        name: _nameController.text.trim(),
        startTime: _timeController.text.trim(),
        operatingDays: Set<int>.of(_daysKey.currentState!.value ?? const {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingDays = widget.existing?.operatingDays ?? const <int>{};
    return AlertDialog(
      title: Text(widget.existing == null ? '반 추가' : '반 수정'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('classNameField'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: '반 이름'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? _nameError : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('classTimeField'),
                controller: _timeController,
                decoration: const InputDecoration(
                  labelText: '시작 시간',
                  helperText: 'HH:mm 형식 (예: 15:00)',
                ),
                validator: (value) =>
                    _startTimePattern.hasMatch((value ?? '').trim())
                    ? null
                    : _timeError,
              ),
              const SizedBox(height: 12),
              FormField<Set<int>>(
                key: _daysKey,
                initialValue: Set<int>.of(existingDays),
                // 요일을 고르는 즉시 오류 문구를 지우고 다시 검사한다.
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) =>
                    (value == null || value.isEmpty) ? _daysError : null,
                builder: (field) {
                  final days = field.value ?? const <int>{};
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '운영 요일',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (var d = 1; d <= 7; d++)
                            FilterChip(
                              label: Text(_dayLabels[d - 1]),
                              selected: days.contains(d),
                              onSelected: (on) {
                                final next = Set<int>.of(days);
                                if (on) {
                                  next.add(d);
                                } else {
                                  next.remove(d);
                                }
                                field.didChange(next);
                              },
                            ),
                        ],
                      ),
                      if (field.hasError)
                        Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}
