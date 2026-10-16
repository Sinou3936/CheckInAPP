/// 기기 바인딩이 일어날 때마다 쌓이는 append-only 기록.
///
/// 현재 매핑(`device_bindings`)은 재바인딩 시 덮어써지므로, 사칭이 있었다면 폰이 원래
/// 주인에게 되돌려진 뒤에는 흔적이 남지 않는다. 관리자가 사후에 점검할 수 있도록
/// 이 테이블은 덮어쓰지 않고 쌓는다.
class BindingLog {
  final int? id;
  final String deviceToken;
  final int memberId;
  final String occurredAt; // ISO8601

  const BindingLog({
    this.id,
    required this.deviceToken,
    required this.memberId,
    required this.occurredAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'device_token': deviceToken,
    'member_id': memberId,
    'occurred_at': occurredAt,
  };

  factory BindingLog.fromMap(Map<String, Object?> map) => BindingLog(
    id: map['id'] as int?,
    deviceToken: map['device_token'] as String,
    memberId: map['member_id'] as int,
    occurredAt: map['occurred_at'] as String,
  );
}
