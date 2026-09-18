class Member {
  final int? id;
  final String name;
  final int? classId;

  const Member({this.id, required this.name, this.classId});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'class_id': classId,
      };

  factory Member.fromMap(Map<String, Object?> map) => Member(
        id: map['id'] as int?,
        name: map['name'] as String,
        classId: map['class_id'] as int?,
      );

  Member copyWith({int? id, String? name, int? classId}) => Member(
        id: id ?? this.id,
        name: name ?? this.name,
        classId: classId ?? this.classId,
      );
}
