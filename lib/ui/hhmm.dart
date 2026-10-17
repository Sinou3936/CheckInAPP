/// 24시간 표기 `HH:mm`. 시·분 모두 두 자리여야 한다 (`9:00` 은 받지 않고 `09:00` 을 받는다).
///
/// 이 검사를 통과하지 못한 문자열이 저장되면 **그 자리가 아니라 나중에 다른 곳에서 터진다.**
/// `ClassModel.startDateTimeFor` 는 이 값을 `:` 로 쪼개 `int.parse` 하고(결석 처리가 그것을
/// 쓴다), 출결 보정은 이 값으로 ISO8601 을 조립한다. 그래서 입력받는 화면마다 따로 적지 않고
/// 여기 한 곳에 둔다 — 두 벌로 두면 반드시 어긋난다.
final hhmmPattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

bool isValidHhmm(String text) => hhmmPattern.hasMatch(text);
