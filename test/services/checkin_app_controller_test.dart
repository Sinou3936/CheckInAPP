import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/qr_token_service.dart';

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

/// `getLocalIPv4` 가 불리면 [requested] 를 완료하고 [release] 가 완료될 때까지 붙든다.
/// start 가 IP 조회를 기다리는 사이에 stop/dispose 를 끼워 넣기 위한 장치.
class _GatedNetworkInfo extends NetworkInfo {
  final Completer<void> requested = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<String?> getLocalIPv4() async {
    if (!requested.isCompleted) requested.complete();
    await release.future;
    return '192.168.1.50';
  }
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

  test('start 직후부터 현재 토큰에 수명이 걸린다', () async {
    final (h, controller) = await _setUp();

    await controller.start();

    // 첫 타이머 틱을 기다리지 않고도, 회전 없이 수명이 지나면 거부되어야 한다.
    final token = h.qr.checkInToken;
    final soon = DateTime.now().add(const Duration(seconds: 1));
    final expired = DateTime.now().add(const Duration(seconds: 41));
    expect(h.qr.kindOf(token, now: soon), QrKind.checkIn);
    expect(h.qr.kindOf(token, now: expired), isNull);
  });

  test('IP 조회 중에 stop 이 불려도 회전 타이머가 남지 않는다', () async {
    final network = _GatedNetworkInfo();
    final (h, controller) = await _setUp(
      networkInfo: network,
      rotationInterval: const Duration(milliseconds: 20),
    );

    final starting = controller.start();
    await network.requested.future;
    await controller.stop();
    network.release.complete();
    await starting;
    final tokenAfterStop = h.qr.checkInToken;

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(h.qr.checkInToken, tokenAfterStop);
    expect(controller.checkInUrl.value, isNull);
  });

  test('IP 조회 중에 dispose 가 불려도 회전 타이머가 남지 않는다', () async {
    final network = _GatedNetworkInfo();
    final (h, controller) = await _setUp(
      networkInfo: network,
      rotationInterval: const Duration(milliseconds: 20),
    );

    final starting = controller.start();
    await network.requested.future;
    controller.dispose();
    network.release.complete();
    await starting;
    final tokenAfterDispose = h.qr.checkInToken;

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(h.qr.checkInToken, tokenAfterDispose);
  });

  test('stop 을 기다리지 않고 dispose 해도 해제된 notifier 에 쓰지 않는다', () async {
    final (_, controller) = await _setUp();
    await controller.start();
    expect(controller.checkInUrl.value, isNotNull);

    final stopping = controller.stop();
    controller.dispose();

    await stopping;
  });
}
