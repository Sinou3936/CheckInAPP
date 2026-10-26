import 'package:flutter/material.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/ui/screens/binding_log_view.dart';
import 'package:checkin_app/ui/screens/notification_log_view.dart';

/// 관리자가 사후 점검에 쓰는 두 이력(학부모 알림 내역, 기기 바인딩 이력)을 한 화면에 모은다.
class AuditLogScreen extends StatelessWidget {
  final DeviceBindingRepository deviceBindingRepository;
  final NotificationLogRepository notificationLogRepository;
  final MemberRepository memberRepository;

  const AuditLogScreen({
    super.key,
    required this.deviceBindingRepository,
    required this.notificationLogRepository,
    required this.memberRepository,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('알림·바인딩 이력'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '알림 내역'),
              Tab(text: '바인딩 이력'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            NotificationLogView(
              notificationLogRepository: notificationLogRepository,
              memberRepository: memberRepository,
            ),
            BindingLogView(
              deviceBindingRepository: deviceBindingRepository,
              memberRepository: memberRepository,
            ),
          ],
        ),
      ),
    );
  }
}
