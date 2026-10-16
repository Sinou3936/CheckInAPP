class DeviceBinding {
  final int? id;
  final String deviceToken;
  final int memberId;

  /// 이 매핑이 만들어진 시각 (ISO8601).
  ///
  /// 같은 기기가 다른 회원으로 다시 묶이면 이 행은 덮어써진다. 사칭 점검을 위한
  /// append-only 이력은 `binding_logs` 에 따로 쌓인다 ([BindingLog]).
  final String boundAt;

  const DeviceBinding({
    this.id,
    required this.deviceToken,
    required this.memberId,
    required this.boundAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'device_token': deviceToken,
    'member_id': memberId,
    'bound_at': boundAt,
  };

  factory DeviceBinding.fromMap(Map<String, Object?> map) => DeviceBinding(
    id: map['id'] as int?,
    deviceToken: map['device_token'] as String,
    memberId: map['member_id'] as int,
    boundAt: map['bound_at'] as String,
  );
}
