import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/ui/attendance_labels.dart';

/// 카운터 화면의 실시간 현황. 등원 QR 과 하원 QR 을 라벨과 함께 보여주고, 오늘 누가 안에
/// 있는지(등원했고 하원하지 않은 회원)를 보여준다.
class DashboardScreen extends StatefulWidget {
  final CheckInAppController controller;
  final AttendanceRepository attendanceRepository;
  final MemberRepository memberRepository;

  /// 오늘 현황을 다시 읽는 간격. 테스트는 타이머가 끼어들지 않도록 길게 준다.
  final Duration refreshInterval;

  const DashboardScreen({
    super.key,
    required this.controller,
    required this.attendanceRepository,
    required this.memberRepository,
    this.refreshInterval = const Duration(seconds: 5),
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<_TodayRow> _rows = const [];

  /// 첫 로드가 끝나기 전에는 요약을 그리지 않는다 — 아직 읽지 않은 0 을 보여주면 안 된다.
  bool _loaded = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final records = await widget.attendanceRepository.getByDate(
      AttendanceService.formatDate(DateTime.now()),
    );
    final rows = <_TodayRow>[];
    for (final record in records) {
      final member = await widget.memberRepository.getById(record.memberId);
      rows.add(_TodayRow(member?.name ?? '알 수 없는 회원', record));
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
            Expanded(child: _buildToday()),
          ],
        ),
      ),
    );
  }

  Widget _buildToday() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    // 등원 수에는 등원 시각이 있는 행만 넣는다. 자동 결석 행은 등원하지 않은 사람이다.
    final checkedIn = _rows.where((r) => r.record.checkInTime != null).toList();
    final checkedOut = checkedIn
        .where((r) => r.record.checkOutTime != null)
        .length;
    final stillIn = checkedIn.length - checkedOut;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '등원 ${checkedIn.length} · 하원 $checkedOut · 미하원 $stillIn',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [for (final row in _rows) _TodayTile(row: row)],
          ),
        ),
      ],
    );
  }
}

/// 오늘 행 한 개와 그 회원 이름.
class _TodayRow {
  final String name;
  final Attendance record;

  const _TodayRow(this.name, this.record);
}

/// 한 회원의 오늘 출결. 하원 시각이 없고 등원 시각이 있으면 `미하원` 으로 보인다 —
/// 이 값은 저장하지 않고 화면에서 파생한다.
class _TodayTile extends StatelessWidget {
  final _TodayRow row;

  const _TodayTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final checkIn = row.record.checkInTime;
    final checkOut = row.record.checkOutTime;
    return ListTile(
      title: Text(row.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(checkIn == null ? '등원 기록 없음' : '등원 ${_hhmm(checkIn)}'),
          if (checkIn != null)
            Text(checkOut == null ? '미하원' : '하원 ${_hhmm(checkOut)}'),
        ],
      ),
      trailing: Text(attendanceStatusLabel(row.record.status)),
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
