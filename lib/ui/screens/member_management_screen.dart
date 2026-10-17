import 'package:flutter/material.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';

class MemberManagementScreen extends StatefulWidget {
  final MemberRepository memberRepository;
  final ClassRepository classRepository;

  const MemberManagementScreen({
    super.key,
    required this.memberRepository,
    required this.classRepository,
  });

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  List<Member> _members = const [];
  List<ClassModel> _classes = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final members = await widget.memberRepository.getAll();
    final classes = await widget.classRepository.getAll();
    if (!mounted) return;
    setState(() {
      _members = members;
      _classes = classes;
    });
  }

  Future<void> _openForm({Member? existing}) async {
    // 다이얼로그는 상태에 이미 있는 반 목록만 쓴다. 여기서 DB 를 읽지 않는다.
    final result = await showDialog<Member>(
      context: context,
      builder: (_) => _MemberFormDialog(existing: existing, classes: _classes),
    );
    if (result == null) return;
    if (existing == null) {
      await widget.memberRepository.insert(result);
    } else {
      await widget.memberRepository.update(result);
    }
    await _reload();
  }

  Future<void> _confirmDelete(Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 삭제'),
        content: Text('${member.name} 회원을 삭제합니다. 등록된 기기 바인딩도 함께 지워집니다.'),
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
    await widget.memberRepository.delete(member.id!);
    await _reload();
  }

  String _classNameOf(int? classId) {
    if (classId == null) return '반 없음';
    for (final c in _classes) {
      if (c.id == classId) return c.name;
    }
    return '반 없음';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      body: _members.isEmpty
          ? const Center(child: Text('등록된 회원이 없습니다.'))
          : ListView(
              children: [
                for (final m in _members)
                  ListTile(
                    title: Text(m.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('반: ${_classNameOf(m.classId)}'),
                        m.parentContact == null
                            ? Text(
                                '연락처 없음 — 기기 바인딩은 관리자 대행',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              )
                            : Text('학부모 연락처: ${m.parentContact}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '수정',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openForm(existing: m),
                        ),
                        IconButton(
                          tooltip: '삭제',
                          icon: const Icon(Icons.delete),
                          onPressed: () => _confirmDelete(m),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '회원 추가',
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 회원 추가·수정 양식. 저장하면 완성된 [Member] 를 돌려주고, 쓰기는 호출한 화면이 한다.
class _MemberFormDialog extends StatefulWidget {
  final Member? existing;
  final List<ClassModel> classes;

  const _MemberFormDialog({required this.existing, required this.classes});

  @override
  State<_MemberFormDialog> createState() => _MemberFormDialogState();
}

class _MemberFormDialogState extends State<_MemberFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late int? _classId;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _contactController = TextEditingController(
      text: existing?.parentContact ?? '',
    );
    _classId = existing?.classId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final contact = _contactController.text.trim();
    // 빈 문자열을 저장하면 뒷 4자리 확인이 빈 값과 비교되어 통과하므로 null 로 바꾼다.
    final member = Member(
      id: widget.existing?.id,
      name: _nameController.text.trim(),
      classId: _classId,
      parentContact: contact.isEmpty ? null : contact,
    );
    Navigator.of(context).pop(member);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '회원 추가' : '회원 수정'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('memberNameField'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: '이름'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? '이름을 입력하세요'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('memberContactField'),
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '학부모 연락처',
                  helperText: '비워 두면 관리자 대행으로 기기를 묶습니다',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                key: const Key('memberClassField'),
                initialValue: _classId,
                decoration: const InputDecoration(labelText: '반'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('반 없음'),
                  ),
                  for (final c in widget.classes)
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) => setState(() => _classId = value),
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
