class DeviceBinding {
  final int? id;
  final String deviceToken;
  final int memberId;

  const DeviceBinding({
    this.id,
    required this.deviceToken,
    required this.memberId,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'device_token': deviceToken,
    'member_id': memberId,
  };

  factory DeviceBinding.fromMap(Map<String, Object?> map) => DeviceBinding(
    id: map['id'] as int?,
    deviceToken: map['device_token'] as String,
    memberId: map['member_id'] as int,
  );
}
