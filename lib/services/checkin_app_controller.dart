import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/qr_token_service.dart';

/// 체크인 서버의 수명과 QR 회전 시계를 쥐고, 카운터 화면이 그릴 두 주소를 만든다.
///
/// 주소는 `http://<로컬IPv4>:<실제포트>/checkin?token=<토큰>` 이다. 체크인 페이지가 `?token=`
/// 에서 토큰을 읽으므로 이 형식을 바꾸면 스캔한 QR 이 토큰을 못 읽는 페이지를 연다.
class CheckInAppController {
  final QrTokenService qrTokenService;
  final CheckInServer server;
  final NetworkInfo networkInfo;
  final int port;
  final Duration rotationInterval;

  /// 등원용 QR 에 담을 주소. 서버가 뜨기 전이거나 로컬 IPv4 를 못 찾으면 null — 화면이
  /// "네트워크를 찾을 수 없습니다" 를 보여줄 근거다.
  final ValueNotifier<String?> checkInUrl = ValueNotifier(null);

  /// 하원용 QR 에 담을 주소. [checkInUrl] 과 같은 조건에서 null 이다.
  final ValueNotifier<String?> checkOutUrl = ValueNotifier(null);

  Timer? _rotationTimer;
  int? _boundPort;
  bool _disposed = false;

  CheckInAppController({
    required this.qrTokenService,
    required this.server,
    required this.networkInfo,
    this.port = 8080,
    this.rotationInterval = const Duration(seconds: 30),
  });

  /// 서버를 띄우고 주소를 채우고 회전 타이머를 건다.
  ///
  /// 서버가 뜨자마자 한 번 [QrTokenService.rotate] 를 불러 회전 시각을 찍는다 — 그러지 않으면
  /// 첫 타이머 틱까지 현재 토큰에 수명이 없어, 그 사이 타이머가 죽으면 촬영한 QR 이 영구히
  /// 통한다. 타이머는 IP 조회를 기다리기 전에 건다: 기다리는 사이 stop/dispose 가 불려도
  /// 그쪽이 취소할 수 있게 하려는 것이다.
  Future<void> start() async {
    _boundPort = await server.start(port: port);
    qrTokenService.rotate();
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(rotationInterval, (_) => rotateNow());
    await _refreshUrls();
  }

  /// 두 토큰을 즉시 돌리고 두 주소를 갱신한다.
  Future<void> rotateNow() async {
    qrTokenService.rotate();
    await _refreshUrls();
  }

  /// 타이머를 끊고 서버를 내린다. 죽은 서버를 가리키는 주소가 화면에 남지 않도록 비운다.
  Future<void> stop() async {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _boundPort = null;
    await server.stop();
    // 기다리는 사이 dispose 됐으면 notifier 는 이미 해제됐다.
    if (_disposed) return;
    checkInUrl.value = null;
    checkOutUrl.value = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    checkInUrl.dispose();
    checkOutUrl.dispose();
  }

  Future<void> _refreshUrls() async {
    final boundPort = _boundPort;
    if (boundPort == null) return;

    final ip = await networkInfo.getLocalIPv4();
    // IP 를 기다리는 사이 stop 이나 dispose 가 불렸으면 결과를 쓰지 않는다.
    if (_disposed || _boundPort == null) return;

    if (ip == null) {
      checkInUrl.value = null;
      checkOutUrl.value = null;
      return;
    }
    checkInUrl.value = _urlFor(ip, boundPort, qrTokenService.checkInToken);
    checkOutUrl.value = _urlFor(ip, boundPort, qrTokenService.checkOutToken);
  }

  String _urlFor(String ip, int boundPort, String token) =>
      'http://$ip:$boundPort/checkin?token=$token';
}
