import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/network_info.dart';

void main() {
  test('getLocalIPv4 는 null 이거나 점 4개 형식의 IPv4 를 돌려준다', () async {
    final ip = await NetworkInfo().getLocalIPv4();
    if (ip != null) {
      expect(
        RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip),
        isTrue,
      );
    }
  });
}
