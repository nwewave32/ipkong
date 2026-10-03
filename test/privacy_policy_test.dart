import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/ui/settings_screen.dart';

/// 개인정보처리방침이 스스로를 부정하지 않게 지킨다.
///
/// 방침 본문은 "앱에는 네트워크로 데이터를 주고받는 기능 자체가 들어 있지
/// 않습니다" 라고 단언한다. 이건 문서의 수사가 아니라 **릴리스 매니페스트로
/// 증명되는 사실**이어야 한다 — 심사자도 사용자도 권한 목록을 본다.
///
/// 여기서 막고 싶은 사고: 누군가 방침 링크를 WebView 로 바꾸거나, 업데이트
/// 확인·원격 설정 같은 걸 붙이면서 `INTERNET` 을 슬쩍 추가하는 것. 그 순간
/// 방침은 거짓이 되는데, 코드만 보면 아무도 눈치채지 못한다.
void main() {
  group('네트워크 없음이라는 약속', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('릴리스 매니페스트에 INTERNET 권한이 없다', () {
      expect(
        manifest,
        isNot(contains('android.permission.INTERNET')),
        reason:
            'INTERNET 을 선언하는 순간 개인정보처리방침의 "네트워크 기능이 '
            '없다"가 거짓이 된다. 정말 필요하다면 방침부터 고칠 것. '
            '(디버그·프로파일 변종의 INTERNET 은 Flutter 기본값이고 릴리스에 '
            '병합되지 않으므로 무관하다.)',
      );
    });

    test('방침 링크를 열 수 있게 브라우저 조회가 선언돼 있다', () {
      // Android 11+ 는 <queries> 없이는 브라우저가 보이지 않아 링크가
      // 조용히 먹통이 된다. 권한이 아니라 '조회' 선언이라 네트워크와 무관하다.
      expect(
        manifest,
        contains('android.intent.action.VIEW'),
        reason: '이게 없으면 설정 화면의 방침 링크가 아무 일도 하지 않는다',
      );
    });
  });

  group('방침 주소', () {
    test('https 다', () {
      expect(
        privacyPolicyUrl,
        startsWith('https://'),
        reason: '평문 http 로 방침을 내보내면 스토어 심사에서 걸린다',
      );
    });

    test('자리표시자가 아니다', () {
      // 배포된 바이너리에 박히는 값이라, 바꾸려면 앱 업데이트와 심사를
      // 다시 거쳐야 한다. 출시 전에 실제 주소인지 확인할 것.
      expect(
        privacyPolicyUrl,
        isNot(anyOf(contains('example.'), contains('TODO'))),
      );
      expect(Uri.tryParse(privacyPolicyUrl)?.host, isNotEmpty);
    });
  });
}
