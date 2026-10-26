import 'dart:async';

import 'package:checkin_app/services/qr_token_service.dart';

/// 체크가 기록된 순간 하나. 카운터 화면이 "출결 되었습니다" 를 띄우는 근거다.
class CheckInEvent {
  final String memberName;

  /// 등원인지 하원인지. 스캔한 QR 의 종류가 그대로 온다.
  final QrKind kind;

  /// 등원이 지각으로 기록됐는가. 하원 이벤트에서는 항상 false.
  final bool isLate;

  const CheckInEvent({
    required this.memberName,
    required this.kind,
    this.isLate = false,
  });
}

/// 학생 폰에서 기록된 체크를 카운터 화면으로 흘려보내는 통로.
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

  /// 기록이 **새로 생긴** 경우에만 부른다. 재스캔까지 발행하면 카운터 화면이 방금 찍지 않은
  /// 사람의 완료 문구를 띄운다.
  void publish(CheckInEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
