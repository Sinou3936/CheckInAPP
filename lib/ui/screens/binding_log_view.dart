import 'package:flutter/material.dart';
import 'package:checkin_app/models/binding_log.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/ui/log_labels.dart';

/// 기기 바인딩 이력 목록. 어떤 폰이 언제 누구로 묶였는지 보고 사칭을 점검한다.
///
/// 같은 기기가 서로 다른 회원으로 묶인 기록이 있으면 표시한다 — 폰이 원래 주인에게
/// 되돌려졌어도 이 이력으로 흔적이 남는다.
class BindingLogView extends StatefulWidget {
  final DeviceBindingRepository deviceBindingRepository;
  final MemberRepository memberRepository;

  const BindingLogView({
    super.key,
    required this.deviceBindingRepository,
    required this.memberRepository,
  });

  @override
  State<BindingLogView> createState() => _BindingLogViewState();
}

class _BindingLogViewState extends State<BindingLogView> {
  List<BindingLog> _logs = const [];
  Map<int, Member> _members = const {};
  Set<String> _reboundTokens = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final logs = await widget.deviceBindingRepository.getRecentLogs();
    final members = await widget.memberRepository.getAll();

    // 기기 토큰별로 묶인 회원이 둘 이상이면 재바인딩된 기기다.
    final membersByToken = <String, Set<int>>{};
    for (final log in logs) {
      membersByToken.putIfAbsent(log.deviceToken, () => {}).add(log.memberId);
    }
    final rebound = {
      for (final e in membersByToken.entries)
        if (e.value.length > 1) e.key,
    };

    if (!mounted) return;
    setState(() {
      _logs = logs;
      _members = {for (final m in members) m.id!: m};
      _reboundTokens = rebound;
      _loaded = true;
    });
  }

  /// 기기 토큰은 길어서 앞 8자리만 보인다. 구분용이지 식별 근거가 아니다.
  String _shortToken(String token) =>
      token.length <= 8 ? token : '${token.substring(0, 8)}…';

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_logs.isEmpty) return const Center(child: Text('바인딩 이력이 없습니다.'));

    final errorColor = Theme.of(context).colorScheme.error;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        children: [
          for (final log in _logs)
            ListTile(
              leading: Icon(
                _reboundTokens.contains(log.deviceToken)
                    ? Icons.warning_amber
                    : Icons.phone_android,
                color: _reboundTokens.contains(log.deviceToken)
                    ? errorColor
                    : null,
              ),
              title: Text(memberNameOf(_members, log.memberId)),
              subtitle: Text(
                '${formatLogTime(log.occurredAt)} · 기기 ${_shortToken(log.deviceToken)}'
                '${_reboundTokens.contains(log.deviceToken) ? '\n다른 회원으로도 묶인 기기' : ''}',
              ),
              isThreeLine: _reboundTokens.contains(log.deviceToken),
            ),
        ],
      ),
    );
  }
}
