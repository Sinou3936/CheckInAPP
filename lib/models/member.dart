class Member {
  final int? id;
  final String name;
  final int? classId;

  /// 학부모 알림의 수신처. 기기 식별에는 쓰지 않는다. 등록되지 않았으면 null.
  final String? parentContact;

  const Member({this.id, required this.name, this.classId, this.parentContact});

  /// 연락처에서 숫자만 남긴 것. 하이픈 유무와 관계없이 같은 값이 된다.
  String get parentContactDigits =>
      parentContact?.replaceAll(RegExp(r'\D'), '') ?? '';

  /// 최초 기기 바인딩의 본인 확인은 학부모 연락처 **숫자 뒷 4자리**로 한다.
  /// 숫자가 4자리에 못 미치면 확인 수단이 못 되므로 그 회원은 폰을 혼자 묶을 수 없고
  /// 관리자가 대행해야 한다. 화면과 서버가 같은 판정을 쓰도록 여기에 둔다.
  bool get canSelfBind => parentContactDigits.length >= 4;

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

  /// `parentContact: null` 은 "바꾸지 않음"과 구별되지 않으므로, 연락처를 지우려면
  /// [clearParentContact] 를 true 로 준다.
  Member copyWith({
    int? id,
    String? name,
    int? classId,
    String? parentContact,
    bool clearParentContact = false,
  }) => Member(
    id: id ?? this.id,
    name: name ?? this.name,
    classId: classId ?? this.classId,
    parentContact: clearParentContact
        ? null
        : (parentContact ?? this.parentContact),
  );
}
