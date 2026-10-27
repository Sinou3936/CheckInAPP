import 'dart:async';

/// 카운터 화면에 뜨는 사건의 종류.
///
/// 기록된 체크 두 가지와 **막힌 시도** 두 가지다. 막힌 시도는 아무것도 기록하지 않으므로
/// 출결 행도, 알림 기록도 남지 않는다 — 이 통로가 유일한 흔적이고, 학생이 카운터 앞에
/// 서 있는 그 순간이 직원이 알아야 하는 순간이다.
enum CheckEventKind {
  checkedIn,
  checkedOut,

  /// 최소 체류 시간이 지나지 않아 하원이 막혔다.
  blockedTooEarly,

  /// 등원으로부터 하원 창(12시간)이 지나 하원이 막혔다. 관리자 보정 대상이다.
  blockedOverdue,
}

/// 카운터 화면이 배너를 띄우는 근거가 되는 순간 하나.
class CheckInEvent {
  final String memberName;

  final CheckEventKind kind;

  /// 등원이 지각으로 기록됐는가. [CheckEventKind.checkedIn] 에서만 참이 될 수 있다.
  final bool isLate;

  /// 하원까지 남은 시간. [CheckEventKind.blockedTooEarly] 에서만 채운다.
  final Duration? remaining;

  const CheckInEvent({
    required this.memberName,
    required this.kind,
    this.isLate = false,
    this.remaining,
  });
}

/// 학생 폰에서 일어난 일을 카운터 화면으로 흘려보내는 통로.
///
/// 서버와 관리자 UI 는 같은 프로세스에 있으므로 이 한 줄짜리 스트림으로 충분하다 — 둘 사이에
/// 별도 통신 계층을 만들지 않는다는 결정을 지킨다.
///
/// 브로드캐스트 스트림이라 듣는 사람이 없을 때 발행한 이벤트는 버려진다. 지난 체크는 현황
/// 목록에 이미 남아 있으므로, 놓친 알림을 되돌려줄 필요가 없다.
class CheckInEventBus {
  final StreamController<CheckInEvent> _controller =
      StreamController<CheckInEvent>.broadcast();

  Stream<CheckInEvent> get events => _controller.stream;

  /// 기록이 **새로 생긴** 경우와 시도가 **막힌** 경우에만 부른다. 재스캔(이미 등원·이미
  /// 하원)까지 발행하면 카운터 화면이 방금 찍지 않은 사람의 완료 문구를 띄운다.
  void publish(CheckInEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
