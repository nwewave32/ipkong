import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// 코드 생성 없는 수동 로컬라이제이션.
///
/// 문자열이 많아지면 ARB + `flutter gen-l10n` 으로 옮기면 되지만,
/// 스캐폴딩 단계에서는 의존성과 생성 단계를 하나라도 줄이는 편이 낫다.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('ko'), Locale('en')];

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('en'));

  bool get _ko => locale.languageCode == 'ko';

  String _t(String ko, String en) => _ko ? ko : en;

  // ── 앱 ──────────────────────────────────────────────
  String get appName => _t('잎콩', 'Ipkong');
  String get tagline =>
      _t('과습 없는 물주기 알림', 'Plant care that prevents overwatering');

  // ── 날짜·시각 ────────────────────────────────────────
  //
  // `DateFormat` 을 로케일 없이 쓰면 앱 언어와 무관하게 기기 기본 로케일을
  // 따라가서, 한국어를 골라도 "Sep 27" 이 나온다. 앱이 이미 언어를 직접
  // 들고 있으므로(_ko) 여기서 갈라준다 — intl 로케일 데이터를 따로 초기화할
  // 필요도 없어진다.

  /// 날짜. 연도를 생략하지 않는다 — 기록은 해를 넘겨 쌓이고, "9월 27일"
  /// 만으로는 작년 것인지 알 수 없다.
  String date(DateTime d) =>
      _ko ? '${d.year}년 ${d.month}월 ${d.day}일' : DateFormat.yMMMd('en_US').format(d);

  /// 날짜 + 시각. 물주기 기록처럼 하루에 여러 번 쌓일 수 있는 곳에 쓴다.
  String dateTime(DateTime d) => _ko
      ? '${date(d)} ${_koClock(d)}'
      : DateFormat.yMMMd('en_US').add_jm().format(d);

  static String _koClock(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.hour < 12 ? '오전' : '오후'} $hour12:$minute';
  }

  // ── 탭 ──────────────────────────────────────────────
  String get tabToday => _t('오늘', 'Today');
  String get tabPlants => _t('내 식물', 'Plants');
  String get tabSettings => _t('설정', 'Settings');

  // ── 온보딩 (§3) ──────────────────────────────────────
  // 세 화면 모두 기능 자랑이 아니라 '무엇을 요구하지 않는가'를 말한다.
  String get onboard1Title =>
      _t('물은 조금 늦게 주는 편이\n안전해요', 'When in doubt,\nwater a little later');
  String get onboard1Body => _t(
    '실내 식물이 힘들어하는 가장 흔한 이유는 물이 모자라서가 아니라 '
        '너무 자주 받아서예요. 그래서 잎콩은 알림 간격을 넉넉하게 잡습니다.',
    "The most common trouble for houseplants isn't too little water — "
        "it's water too often. So Ipkong leaves plenty of room between "
        'reminders.',
  );
  String get onboard2Title =>
      _t('흙이 어땠는지만 알려주세요', 'Just tell us how the soil felt');
  String get onboard2Body => _t(
    '알림이 오면 흙을 만져보고 축축한지, 적당한지, 바짝 말랐는지 '
        '한 번만 눌러주세요. 그 답이 쌓이면 이 화분에 맞는 주기를 '
        '잎콩이 알아서 찾아갑니다. 식물 이름을 검색할 필요도, '
        '계정을 만들 필요도 없어요.',
    'When a reminder arrives, feel the soil and tap one of three: still '
        'moist, just right, or bone dry. Those answers are how Ipkong '
        'settles on the right rhythm for this pot — no species lookup, '
        'no account.',
  );
  String get onboard3Title =>
      _t('알림은 하루에 하나뿐입니다', 'One notification a day. That’s it');
  String get onboard3Body => _t(
    '식물이 몇 그루든 하나로 묶어서 보냅니다. 밀린 일정을 빨간 배지로 '
        '쌓아 올리지도 않아요. 기록은 전부 이 기기 안에만 있습니다.',
    'However many plants you have, they arrive grouped into one. No red '
        'badges piling up. Everything stays on this device.',
  );
  String get onboardNext => _t('다음', 'Next');
  String get onboardStart => _t('첫 식물 등록하기', 'Add my first plant');

  // ── 오늘 ────────────────────────────────────────────
  String get todayEmpty => _t('오늘은 확인할 식물이 없어요', 'Nothing to check today');
  String nextCheckIn(int days) =>
      _ko ? '다음 확인까지 $days일' : 'Next check in $days days';
  String get watered => _t('줬어요', 'Watered');

  // ── 흙 상태 응답 ─────────────────────────────────────
  String get soilQuestion => _t('흙이 어땠나요?', 'How was the soil?');
  String get settledQuestion => _t('물 줄 시간이에요', 'Time to water');
  String get tooWet => _t('축축했어요', 'Still moist');
  String get justRight => _t('적당했어요', 'Just right');
  String get tooDry => _t('바짝 말랐어요', 'Bone dry');
  String get stillMoist => _t('아직 축축해요', 'Still moist');

  /// 세 선택지를 가르는 건 겉흙이 아니라 **속흙**이다. 이 한 줄이 없으면
  /// '적당했어요' 를 무엇으로 판단해야 할지 알 수 없다 — 겉만 보면 마른
  /// 흙과 속까지 마른 흙이 똑같이 보인다.
  String get soilDepthHint => _t(
    '검지를 두 마디(약 3cm) 찔러 넣어 보세요',
    'Push your finger in about two knuckles (1 inch)',
  );
  String get tooWetHint =>
      _t('손가락에 흙이 묻어나요', 'Soil sticks to your finger');
  String get justRightHint => _t(
    '겉은 말랐는데 속은 아직 서늘해요',
    'Dry on top, still cool underneath',
  );
  String get tooDryHint => _t(
    '두 마디 깊이까지 푸석하고 가벼워요',
    'Crumbly and light all the way down',
  );
  String get wateredHint => _t(
    '화분 밑으로 흘러나올 만큼 듬뿍',
    'Enough to run out of the drainage hole',
  );
  String get stillMoistHint =>
      _t('이번엔 건너뛰고 다음에 다시 여쭤볼게요', "We'll skip this one and ask again");

  // ── 식물 추가 ────────────────────────────────────────
  String get addPlant => _t('식물 추가', 'Add plant');
  String get plantName => _t('이름', 'Name');
  String get plantNameHint => _t('내 식물', 'My plant');
  String get kindQuestion => _t('이 식물은 어디에 가까운가요?', 'Which is it closest to?');
  String get kindSucculent => _t('다육 · 선인장', 'Succulent · Cactus');
  String get kindNormal => _t('일반 화분 식물', 'Regular potted plant');
  String get kindThinLeaf => _t('잎이 얇고 넓은 것 · 허브', 'Thin wide leaves · Herbs');
  String get lightQuestion => _t('어디에 두셨나요?', 'Where did you put it?');
  String get lightBright => _t('밝은 창가', 'Bright window');
  String get lightMedium => _t('보통', 'Medium');
  String get lightLow => _t('어두움', 'Low light');
  String get intervalLabel => _t('물주기', 'Watering every');
  String days(int n) => _ko ? '$n일' : (n == 1 ? '1 day' : '$n days');
  String get everyNDaysSuffix => _t('마다', '');
  String get edit => _t('수정', 'Edit');
  String get save => _t('저장', 'Save');
  String get cancel => _t('취소', 'Cancel');
  String get delete => _t('삭제', 'Delete');
  String get photo => _t('사진', 'Photo');
  String get skip => _t('건너뛰기', 'Skip');

  // ── 사진 ────────────────────────────────────────────
  String get photoOptional => _t('사진 (선택)', 'Photo (optional)');
  String get photoChange => _t('탭해서 바꾸기', 'Tap to change');
  String get photoFromGallery => _t('앨범에서 고르기', 'Choose from library');
  String get photoFromCamera => _t('사진 찍기', 'Take a photo');
  String get photoRemove => _t('사진 지우기', 'Remove photo');

  // ── 주기 안내 문구 ───────────────────────────────────
  String get intervalSuggestedNote => _t(
    '기본 제안값입니다. 그대로 두셔도 쓰면서 맞춰집니다',
    "A suggested starting point. Leave it — it'll adjust as you go",
  );
  String get intervalCurrentNote => _t(
    '지금 적용 중인 주기입니다. 그대로 두시면 계속 맞춰갑니다',
    "The interval in use now. Leave it and it'll keep adjusting",
  );
  String get intervalUserNote =>
      _t('✓ 직접 정하신 주기를 기준으로 맞춰갑니다', '✓ Adjusting from the interval you set');

  // ── 식물 수정 ────────────────────────────────────────
  String get editPlant => _t('식물 수정', 'Edit plant');
  String get relocateResetsSettling => _t(
    '자리나 종류가 바뀌면 주기를 다시 맞춰야 해서, 확정된 주기가 풀리고 '
        '흙 상태를 몇 번 더 여쭤봅니다.',
    'A new spot or type means the schedule needs rechecking, so it '
        'unlocks and we ask about the soil a few more times.',
  );
  String get intervalOverrideWarning => _t(
    '직접 정한 주기가 지금까지 배운 조정값보다 우선합니다. 앞으로는 이 '
        '값을 기준으로 다시 맞춰가요.',
    "Your interval overrides what we've learned so far. We'll start "
        'adjusting again from this value.',
  );
  String get deleteConfirmTitle => _t('이 식물을 지울까요?', 'Delete this plant?');
  String deleteConfirmBody(String name) => _ko
      ? '$name 의 물주기 알림이 더 이상 오지 않습니다. 되돌릴 수 없어요.'
      : "You'll stop getting watering reminders for $name. This can't be undone.";

  // ── 상세 ────────────────────────────────────────────
  String get history => _t('물주기 기록', 'Watering history');
  String get waterNow => _t('지금 물주기', 'Water now');
  String settledHint(int remaining) => _ko
      ? '$remaining번 더 답하면 주기가 확정돼요'
      : '$remaining more answers to lock in the schedule';
  String get settledDone => _t('주기가 확정되었어요', 'Schedule locked in');
  String get drainageWarning => _t(
    '계속 축축하네요. 화분 배수구가 막혔거나 받침에 물이 고여 있는지 확인해보세요.',
    "Still moist. Check your pot's drainage or the saucer.",
  );

  // ── 겨울 모드 ────────────────────────────────────────
  String get winterCardTitle => _t('날이 추워졌나요?', 'Has it turned cold?');
  String get winterCardBody => _t(
    '겨울엔 식물이 물을 훨씬 천천히 씁니다. 물주기를 조금 늦출까요?',
    'Plants drink much slower in winter. Should we slow the schedule down?',
  );
  String get winterYes => _t('네, 늦춰주세요', 'Yes, slow it down');
  String get winterNo => _t('아니요, 그대로', 'No, keep it');
  String get winterMode => _t('겨울 모드', 'Winter mode');

  // ── 설정 ────────────────────────────────────────────
  String get settingsNotifications => _t('알림', 'Notifications');
  String get settingsData => _t('내 데이터', 'My data');

  String get notifyTime => _t('알림 시간', 'Notification time');
  String get notifyTimeDesc => _t(
    '하루에 한 번만 알립니다. 확인할 식물이 여러 개면 하나로 묶어서 보내요.',
    'One notification a day. Several plants are grouped into one.',
  );
  String get notifyTimeChange => _t('알림 시간 바꾸기', 'Change notification time');
  String get photoSaveFailed => _t(
    '사진을 저장하지 못했어요. 나머지 정보는 저장됐습니다.',
    "Couldn't save the photo. Everything else was saved.",
  );
  /// 시간 휠 각 칸의 스크린 리더 이름. 값만 읽히면 "9" 가 시인지 분인지 모른다.
  String get wheelAmPm => _t('오전 오후', 'AM or PM');
  String get wheelHour => _t('시', 'Hour');
  String get wheelMinute => _t('분', 'Minute');
  String get notifySheetNote => _t(
    '하루에 한 번, 이 시각에 알립니다. 정시 알람이 아니라 십수 분 늦을 수 있습니다.',
    'Once a day, around this time. It is not an exact alarm, so it can be '
        'a few minutes late.',
  );

  String get language => _t('언어', 'Language');
  String get languageSystem => _t('시스템 설정', 'System');
  String get comingSoon => _t('곧 나올 기능', 'Coming soon');

  // ── 겨울 모드 ────────────────────────────────────────
  String get winterModeDesc => _t(
    '겨울엔 식물이 물을 훨씬 천천히 씁니다. 켜두면 물주기 간격을 자동으로 늘려 과습을 막아요.',
    'Plants drink far slower in winter. This stretches the interval '
        'automatically so you do not overwater.',
  );
  String get winterStatusActive => _t(
    '지금은 겨울 — 간격을 1.4배로 늘리는 중 (다육은 1.9배)',
    'Winter now — intervals stretched 1.4× (1.9× for succulents)',
  );
  String get winterStatusOffInWinter => _t(
    '지금은 겨울이지만 꺼져 있어서 평소 간격으로 알립니다',
    "It's winter, but this is off — using the usual interval",
  );
  String get winterStatusNotWinter => _t(
    '지금은 겨울이 아니라 평소 간격이에요',
    'Not winter right now — using the usual interval',
  );
  String get winterStatusTropical => _t(
    '이 지역은 겨울이 없어서 늘 평소 간격이에요',
    'No winter in this region — always the usual interval',
  );

  // ── 데이터 내보내기 ───────────────────────────────────
  String get exportData => _t('내 식물 데이터 내보내기', 'Export my plant data');
  String get exportDataDesc => _t(
    '등록한 식물과 물주기 기록을 파일로 저장하거나 복사합니다.',
    'Save your plants and watering history as a file, or copy them.',
  );
  String get exportDialogTitle => _t('무엇이 나가나요?', 'What gets exported?');
  String exportDialogBody(int plants, int events) => _ko
      ? '식물 $plants개와 물주기 기록 $events건이 JSON 파일로 저장됩니다.\n\n'
            '잎콩은 이 데이터를 어디에도 보내지 않고 기기 안에만 둡니다. '
            '그래서 앱을 지우거나 기기를 바꾸면 되살릴 방법이 없어요. '
            '메모 앱이나 메일에 붙여넣어 보관해두세요.'
      : '$plants ${plants == 1 ? "plant" : "plants"} and $events watering '
            '${events == 1 ? "record" : "records"} will be copied as text.\n\n'
            'Ipkong keeps this data on your device and never sends it anywhere, '
            'so deleting the app or switching phones loses it for good. '
            'Paste it somewhere safe — a notes app or an email to yourself.';
  String get exportNothing => _t('아직 등록한 식물이 없어요', 'No plants registered yet');
  String get exportCopy => _t('복사', 'Copy');
  String get exportShare => _t('파일로 저장', 'Save as file');
  String get exportDone =>
      _t('복사했습니다. 안전한 곳에 붙여넣어 두세요.', 'Copied. Paste it somewhere safe.');
  String get exportSaved => _t(
    '내보냈습니다. 이 파일이 있으면 기기를 바꿔도 기록이 남습니다.',
    'Exported. Keep this file and your records survive a new phone.',
  );
  String get exportFileSubject => _t('잎콩 백업', 'Ipkong backup');
  String get exportFellBackToCopy => _t(
    '파일로 저장할 수 없어 대신 복사했습니다. 안전한 곳에 붙여넣어 두세요.',
    "Couldn't save a file, so it was copied instead. Paste it somewhere safe.",
  );

  // ── v1.1 돌봄 링크 티저 ───────────────────────────────
  String get careLinkTitle =>
      _t('여행 가실 때, 식물을 맡길 수 있어요', 'Hand your plants to someone while away');
  String get careLinkBody => _t(
    '링크 하나만 보내면 됩니다. 상대는 앱을 설치할 필요도, 로그인할 필요도 없어요.',
    'Just send a link. No app install, no login on their side.',
  );
  String get careLinkNextUpdate =>
      _t('다음 업데이트에서 만나요', 'Coming in the next update');
  String get careLinkNotifyMe => _t('나올 때 알려주세요', 'Notify me');
  String get careLinkNoted =>
      _t('알겠습니다. 나오면 알려드릴게요!', "Got it — we'll let you know!");
}

class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales.any(
    (l) => l.languageCode == locale.languageCode,
  );

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
