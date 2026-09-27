class ClassModel {
  final int? id;
  final String name;
  final String startTime; // "HH:mm"
  final Set<int> operatingDays; // DateTime.weekday values: 1=Mon .. 7=Sun

  const ClassModel({
    this.id,
    required this.name,
    required this.startTime,
    required this.operatingDays,
  });

  bool operatesOn(DateTime date) => operatingDays.contains(date.weekday);

  DateTime startDateTimeFor(DateTime date) {
    final parts = startTime.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'start_time': startTime,
    'operating_days': operatingDays.join(','),
  };

  factory ClassModel.fromMap(Map<String, Object?> map) => ClassModel(
    id: map['id'] as int?,
    name: map['name'] as String,
    startTime: map['start_time'] as String,
    operatingDays: (map['operating_days'] as String)
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toSet(),
  );
}
