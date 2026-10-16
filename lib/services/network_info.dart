import 'dart:io';

/// 카운터 PC 가 로컬 네트워크에서 갖는 주소를 찾는다.
///
/// QR 에 담기는 체크인 페이지 주소가 이 값으로 만들어진다. 사설 주소이므로 인터넷에서는
/// 라우팅되지 않는다 — 학생 폰이 학원 WiFi 에 붙어 있어야만 접근할 수 있고, 그 제약이
/// "그 자리에 있어야 한다"는 보증을 만든다.
class NetworkInfo {
  Future<String?> getLocalIPv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }
}
