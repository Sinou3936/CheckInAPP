import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/network_info.dart';

import '../helpers/checkin_server_harness.dart';

class _FixedNetworkInfo extends NetworkInfo {
  @override
  Future<String?> getLocalIPv4() async => '192.168.1.50';
}

class _NoNetworkInfo extends NetworkInfo {
  @override
  Future<String?> getLocalIPv4() async => null;
}

/// 하네스가 이미 서버를 띄워 두므로 컨트롤러의 `start` 는 그 서버의 포트를 돌려받는다
/// (`CheckInServer.start` 의 재진입 방지). 컨트롤러 정리는 하네스보다 먼저 걸어 둔다 —
/// addTearDown 은 거꾸로 실행되므로 컨트롤러가 먼저 내려가고 DB 가 닫힌다.
Future<(CheckInServerHarness, CheckInAppController)> _setUp({
  NetworkInfo? networkInfo,
  Duration rotationInterval = const Duration(seconds: 30),
}) async {
  final h = await CheckInServerHarness.start();
  addTearDown(h.close);
  final controller = CheckInAppController(
    qrTokenService: h.qr,
    server: h.server,
    networkInfo: networkInfo ?? _FixedNetworkInfo(),
    port: 0,
    rotationInterval: rotationInterval,
  );
  addTearDown(controller.dispose);
  addTearDown(controller.stop);
  return (h, controller);
}

String _tokenOf(String? url) => Uri.parse(url!).queryParameters['token']!;

void main() {
  test('start 는 두 종류의 주소를 각자의 토큰으로 채운다', () async {
    final (h, controller) = await _setUp();

    await controller.start();

    final prefix = 'http://192.168.1.50:${h.port}/checkin?token=';
    expect(controller.checkInUrl.value, startsWith(prefix));
    expect(controller.checkOutUrl.value, startsWith(prefix));
    expect(_tokenOf(controller.checkInUrl.value), h.qr.checkInToken);
    expect(_tokenOf(controller.checkOutUrl.value), h.qr.checkOutToken);
    expect(
      _tokenOf(controller.checkInUrl.value),
      isNot(_tokenOf(controller.checkOutUrl.value)),
    );
  });

  test('start 전에는 두 주소가 null 이다', () async {
    final (_, controller) = await _setUp();

    expect(controller.checkInUrl.value, isNull);
    expect(controller.checkOutUrl.value, isNull);
  });

  test('rotateNow 는 두 주소를 모두 바꾼다', () async {
    final (h, controller) = await _setUp();
    await controller.start();
    final beforeCheckIn = controller.checkInUrl.value;
    final beforeCheckOut = controller.checkOutUrl.value;

    await controller.rotateNow();

    expect(controller.checkInUrl.value, isNot(beforeCheckIn));
    expect(controller.checkOutUrl.value, isNot(beforeCheckOut));
    expect(_tokenOf(controller.checkInUrl.value), h.qr.checkInToken);
    expect(_tokenOf(controller.checkOutUrl.value), h.qr.checkOutToken);
  });

  test('로컬 IPv4 를 찾을 수 없으면 두 주소가 null 이다', () async {
    final (_, controller) = await _setUp(networkInfo: _NoNetworkInfo());

    await controller.start();

    expect(controller.checkInUrl.value, isNull);
    expect(controller.checkOutUrl.value, isNull);
  });

  test('회전 타이머가 주기마다 두 주소를 바꾼다', () async {
    final (_, controller) = await _setUp(
      rotationInterval: const Duration(milliseconds: 20),
    );
    await controller.start();
    final first = controller.checkInUrl.value;

    final changed = Completer<void>();
    controller.checkInUrl.addListener(() {
      if (!changed.isCompleted) changed.complete();
    });
    await changed.future.timeout(const Duration(seconds: 5));

    expect(controller.checkInUrl.value, isNot(first));
  });

  test('stop 뒤에는 서버에 접속할 수 없다', () async {
    final (h, controller) = await _setUp();
    await controller.start();
    expect((await http.get(h.uri('/checkin'))).statusCode, 200);

    await controller.stop();

    await expectLater(http.get(h.uri('/checkin')), throwsA(anything));
    expect(controller.checkInUrl.value, isNull);
    expect(controller.checkOutUrl.value, isNull);
  });

  test('stop 뒤에는 회전 타이머가 멈춘다', () async {
    final (h, controller) = await _setUp(
      rotationInterval: const Duration(milliseconds: 20),
    );
    await controller.start();
    await controller.stop();
    final tokenAfterStop = h.qr.checkInToken;

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(h.qr.checkInToken, tokenAfterStop);
  });
}
