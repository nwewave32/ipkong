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

앱은 동작하고 테스트도 돌아가지만, **실기기 알림은 아직 나가지 않습니다.**

`flutter_local_notifications` 22.x 는 `zonedSchedule` 이 플랫폼별 플러그인으로
옮겨가고 인자도 전부 named 로 바뀌어서, 그 어댑터 한 파일만 비워 두었습니다.
지금은 `DebugNotificationBackend` 가 붙어 있어 예약 내용을 콘솔에 찍습니다.

붙이는 방법:

1. `lib/notifications/local_notification_backend.dart` 에 `NotificationBackend`
   구현체를 만든다 (필요한 문구·액션은 `NotificationCopy` 에 이미 있습니다)
2. `lib/main.dart` 의 아래 한 줄만 바꾼다

```dart
final NotificationBackend backend = DebugNotificationBackend();
//                                  ^^^^^^^^^^^^^^^^^^^^^^^^ → LocalNotificationBackend()
```

**어떤 날짜에 무엇을 보낼지 정하는 로직은 이미 완성되어 있고 테스트도
통과합니다** (`notification_plan.dart`). 어댑터는 그 계획을 플랫폼 API 로
옮기기만 하면 됩니다.

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

**iOS** — `ios/Runner/Info.plist`

```xml
<key>UIBackgroundModes</key>
<array><string>remote-notification</string></array>
<key>NSPhotoLibraryUsageDescription</key>
<string>식물 사진을 등록하기 위해 사진 접근이 필요합니다.</string>
<key>NSCameraUsageDescription</key>
<string>식물 사진을 찍기 위해 카메라 접근이 필요합니다.</string>
```

**Android** — `android/app/src/main/AndroidManifest.xml` 의 `<manifest>` 안

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

---

## 남은 작업

- [ ] `LocalNotificationBackend` 구현 (위 '현재 상태' 참고)
- [ ] 실기기에서 알림 액션 버튼 확인 (종료 / 백그라운드 / 잠금화면)
- [ ] 식물 30개로 iOS 64개 상한 검증
- [ ] 기기 날짜를 12월로 바꿔 겨울 모드 전환 테스트
- [ ] 타임존을 `Australia/Sydney` 로 바꿔 남반구 테스트
- [ ] 사진을 앱 문서 폴더로 복사 (현재는 `image_picker` 임시 경로를 그대로 저장)
- [ ] 90일 미응답 시 `decayStaleLearning` 호출 지점 연결
- [ ] 앱 아이콘 · 스플래시
