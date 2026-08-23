import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 앱 설정 + 익명 기기 키.
///
/// v1.0 은 네트워크를 전혀 쓰지 않는다. 여기 저장되는 값은 어떤 경우에도
/// 기기 밖으로 나가지 않으며, 그래야 App Privacy 라벨을 "데이터 수집 안 함"
/// 으로 제출할 수 있다.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kDeviceId = 'device_id';
  static const _kNotifyHour = 'notify_hour';
  static const _kNotifyMinute = 'notify_minute';
  static const _kWinterMode = 'winter_mode_enabled';
  static const _kWinterAsked = 'winter_asked_for_season';
  static const _kLocale = 'locale';
  static const _kInterestCareLink = 'interest_care_link';
  static const _kOnboardingDone = 'onboarding_done';

  /// 첫 실행 때 발급해 Keychain/Keystore 에 준하는 저장소에 둔다.
  /// v1.1 에서 계정 없이 돌봄 링크의 소유자를 식별하는 열쇠가 된다.
  String get deviceId {
    var id = _prefs.getString(_kDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  int get notifyHour => _prefs.getInt(_kNotifyHour) ?? 9;
  int get notifyMinute => _prefs.getInt(_kNotifyMinute) ?? 0;

  Future<void> setNotifyTime(int hour, int minute) async {
    await _prefs.setInt(_kNotifyHour, hour);
    await _prefs.setInt(_kNotifyMinute, minute);
  }

  /// 겨울 모드는 자동 판정하되 사용자가 끌 수 있다.
  bool get winterModeEnabled => _prefs.getBool(_kWinterMode) ?? true;
  Future<void> setWinterMode(bool v) => _prefs.setBool(_kWinterMode, v);

  /// 같은 겨울에 확인 카드를 두 번 띄우지 않기 위한 표식 (예: '2026-W').
  String? get winterAskedSeason => _prefs.getString(_kWinterAsked);
  Future<void> setWinterAskedSeason(String s) =>
      _prefs.setString(_kWinterAsked, s);

  /// 온보딩을 이미 봤는가. 스킵도 '봤다'로 친다 — 거절한 화면을
  /// 다시 들이미는 앱이 되지 않기 위해서다.
  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone(bool v) => _prefs.setBool(_kOnboardingDone, v);

  String? get localeCode => _prefs.getString(_kLocale);
  Future<void> setLocaleCode(String? code) async {
    if (code == null) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, code);
    }
  }

  /// v1.1 돌봄 링크 예고 티저의 관심 표시.
  ///
  /// ⚠️ 로컬에만 저장한다. 서버로 보내면 "데이터 수집 안 함" 라벨이 깨진다.
  /// 수요 데이터는 포기하되, v1.1 업데이트 후 첫 실행 때 이 플래그를 읽어
  /// "기다리시던 기능이 나왔어요" 를 띄운다.
  bool get interestedInCareLink =>
      _prefs.getBool(_kInterestCareLink) ?? false;
  Future<void> setInterestedInCareLink(bool v) =>
      _prefs.setBool(_kInterestCareLink, v);
}
