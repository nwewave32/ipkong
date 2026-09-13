# 잎콩 (Ipkong)

과습을 막는 물주기 알림 앱. 물을 주라고 시키지 않고, 물이 필요한지 확인하게 한다.

> 이 README 는 코드 구조와 실행 방법만 다룹니다.
> 기획 문서와 빌드 체크리스트는 저장소에 포함하지 않습니다.

```bash
flutter test     # 알고리즘 · 알림 계획 · 기후대 판정
flutter run
```

---

## 현재 상태

알림이 실기기로 나갑니다. `lib/notifications/local_notification_backend.dart`
가 `flutter_local_notifications` 22.x 어댑터이고, `main.dart` 가 이것을
주입합니다. 아직 실기기에서 눌러보지는 않았습니다 (남은 작업 참고).

어떤 날짜에 무엇을 보낼지는 `notification_plan.dart` 가 정하고, 어댑터는
그 계획을 플랫폼 API 로 옮기기만 합니다. 계획 로직은 플랫폼을 모르므로
단위 테스트가 됩니다.

알아둘 것 세 가지:

- **iOS 액션 버튼은 알림마다 붙일 수 없습니다.** `initialize` 때
  `DarwinNotificationCategory` 로 미리 등록하고, 알림은 카테고리 ID 만
  지목합니다. 그래서 버튼 문구를 언어에 따라 바꾸려면 재등록이 필요합니다
- **정시 알람을 쓰지 않습니다.** Android 14+ 에서 `SCHEDULE_EXACT_ALARM` 은
  알람시계·캘린더 앱 전용이라 물주기 알림은 승인을 받을 수 없습니다.
  `inexactAllowWhileIdle` 로 예약하고, 오차는 길어야 십수 분입니다
- **액션은 앱을 열지 않습니다.** 백그라운드 isolate 로 떨어져
  (`ipkongBackgroundActionHandler`) DB 대신 `PendingActions` 큐에만 적고,
  앱이 다음에 열릴 때 반영됩니다

`DebugNotificationBackend` 는 남아 있습니다 — 위젯 테스트가
`notificationBackendProvider` 를 오버라이드하지 않으므로, 기본값이 실제
구현이면 테스트가 플랫폼 채널을 부르다 죽습니다.

---

## 구조

```
lib/
├── main.dart                      진입점 — 기후대 판정, DI, 백엔드 선택
├── app.dart                       MaterialApp, 테마, 로컬라이제이션
│
├── core/
│   ├── climate.dart               타임존 → 기후대 판정 (순수)
│   └── local_timezone.dart        flutter_timezone 래퍼
│
├── domain/                        ★ 외부 의존성 없음. 전부 순수 함수
│   ├── models/
│   └── watering_schedule.dart     ★ 물주기 알고리즘
│
├── data/
│   ├── app_database.dart          sqflite 초기화 + 마이그레이션
│   ├── plant_repository.dart      식물 CRUD + 이벤트 append
│   └── settings_repository.dart   설정 + 익명 기기 키
│
├── notifications/
│   ├── notification_plan.dart     ★ 언제 무엇을 보낼지 (순수, 테스트됨)
│   ├── notification_backend.dart  인터페이스 + 문구 + Debug 구현
│   └── pending_actions.dart       백그라운드 액션 큐
│
├── providers/providers.dart       Riverpod. 모든 상태 변경의 진입점
├── l10n/app_localizations.dart    ko/en (코드 생성 없음)
└── ui/                            화면
```

`flutter_local_notifications` 는 **`notifications/` 안의 어댑터 한 파일에서만**
쓰입니다. 패키지 API 가 또 바뀌어도 나머지는 영향을 받지 않습니다.

---

## 핵심 알고리즘

```
interval = anchorDays × seasonAdjust × factor
```

| 항목 | 출처 |
|---|---|
| `anchorDays` | 사용자 입력 또는 (종류 × 광량) 테이블. 무정보 시 10일 |
| `seasonAdjust` | **달력**. 겨울이면 ×1.4 (다육 ×1.9) |
| `factor` | **학습되는 유일한 값.** 난방·화분 재질 같은 개인차만 흡수 |

계절을 factor 에게 배우게 하면 factor 가 계절 신호에 오염되어 정작
개인차를 못 배운다. 달력으로 아는 걸 데이터로 배울 이유가 없다.

### 다음 알림 날짜 ★

**기산점은 "마지막 알림"이 아니라 마지막 물 준 날이다.**
흙이 축축하다는 건 물을 안 줬다는 뜻이므로 시계가 리셋되지 않는다.

```dart
base       = lastWateredAt ?? createdAt
byInterval = base + interval
floor      = now + max(2, round(interval × 0.15))   // minSnooze
next       = 늦은 쪽
```

`now + interval` 로 구현하면 "축축해요"를 누를 때마다 시계가 리셋되어
알림이 무한정 밀린다. 반대로 `base + interval` 만 쓰면 연장 폭이 작을 때
다음 알림이 내일이 된다. 두 실수 모두 회귀 테스트로 막고 있다.

### 3버튼의 의미

| 버튼 | 물 줌? | factor | 기산점 |
|---|---|---|---|
| 축축했어요 | ✗ | 연장 | **유지** |
| 적당했어요 | ✓ | 유지, streak+1 | now |
| 바짝 말랐어요 | ✓ | 단축 | now |

---

## 사진은 어디에 저장되나

`Documents/photos/<uuid>.jpg` — 앱 문서 폴더입니다 (`lib/data/photo_store.dart`).
`image_picker` 가 주는 경로는 OS 임시·캐시 폴더라 언제든 비워질 수 있어서,
고른 사진을 문서 폴더로 복사해 두고 그 뒤로는 이 폴더만 봅니다. 문서 폴더를
고른 이유는 사진이 **다시 만들 수 없는 사용자 콘텐츠**라 기기 백업에 들어가야
하기 때문입니다.

**DB 에는 절대 경로가 아니라 파일 이름만 저장합니다.** iOS 앱 컨테이너 경로에는
UUID 가 들어 있고 그 UUID 는 앱 업데이트·백업 복원 때 바뀝니다. 절대 경로를
저장하면 업데이트 한 번에 모든 사진이 깨지는데, 눈에 안 띄고 한참 뒤에 터지는
종류의 버그라 테스트로 못을 박아 뒀습니다.

복사는 사진을 **고를 때가 아니라 저장할 때** 합니다. 고르자마자 복사하면 폼을
취소한 사진이 쓰레기로 남습니다. 사진을 바꿀 때는 새 파일을 먼저 쓰고 옛 파일을
나중에 지우므로, 복사가 실패해도 기존 사진이 살아남습니다.

v1.0 은 사진을 서버에 올리지 않습니다 — 올리는 순간 App Privacy 라벨의
"데이터 수집 안 함" 이 깨집니다. v1.1 돌봄 링크는 어차피 서버가 필요하고,
그때 여기서 쓰는 uuid 파일명이 그대로 스토리지 객체 키가 됩니다.

---

## 설계 메모

**왜 Drift 가 아니라 sqflite 인가.** 코드 생성(build_runner) 의존을 줄이려고
sqflite + 얇은 리포지토리로 시작했습니다. `PlantRepository` 인터페이스를
유지하면 나중에 Drift 로 갈아끼울 때 UI 와 도메인은 손대지 않아도 됩니다.

**왜 ARB 가 아닌가.** 같은 이유입니다. 문자열이 늘어나면 `flutter gen-l10n`
으로 옮기세요.

**왜 알림이 하루에 하나인가.** 알림 과부하 방지(제품 차별점)와 iOS 예약 상한
대응이 동시에 해결됩니다. iOS 는 앱당 예약 알림을 **64개**까지만 유지하고
초과분을 조용히 버립니다. 날짜당 1개 × 30일이면 최대 30개입니다.

---

## 플랫폼 설정

**iOS** — `ios/Runner/Info.plist` (사진·카메라 문구만 필요합니다)

`UIBackgroundModes` 는 넣지 않았습니다. 그건 푸시(remote-notification)용이고
로컬 알림은 액션 처리까지 포함해 요구하지 않습니다 — 쓰지도 않을 배경 모드를
선언하면 App Review 에서 용도를 되묻습니다.

대신 `AppDelegate.swift` 에 두 가지가 필요했습니다:
`UNUserNotificationCenter` delegate 지정과, 백그라운드 isolate 에 플러그인을
등록하는 `setPluginRegistrantCallback`. 이 앱은 UIScene 생명주기를 쓰므로
후자는 `didFinishLaunchingWithOptions` 가 아니라
`didInitializeImplicitFlutterEngine` 에 둡니다.

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>식물 사진을 등록하기 위해 사진 접근이 필요합니다.</string>
<key>NSCameraUsageDescription</key>
<string>식물 사진을 찍기 위해 카메라 접근이 필요합니다.</string>
```

**Android** — `android/app/src/main/AndroidManifest.xml` 의 `<manifest>` 안

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

`SCHEDULE_EXACT_ALARM` 은 일부러 넣지 않았습니다 (위 '현재 상태' 참고).

`<application>` 안에는 리시버 3종이 필요합니다 —
`ScheduledNotificationReceiver` 가 없으면 예약은 되는데 아무것도 뜨지 않고,
`ActionBroadcastReceiver` 가 없으면 액션 버튼이 먹통이 되며,
`ScheduledNotificationBootReceiver` 가 없으면 재부팅 후 예약이 사라집니다.

`res/raw/keep.xml` 도 함께 두었습니다. 알림 아이콘(`ic_notification`)은 Dart
문자열로만 참조하므로 R8 눈에는 미사용으로 보이고, 지워지면 알림이 **조용히**
실패합니다.

---

## 남은 작업

- [ ] 실기기에서 알림 액션 버튼 확인 (종료 / 백그라운드 / 잠금화면)
- [ ] 앱을 지웠다 깔거나 기기를 복원해도 사진이 따라오는지 실기기 확인
- [ ] 재부팅 후 예약이 복구되는지 확인
- [ ] 알림 문구 영어 — `NotificationCopy` 와 Android 채널 이름·설명이 아직
      한국어 하드코딩
- [ ] 식물 30개로 iOS 64개 상한 검증
- [ ] 기기 날짜를 12월로 바꿔 겨울 모드 전환 테스트
- [ ] 타임존을 `Australia/Sydney` 로 바꿔 남반구 테스트
- [ ] 90일 미응답 시 `decayStaleLearning` 호출 지점 연결
- [ ] 앱 아이콘 · 스플래시
