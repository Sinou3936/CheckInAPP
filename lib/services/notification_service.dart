import 'package:checkin_app/models/notification_log.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';

/// 학부모 알림을 실제로 내보내는 지점.
///
/// 지금은 기록만 하는 구현체 하나뿐이다. 문자/카카오 알림톡 발송기는 업체 계약과
/// 사업자등록이 가능해지는 시점에 이 인터페이스 뒤에 붙인다 — 알림톡은 채널 개설과
/// 템플릿 사전 승인, 사업자등록증이 필요해서 실제 학원을 운영하지 않는 상태로는 발급
/// 자체가 불가능하다.
abstract class ParentNotifier {
  Future<void> notify(NotificationLog log);
}

/// 알림 이벤트를 DB에 남기기만 하는 구현체. 관리자 화면이 이 기록을 보여준다.
class RecordingParentNotifier implements ParentNotifier {
  final NotificationLogRepository repository;
  RecordingParentNotifier(this.repository);

  @override
  Future<void> notify(NotificationLog log) async {
    await repository.insert(log);
  }
}

/// 등원·하원 알림 이벤트를 만들어 [ParentNotifier] 에 넘긴다.
///
/// **이 서비스를 호출하는 곳은 학생이 QR 을 스캔하는 경로뿐이다.** 관리자가 이력 화면에서
/// 기록을 보정할 때는 저장소를 직접 쓰고 알림을 내지 않는다 — 다음 날 아침의 보정이 학부모에게
/// "자녀가 나갔습니다"로 전달되면, 회전 QR 로 막으려 한 바로 그 피해가 된다. 그래서 이 서비스는
/// "호출되면 기록한다"만 하고, 호출 여부 판단은 부르는 쪽이 한다.
class NotificationService {
  final MemberRepository memberRepository;
  final ParentNotifier notifier;

  NotificationService({required this.memberRepository, required this.notifier});

  Future<void> onCheckIn(int memberId, DateTime at) =>
      _emit(memberId, at, NotificationKind.checkIn);

  Future<void> onCheckOut(int memberId, DateTime at) =>
      _emit(memberId, at, NotificationKind.checkOut);

  Future<void> _emit(int memberId, DateTime at, NotificationKind kind) async {
    final member = await memberRepository.getById(memberId);
    // 연락처가 없으면 수신처 없이 기록한다 — 관리자가 "알림 대상 없음"을 볼 수 있어야 한다.
    await notifier.notify(
      NotificationLog(
        memberId: memberId,
        occurredAt: at.toIso8601String(),
        kind: kind,
        recipient: member?.parentContact,
      ),
    );
  }
}
