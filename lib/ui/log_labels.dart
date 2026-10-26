import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/notification_log.dart';

String notificationKindLabel(NotificationKind kind) => switch (kind) {
  NotificationKind.checkIn => '등원',
  NotificationKind.checkOut => '하원',
};

/// ISO8601 시각을 `yyyy-MM-dd HH:mm` 으로 줄인다. 파싱이 안 되면 원문을 그대로 보인다.
String formatLogTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}

/// 회원 이름. 회원이 삭제됐어도 이력은 남으므로 이름을 못 찾으면 번호로 보인다.
String memberNameOf(Map<int, Member> membersById, int memberId) =>
    membersById[memberId]?.name ?? '삭제된 회원 (#$memberId)';
