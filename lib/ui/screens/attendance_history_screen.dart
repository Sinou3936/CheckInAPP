import 'package:flutter/material.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/ui/attendance_labels.dart';

const _timeError = '시각을 HH:mm 형식으로 입력하세요 (예: 09:00)';
const _orderError = '등원 시각 없이 하원 시각을 넣을 수 없습니다';

/// 비우거나 `HH:mm` 두 자리씩인 시각만 받는다. `DateTime.parse` 전에 막아야 저장된 값이 깨지지 않는다.
final _timePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

String _two(int n) => n.toString().padLeft(2, '0');

String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// `date`(YYYY-MM-DD) 날짜의 [hhmm] 시각. 날짜 문자열은 로컬 자정으로 읽힌다.
DateTime _atDay(String date, String hhmm) {
  final day = DateTime.parse(date);
  final parts = hhmm.split(':');
  return DateTime(
    day.year,
    day.month,
    day.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
}

/// 하원 시각을 저장용 ISO8601 로 만든다. 하원이 등원보다 이르면 자정을 넘긴 방문으로 보고 다음 날로 넘긴다.
/// 등원 시각이 없는 하원은 검증 단계에서 이미 걸러져 여기 오지 않는다.
String _checkOutIso(String date, String checkIn, String checkOut) {
  final inAt = _atDay(date, checkIn);
  var outAt = _atDay(date, checkOut);
  if (outAt.isBefore(inAt)) {
    outAt = DateTime(
      outAt.year,
      outAt.month,
      outAt.day + 1,
      outAt.hour,
      outAt.minute,
    );
  }
  return outAt.toIso8601String();
}

/// 목록의 "등원 09:00 · 하원 18:00" 한 줄. 하원이 행 날짜 다음 날이면 그 사실을 드러낸다.
String _timeLine(Attendance a) {
  final checkIn = DateTime.parse(a.checkInTime!);
  final String checkOutText;
  if (a.checkOutTime == null) {
    checkOutText = '하원 없음';
  } else {
    final checkOut = DateTime.parse(a.checkOutTime!);
    final rowDay = DateTime.parse(a.date);
    final nextDay = DateTime(
      checkOut.year,
      checkOut.month,
      checkOut.day,
    ).isAfter(rowDay);
    checkOutText = '하원 ${_hhmm(checkOut)}${nextDay ? ' (다음 날)' : ''}';
  }
  return '등원 ${_hhmm(checkIn)} · $checkOutText';
}

/// 한 회원의 기록 스냅샷. 어느 회원의 것인지 함께 들고 있어야 회원을 바꾸는 사이의 옛 값을 가리지 않는다.
class _History {
  final int memberId;
  final List<Attendance> rows;

  /// 12시간 이내에 아직 하원하지 않은 기록의 id ("체류 중").
  final Set<int> stayingIds;

  /// 12시간이 지나도록 하원하지 않은 기록의 id ("미하원", 보정 대상).
  final Set<int> overdueIds;

  const _History({
    required this.memberId,
    required this.rows,
    required this.stayingIds,
    required this.overdueIds,
  });
}

class AttendanceHistoryScreen extends StatefulWidget {
  final MemberRepository memberRepository;
  final AttendanceRepository attendanceRepository;

  const AttendanceHistoryScreen({
    super.key,
    required this.memberRepository,
    required this.attendanceRepository,
  });

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  List<Member> _members = const [];

  /// 첫 로드가 끝나기 전에는 빈 안내 대신 로딩 표시를 그린다.
  bool _loaded = false;

  /// 사용자가 고른 회원. 목록에 없으면 선택이 없는 것으로 본다([_effectiveMemberId]).
  int? _memberId;

  /// 사용자가 고른 달(YYYY-MM). 기록에 없으면 가장 최근 달로 본다.
  String? _month;

  _History? _history;

  @override
  void initState() {
    super.initState();
    _reloadMembers();
  }

  Future<void> _reloadMembers() async {
    final members = await widget.memberRepository.getAll();
    if (!mounted) return;
    setState(() {
      _members = members;
      _loaded = true;
    });
  }

  int? get _effectiveMemberId =>
      _members.any((m) => m.id == _memberId) ? _memberId : null;

  Future<void> _selectMember(int id) async {
    setState(() {
      _memberId = id;
      _history = null;
      _month = null;
    });
    await _loadHistory();
  }

  /// 회원의 기록과, 지금 기준의 체류 중·미하원 판정을 함께 읽는다.
  /// 판정은 저장소 메서드가 하고, 여기서는 그 결과의 id 를 모을 뿐이다.
  Future<void> _loadHistory() async {
    final memberId = _effectiveMemberId;
    if (memberId == null) return;
    final now = DateTime.now();
    final rows = await widget.attendanceRepository.getHistoryForMember(
      memberId,
    );
    final staying = await widget.attendanceRepository.findOpenSessionsWithin(
      now: now,
    );
    final overdue = await widget.attendanceRepository.findUnclosedSessions(
      now: now,
    );
    if (!mounted || memberId != _effectiveMemberId) return;
    setState(() {
      _history = _History(
        memberId: memberId,
        rows: rows,
        stayingIds: staying.map((a) => a.id).whereType<int>().toSet(),
        overdueIds: overdue.map((a) => a.id).whereType<int>().toSet(),
      );
    });
  }

  Future<void> _openEdit(Attendance row) async {
    final updated = await showDialog<Attendance>(
      context: context,
      builder: (_) => _AttendanceEditDialog(existing: row),
    );
    if (updated == null || !mounted) return;
    // 보정은 학부모 알림을 내지 않는다. 이 화면은 알림 서비스를 받지 않는다.
    await widget.attendanceRepository.update(updated);
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final memberId = _effectiveMemberId;
    final history = (memberId != null && _history?.memberId == memberId)
        ? _history
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('출결 기록')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _members.isEmpty
          ? const Center(child: Text('등록된 회원이 없습니다.'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButton<int>(
                    key: const Key('memberDropdown'),
                    hint: const Text('회원을 선택하세요'),
                    value: memberId,
                    items: [
                      for (final m in _members)
                        DropdownMenuItem<int>(
                          value: m.id!,
                          child: Text(m.name),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) _selectMember(id);
                    },
                  ),
                ),
                Expanded(
                  child: memberId == null
                      ? const Center(child: Text('회원을 선택하면 출결 기록을 볼 수 있습니다.'))
                      : history == null
                      ? const Center(child: CircularProgressIndicator())
                      : _HistoryBody(
                          history: history,
                          month: _month,
                          onMonthChanged: (m) => setState(() => _month = m),
                          onEdit: _openEdit,
                        ),
                ),
              ],
            ),
    );
  }
}

/// 선택한 회원의 달 목록, 월별 집계, 행 목록. 달 목록은 기록에서 만들고 최근 달이 먼저 온다.
class _HistoryBody extends StatelessWidget {
  final _History history;
  final String? month;
  final ValueChanged<String?> onMonthChanged;
  final ValueChanged<Attendance> onEdit;

  const _HistoryBody({
    required this.history,
    required this.month,
    required this.onMonthChanged,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final months =
        history.rows.map((a) => a.date.substring(0, 7)).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    if (months.isEmpty) {
      return const Center(child: Text('출결 기록이 없습니다.'));
    }
    // 저장된 달 목록에 없는 선택은 가장 최근 달로 되돌린다. 드롭다운 value 가 items 와 어긋나면 assert 로 깨진다.
    final selected = months.contains(month) ? month! : months.first;
    final rows = history.rows
        .where((a) => a.date.startsWith(selected))
        .toList();

    final present = rows.where((a) => a.status == AttendanceStatus.present);
    final late = rows.where((a) => a.status == AttendanceStatus.late);
    final absent = rows.where((a) => a.status == AttendanceStatus.absent);
    final overdue = rows.where((a) => history.overdueIds.contains(a.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              DropdownButton<String>(
                key: const Key('monthDropdown'),
                value: selected,
                items: [
                  for (final m in months)
                    DropdownMenuItem<String>(value: m, child: Text(m)),
                ],
                onChanged: onMonthChanged,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '출석 ${present.length} · 지각 ${late.length} · '
                  '결석 ${absent.length} · 미하원 ${overdue.length}',
                  key: const Key('summaryText'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final a in rows)
                _HistoryTile(
                  row: a,
                  staying: history.stayingIds.contains(a.id),
                  overdue: history.overdueIds.contains(a.id),
                  onEdit: () => onEdit(a),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Attendance row;
  final bool staying;
  final bool overdue;
  final VoidCallback onEdit;

  const _HistoryTile({
    required this.row,
    required this.staying,
    required this.overdue,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return ListTile(
      title: Text(row.date),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(attendanceStatusLabel(row.status)),
          // 자동 결석 행은 등원 기록이 없으므로 시각을 그리지 않는다.
          if (row.checkInTime != null) Text(_timeLine(row)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (staying) const Text(stayingLabel),
          if (overdue)
            Text(
              overdueLabel,
              style: TextStyle(color: errorColor, fontWeight: FontWeight.bold),
            ),
          IconButton(
            tooltip: '보정',
            icon: const Icon(Icons.edit),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// 출결 보정 양식. 기존 행에서 출발해 [Attendance] 를 전체로 만들어 돌려주고, 쓰기는 화면이 한다.
class _AttendanceEditDialog extends StatefulWidget {
  final Attendance existing;

  const _AttendanceEditDialog({required this.existing});

  @override
  State<_AttendanceEditDialog> createState() => _AttendanceEditDialogState();
}

class _AttendanceEditDialogState extends State<_AttendanceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late AttendanceStatus _status;
  late final TextEditingController _checkInController;
  late final TextEditingController _checkOutController;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _status = existing.status;
    _checkInController = TextEditingController(
      text: existing.checkInTime == null
          ? ''
          : _hhmm(DateTime.parse(existing.checkInTime!)),
    );
    _checkOutController = TextEditingController(
      text: existing.checkOutTime == null
          ? ''
          : _hhmm(DateTime.parse(existing.checkOutTime!)),
    );
  }

  @override
  void dispose() {
    _checkInController.dispose();
    _checkOutController.dispose();
    super.dispose();
  }

  String? _checkInValidator(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty || _timePattern.hasMatch(text) ? null : _timeError;
  }

  String? _checkOutValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!_timePattern.hasMatch(text)) return _timeError;
    if (_checkInController.text.trim().isEmpty) return _orderError;
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final checkIn = _checkInController.text.trim();
    final checkOut = _checkOutController.text.trim();
    Navigator.of(context).pop(
      Attendance(
        id: existing.id,
        memberId: existing.memberId,
        date: existing.date,
        status: _status,
        checkInTime: checkIn.isEmpty
            ? null
            : _atDay(existing.date, checkIn).toIso8601String(),
        checkOutTime: checkOut.isEmpty
            ? null
            : _checkOutIso(existing.date, checkIn, checkOut),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('출결 보정'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AttendanceStatus>(
                key: const Key('statusField'),
                initialValue: _status,
                decoration: const InputDecoration(labelText: '상태'),
                items: [
                  for (final s in AttendanceStatus.values)
                    DropdownMenuItem<AttendanceStatus>(
                      value: s,
                      child: Text(attendanceStatusLabel(s)),
                    ),
                ],
                onChanged: (s) {
                  if (s != null) setState(() => _status = s);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('checkInField'),
                controller: _checkInController,
                decoration: const InputDecoration(
                  labelText: '등원 시각',
                  helperText: 'HH:mm 형식, 비우면 등원 기록 없음',
                ),
                validator: _checkInValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('checkOutField'),
                controller: _checkOutController,
                decoration: const InputDecoration(
                  labelText: '하원 시각',
                  helperText: 'HH:mm 형식, 비우면 미하원',
                ),
                validator: _checkOutValidator,
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
