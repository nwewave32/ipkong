import '../domain/models/enums.dart';

/// 기후대 판정.
///
/// 기기 언어(`en_US`)보다 IANA 타임존이 실제 위치를 정확히 반영한다.
/// 기기 언어를 영어(미국)로 두고 시드니에 사는 사람은 흔하지만,
/// 타임존은 실제 위치를 따라간다. 위치 권한도 네트워크도 필요 없다.
///
/// 이 파일은 순수 함수만 담는다. 타임존 문자열을 가져오는 부수효과는
/// [ClimateService] 가 맡고, 실패하면 [Climate.northern] 으로 떨어진다.
class ClimateResolver {
  const ClimateResolver._();

  /// 열대 — 겨울이 아예 없다. 어느 쪽으로 적용해도 틀리므로 별도 분류한다.
  ///
  /// ⚠️ 순서 주의: `Australia/Darwin` 은 열대이므로 `Australia/` 접두어보다
  /// 먼저 검사해야 한다. 아래 [resolve] 가 열대를 먼저 확인한다.
  static const tropicalZones = <String>[
    'Australia/Darwin',
    'Asia/Singapore',
    'Asia/Kuala_Lumpur',
    'Asia/Jakarta',
    'Asia/Bangkok',
    'Asia/Manila',
    'Asia/Ho_Chi_Minh',
    'Asia/Colombo',
    'Africa/Nairobi',
    'Africa/Lagos',
    'Africa/Accra',
    'America/Bogota',
    'America/Lima',
    'America/Panama',
    'Pacific/Fiji',
  ];

  /// 남반구 온대 — 5~8월이 겨울이다.
  static const southernZones = <String>[
    'Australia/',
    'Pacific/Auckland',
    'Pacific/Chatham',
    'America/Argentina/',
    'America/Santiago',
    'America/Sao_Paulo',
    'America/Montevideo',
    'America/Asuncion',
    'America/Punta_Arenas',
    'Africa/Johannesburg',
    'Africa/Windhoek',
    'Africa/Harare',
    'Africa/Maputo',
  ];

  /// IANA 타임존 이름으로 기후대를 판정한다.
  ///
  /// 목록 밖은 전부 [Climate.northern]. 한국·일본·미국·유럽·중국이 모두
  /// 기본값에 포함되므로 안전하다.
  static Climate resolve(String? ianaName) {
    if (ianaName == null || ianaName.isEmpty) return Climate.northern;

    for (final z in tropicalZones) {
      if (ianaName == z) return Climate.tropical;
    }
    for (final z in southernZones) {
      final match = z.endsWith('/') ? ianaName.startsWith(z) : ianaName == z;
      if (match) return Climate.southern;
    }
    return Climate.northern;
  }

  /// 지금이 겨울인가.
  static bool isWinter(DateTime now, Climate climate) => switch (climate) {
        Climate.northern => now.month >= 11 || now.month <= 2,
        Climate.southern => now.month >= 5 && now.month <= 8,
        Climate.tropical => false,
      };
}
