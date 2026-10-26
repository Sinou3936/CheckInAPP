import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/ui/attendance_labels.dart';

/// 과거 날짜에서 이어진 방문 구역의 제목.
const _previousSectionTitle = '이전 날짜에서 이어진 방문';

/// 카운터 화면의 실시간 현황. 등원 QR 과 하원 QR 을 라벨과 함께 보여주고, 지금 체류 중인 사람과
/// 보정이 필요한 미하원 기록을 보여준다.
///
/// 요약 숫자는 오늘 행만 센다. 과거 날짜에서 이어진 방문(자정을 넘긴 체류·하원·미하원)은
/// 목록 아래 구역에 따로 보여, "오늘 등원 N" 이 과거 방문에 오염되지 않게 한다.
class DashboardScreen extends StatefulWidget {
  final CheckInAppController controller;
  final AttendanceRepository attendanceRepository;
  final MemberRepository memberRepository;

  /// 오늘 현황을 다시 읽는 간격. 테스트는 타이머가 끼어들지 않도록 길게 준다.
  final Duration refreshInterval;

  /// 현재 시각. 테스트가 자정 전후 같은 시각을 고정하려고 주입한다.
  final DateTime Function() clock;

  /// 체크 완료 배너를 보여주는 시간.
  final Duration bannerDuration;

  const DashboardScreen({
    super.key,
    required this.controller,
    required this.attendanceRepository,
    required this.memberRepository,
    this.refreshInterval = const Duration(seconds: 5),
    this.clock = DateTime.now,
    this.bannerDuration = const Duration(seconds: 5),
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<_DashboardRow> _rows = const [];

  /// 첫 로드가 끝나기 전에는 요약을 그리지 않는다 — 아직 읽지 않은 0 을 보여주면 안 된다.
  bool _loaded = false;

  Timer? _timer;

  /// 방금 학생 폰에서 기록된 체크. 카운터 앞의 학생이 "찍혔다"를 눈으로 확인하는 용도다.
  CheckInEvent? _banner;
  Timer? _bannerTimer;
  StreamSubscription<CheckInEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
    // 서버와 같은 프로세스라 컨트롤러가 든 서버의 통로를 그대로 듣는다.
    _eventSubscription = widget.controller.server.checkInEventBus.events.listen(
      _onCheckInEvent,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerTimer?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _onCheckInEvent(CheckInEvent event) {
    if (!mounted) return;
    setState(() => _banner = event);
    // 다음 사람이 연달아 찍으면 타이머를 새로 걸어 마지막 사람의 문구가 끝까지 보이게 한다.
    _bannerTimer?.cancel();
    _bannerTimer = Timer(widget.bannerDuration, () {
      if (mounted) setState(() => _banner = null);
    });
    // 목록도 곧바로 갱신해 방금 찍은 사람이 보이게 한다.
    _refresh();
  }

  Future<void> _refresh() async {
    final now = widget.clock();
    final today = AttendanceService.formatDate(now);
    final repo = widget.attendanceRepository;

    final todayRecords = await repo.getByDate(today);
    final openRecords = await repo.findOpenSessionsWithin(now: now);
    final sessionRecords = await repo.findSessionsWithin(now: now);
    final overdueRecords = await repo.findUnclosedSessions(now: now);
    final openIds = {for (final a in openRecords) a.id};
    final overdueIds = {for (final a in overdueRecords) a.id};

    // 여러 질의가 같은 행을 돌려줄 수 있으므로 id 로 한 번만 담는다. 오늘 행이 먼저 들어간다.
    final byId = <int, Attendance>{};
    for (final a in [
      ...todayRecords,
      ...openRecords,
      ...sessionRecords,
      ...overdueRecords,
    ]) {
      byId.putIfAbsent(a.id!, () => a);
    }

    final rows = <_DashboardRow>[];
    for (final record in byId.values) {
      final member = await widget.memberRepository.getById(record.memberId);
      rows.add(
        _DashboardRow(
          name: member?.name ?? '알 수 없는 회원',
          record: record,
          isToday: record.date == today,
          stage: _stageOf(record, openIds, overdueIds),
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실시간 현황')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ValueListenableBuilder<String?>(
                  valueListenable: widget.controller.checkInUrl,
                  builder: (_, url, _) => QrCard(
                    key: const Key('checkInCard'),
                    label: '등원',
                    url: url,
                  ),
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: widget.controller.checkOutUrl,
                  builder: (_, url, _) => QrCard(
                    key: const Key('checkOutCard'),
                    label: '하원',
                    url: url,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_banner != null) _CheckInBanner(event: _banner!),
            Expanded(child: _buildToday()),
          ],
        ),
      ),
    );
  }

  Widget _buildToday() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    final todayRows = _rows.where((r) => r.isToday).toList();
    final previousRows = _rows.where((r) => !r.isToday).toList();

    // 요약은 오늘 행만 센다. 등원 수에는 등원 시각이 있는 행만 넣는다 — 자동 결석은 등원하지 않은 사람이다.
    final checkedIn = todayRows
        .where((r) => r.record.checkInTime != null)
        .length;
    int countOf(_Stage stage) =>
        todayRows.where((r) => r.stage == stage).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '등원 $checkedIn · 하원 ${countOf(_Stage.checkedOut)} · '
          '$stayingLabel ${countOf(_Stage.staying)} · '
          '$overdueLabel ${countOf(_Stage.overdue)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final row in todayRows) _DashboardTile(row: row),
              if (previousRows.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text(
                    _previousSectionTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final row in previousRows) _DashboardTile(row: row),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "OOO 님 등원 완료" 를 크게 보여주는 확인 배너. 지각은 색으로도 구분한다.
class _CheckInBanner extends StatelessWidget {
  final CheckInEvent event;

  const _CheckInBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCheckOut = event.kind == QrKind.checkOut;
    final text =
        '${event.memberName} 님 ${isCheckOut ? '하원' : '등원'} 완료'
        '${event.isLate ? ' (지각)' : ''}';
    return Container(
      key: const Key('checkInBanner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: event.isLate
            ? scheme.tertiaryContainer
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}

/// 행의 현재 상태. 저장되는 값이 아니라 조회 결과로 정해지는 파생 값이다.
enum _Stage {
  /// 등원 시각이 없다 (자동 결석 행).
  notCheckedIn,

  /// 하원 시각이 있다.
  checkedOut,

  /// 등원 후 12시간 이내이고 하원하지 않았다.
  staying,

  /// 등원 후 12시간이 지나도록 하원하지 않았다. 보정 대상.
  overdue,
}

/// 12시간 판정은 여기서 다시 하지 않는다. [openIds] 와 [overdueIds] 는 저장소 조회가 준 행이다.
_Stage _stageOf(Attendance record, Set<int?> openIds, Set<int?> overdueIds) {
  if (record.checkInTime == null) return _Stage.notCheckedIn;
  if (record.checkOutTime != null) return _Stage.checkedOut;
  if (overdueIds.contains(record.id)) return _Stage.overdue;
  assert(openIds.contains(record.id), '열린 행은 체류 중 조회나 미하원 조회 중 하나에 있어야 한다');
  return _Stage.staying;
}

class _DashboardRow {
  final String name;
  final Attendance record;
  final bool isToday;
  final _Stage stage;

  const _DashboardRow({
    required this.name,
    required this.record,
    required this.isToday,
    required this.stage,
  });
}

/// 한 회원의 출결 한 줄. 보정 대상(미하원)은 배경색으로 눈에 띄게 한다.
class _DashboardTile extends StatelessWidget {
  final _DashboardRow row;

  const _DashboardTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final record = row.record;
    final scheme = Theme.of(context).colorScheme;
    final checkIn = record.checkInTime;
    return ListTile(
      tileColor: row.stage == _Stage.overdue ? scheme.errorContainer : null,
      title: Text(row.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 오늘이 아닌 행은 날짜를 함께 보여줘야 관리자가 어느 날의 방문인지 안다.
          if (!row.isToday) Text(record.date),
          Text(checkIn == null ? '등원 기록 없음' : '등원 ${_hhmm(checkIn)}'),
          switch (row.stage) {
            _Stage.checkedOut => Text('하원 ${_hhmm(record.checkOutTime!)}'),
            _Stage.staying => const Text(stayingLabel),
            _Stage.overdue => Text(
              overdueLabel,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            _Stage.notCheckedIn => const SizedBox.shrink(),
          },
        ],
      ),
      trailing: Text(attendanceStatusLabel(record.status)),
    );
  }
}

/// 저장 형식 ISO8601 에서 `HH:mm` 만 자른다. 저장값은 `toIso8601String()` 이 만든 지역 시각이다.
String _hhmm(String iso) => iso.substring(11, 16);

/// QR 한 장과 그 라벨. [url] 이 아직 없으면 같은 자리에 로딩 표시를 그린다.
///
/// qr_flutter 는 QR 의 data 를 private 으로 두므로, 테스트는 이 위젯이 받은 [url] 을 본다.
/// 이 위젯은 그 값을 그대로 `QrImageView(data:)` 에 넘긴다.
class QrCard extends StatelessWidget {
  final String label;
  final String? url;

  const QrCard({super.key, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (url == null)
          const SizedBox(
            width: 200,
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          )
        else
          QrImageView(data: url, size: 200),
      ],
    );
  }
}
