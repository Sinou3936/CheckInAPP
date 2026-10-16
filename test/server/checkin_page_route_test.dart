import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/server/checkin_page.dart';

import '../helpers/checkin_server_harness.dart';

void main() {
  test('GET /checkin 은 체크인 HTML 을 서빙한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(h.uri('/checkin'));

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('text/html'));
    expect(response.headers['content-type'], contains('utf-8'));
    expect(response.body.toLowerCase(), contains('<!doctype html'));
  });

  test('페이지는 서버가 실제로 가진 엔드포인트만 참조한다', () {
    for (final endpoint in [
      '/api/session',
      '/api/device-status',
      '/api/members',
      '/api/bind',
      '/api/checkin',
    ]) {
      expect(checkInPageHtml, contains(endpoint), reason: endpoint);
    }
  });

  test('페이지는 Task 11 의 결과 코드를 모두 다룬다', () {
    for (final code in [
      'checkedIn',
      'checkedOut',
      'alreadyCheckedIn',
      'alreadyCheckedOut',
      'no_open_session',
      'verification_failed',
      'verification_unavailable',
      'too_many_attempts',
    ]) {
      expect(checkInPageHtml, contains(code), reason: code);
    }
  });

  test('페이지는 기기 토큰을 localStorage 에 둔다', () {
    expect(checkInPageHtml, contains('localStorage'));
    expect(checkInPageHtml, contains('deviceToken'));
  });

  test('페이지는 외부 스크립트·스타일을 불러오지 않는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    // 체크인 페이지는 인터넷이 없는 로컬 네트워크에서 열린다 — 서빙되는 본문 기준으로 본다.
    final body = (await http.get(h.uri('/checkin'))).body;

    expect(body, isNotEmpty);
    expect(body, isNot(contains('http://')));
    expect(body, isNot(contains('https://')));
  });
}
