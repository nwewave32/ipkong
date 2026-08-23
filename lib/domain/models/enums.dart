/// 식물 종류 — 종 식별 대신 사용하는 3분류.
/// 초보자도 사진만 보고 100% 맞출 수 있는 수준으로 유지한다.
enum PlantKind {
  succulent, // 🌵 다육 · 선인장
  normal, // 🪴 일반 화분 식물
  thinLeaf, // 🌿 잎이 얇고 넓은 것 · 허브
}

/// 놓아둔 자리의 광량.
enum LightLevel {
  bright, // 밝은 창가
  medium, // 보통
  low, // 어두움
}

/// anchorDays 의 출처. 학습 강도를 결정한다.
///
/// [user] 는 사용자가 직접 주기를 입력한 경우로, 그 사람이 식물을 안다는
/// 신호이므로 factor 를 좁은 범위에서 작게만 움직인다.
enum AnchorSource { user, table }

/// 알림에 대한 사용자 응답 = 흙 상태.
///
/// [tooWet] 만 "물을 주지 않았다"는 뜻이며 기산점을 갱신하지 않는다.
enum SoilResponse {
  tooWet, // 축축했어요   → 물 안 줌, 주기 연장
  justRight, // 적당했어요   → 물 줌, 주기 유지
  tooDry, // 바짝 말랐어요 → 물 줌, 주기 단축
}

/// 물주기 이벤트 로그의 종류.
enum EventType {
  tooWet,
  justRight,
  tooDry,
  watered, // 알림 없이 직접 물을 준 경우
}

/// 이벤트를 기록한 주체. v1.1 돌봄 링크 대비.
enum Actor { owner, sitter }

/// 기후대. 겨울이 언제인지 (혹은 없는지) 결정한다.
enum Climate {
  northern, // 북반구 온대 — 11~2월이 겨울
  southern, // 남반구 온대 — 5~8월이 겨울
  tropical, // 열대 — 겨울 없음
}

extension SoilResponseX on SoilResponse {
  /// 물을 준 응답인가. [SoilResponse.tooWet] 만 false 다.
  bool get didWater => this != SoilResponse.tooWet;

  EventType get eventType => switch (this) {
        SoilResponse.tooWet => EventType.tooWet,
        SoilResponse.justRight => EventType.justRight,
        SoilResponse.tooDry => EventType.tooDry,
      };
}
