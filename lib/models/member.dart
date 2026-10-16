class Member {
  final int? id;
  final String name;
  final int? classId;

  /// 학부모 알림의 수신처. 기기 식별에는 쓰지 않는다. 등록되지 않았으면 null.
  final String? parentContact;

  const Member({this.id, required this.name, this.classId, this.parentContact});

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'class_id': classId,
    'parent_contact': parentContact,
  };

  factory Member.fromMap(Map<String, Object?> map) => Member(
    id: map['id'] as int?,
    name: map['name'] as String,
    classId: map['class_id'] as int?,
    parentContact: map['parent_contact'] as String?,
  );

  Member copyWith({
    int? id,
    String? name,
    int? classId,
    String? parentContact,
  }) => Member(
    id: id ?? this.id,
    name: name ?? this.name,
    classId: classId ?? this.classId,
    parentContact: parentContact ?? this.parentContact,
  );
}
