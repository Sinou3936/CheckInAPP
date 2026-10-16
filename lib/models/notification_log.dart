enum NotificationKind { checkIn, checkOut }

/// 발생한 학부모 알림 이벤트 한 건.
///
/// 지금은 기록만 하고 실제 발송은 하지 않는다. 전송 성공/실패 상태 필드는 실제 발송기를
/// 붙이는 시점에 추가한다 — 지금 넣어봐야 값이 하나뿐이다.
class NotificationLog {
  final int? id;
  final int memberId;
  final String occurredAt; // ISO8601

  final NotificationKind kind;

  /// 학부모 연락처. 등록되어 있지 않으면 null — 그래도 이벤트는 기록해서 관리자가
  /// "알림 대상 없음"을 볼 수 있게 한다.
  final String? recipient;

  const NotificationLog({
    this.id,
    required this.memberId,
    required this.occurredAt,
    required this.kind,
    this.recipient,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'member_id': memberId,
    'occurred_at': occurredAt,
    'kind': kind.name,
    'recipient': recipient,
  };

  factory NotificationLog.fromMap(Map<String, Object?> map) => NotificationLog(
    id: map['id'] as int?,
    memberId: map['member_id'] as int,
    occurredAt: map['occurred_at'] as String,
    kind: NotificationKind.values.byName(map['kind'] as String),
    recipient: map['recipient'] as String?,
  );
}
