import 'package:flutter_timezone/flutter_timezone.dart';

/// 기기의 IANA 타임존 이름 (예: `Asia/Seoul`).
///
/// flutter_timezone 5.x 는 `TimezoneInfo` 를 돌려주며 `identifier` 에
/// IANA 이름이 들어 있다.
///
/// 실패하면 null 을 돌려준다. 호출부는 북반구로 떨어뜨리면 되고,
/// 어차피 겨울 확인 카드가 사용자에게 되묻기 때문에 치명적이지 않다.
Future<String?> resolveLocalTimezoneName() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    final id = info.identifier;
    return id.isEmpty ? null : id;
  } catch (_) {
    return null;
  }
}
