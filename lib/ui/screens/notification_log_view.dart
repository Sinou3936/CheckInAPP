import 'package:flutter/material.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/notification_log.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/ui/log_labels.dart';

/// 발생한 학부모 알림 내역 목록. 지금은 실제 발송 없이 기록만 하므로 이 화면이 유일한 확인 수단이다.
class NotificationLogView extends StatefulWidget {
  final NotificationLogRepository notificationLogRepository;
  final MemberRepository memberRepository;

  const NotificationLogView({
    super.key,
    required this.notificationLogRepository,
    required this.memberRepository,
  });

  @override
  State<NotificationLogView> createState() => _NotificationLogViewState();
}

class _NotificationLogViewState extends State<NotificationLogView> {
  List<NotificationLog> _logs = const [];
  Map<int, Member> _members = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final logs = await widget.notificationLogRepository.getRecent();
    final members = await widget.memberRepository.getAll();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _members = {for (final m in members) m.id!: m};
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_logs.isEmpty) return const Center(child: Text('알림 내역이 없습니다.'));

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        children: [
          for (final log in _logs)
            ListTile(
              leading: Icon(
                log.kind == NotificationKind.checkIn
                    ? Icons.login
                    : Icons.logout,
              ),
              title: Text(
                '${memberNameOf(_members, log.memberId)} · ${notificationKindLabel(log.kind)}',
              ),
              // 연락처가 없어도 이벤트는 기록된다 — 관리자가 "알림 대상 없음"을 알아야 한다.
              subtitle: Text(
                '${formatLogTime(log.occurredAt)} · '
                '${log.recipient == null ? '알림 대상 없음' : '수신처 ${log.recipient}'}',
              ),
            ),
        ],
      ),
    );
  }
}
