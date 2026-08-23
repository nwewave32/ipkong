import 'enums.dart';

/// 식물 한 그루.
///
/// 학습되는 값은 [factor] 하나뿐이다. [anchorDays] 는 기준이고,
/// 계절 보정은 달력에서 오며, 개인차만 factor 가 흡수한다.
class Plant {
  const Plant({
    required this.id,
    required this.name,
    required this.kind,
    required this.light,
    required this.anchorDays,
    required this.anchorSource,
    required this.anchorInWinter,
    required this.createdAt,
    required this.updatedAt,
    this.photoPath,
    this.factor = 1.0,
    this.settledStreak = 0,
    this.isSettled = false,
    this.eventCount = 0,
    this.tooWetStreak = 0,
    this.lastWateredAt,
    this.lastRespondedAt,
    this.isArchived = false,
  });

  final String id; // UUID v4 — 서버 호환 대비
  final String name;
  final String? photoPath;

  final PlantKind kind;
  final LightLevel light;

  /// 기준 주기(일). 사용자가 입력했거나 테이블에서 온 값.
  final double anchorDays;
  final AnchorSource anchorSource;

  /// anchorDays 를 정한 시점이 겨울이었는가.
  /// 겨울에 입력한 값에 겨울 배율을 또 곱하는 이중 적용을 막는다.
  final bool anchorInWinter;

  /// 학습되는 유일한 값. 개인차(난방·화분 재질 등)를 흡수한다.
  final double factor;

  /// "적당했어요" 연속 횟수. 임계치에 닿으면 정착.
  final int settledStreak;

  /// 정착되면 흙 상태를 묻지 않고 단순 알림으로 전환한다.
  final bool isSettled;

  /// 초기 학습 스텝 크기를 결정한다 (3회 미만이면 크게).
  final int eventCount;

  /// "축축했어요" 연속 횟수. 3회 + factor 상한이면 배수 문제를 의심한다.
  final int tooWetStreak;

  /// ★ 주기의 기산점. null 이면 [createdAt] 을 쓴다.
  /// "축축했어요" 는 물을 준 게 아니므로 이 값을 갱신하지 않는다.
  final DateTime? lastWateredAt;

  /// 마지막으로 알림에 응답한 시각. 응답 종류와 무관하게 갱신된다.
  ///
  /// 최소 재확인 간격(minSnooze)의 기준점이다. 이걸 `now` 로 두면 조회할
  /// 때마다 예정일이 뒤로 밀려서 **밀린 식물의 알림이 영영 오지 않는다.**
  final DateTime? lastRespondedAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;

  /// 주기 계산의 기산점.
  DateTime get scheduleBase => lastWateredAt ?? createdAt;

  /// 최소 재확인 간격의 기준점.
  DateTime get snoozeBase => lastRespondedAt ?? scheduleBase;

  Plant copyWith({
    String? name,
    String? photoPath,
    bool clearPhotoPath = false,
    PlantKind? kind,
    LightLevel? light,
    double? anchorDays,
    AnchorSource? anchorSource,
    bool? anchorInWinter,
    double? factor,
    int? settledStreak,
    bool? isSettled,
    int? eventCount,
    int? tooWetStreak,
    DateTime? lastWateredAt,
    DateTime? lastRespondedAt,
    DateTime? updatedAt,
    bool? isArchived,
  }) {
    return Plant(
      id: id,
      name: name ?? this.name,
      photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
      kind: kind ?? this.kind,
      light: light ?? this.light,
      anchorDays: anchorDays ?? this.anchorDays,
      anchorSource: anchorSource ?? this.anchorSource,
      anchorInWinter: anchorInWinter ?? this.anchorInWinter,
      factor: factor ?? this.factor,
      settledStreak: settledStreak ?? this.settledStreak,
      isSettled: isSettled ?? this.isSettled,
      eventCount: eventCount ?? this.eventCount,
      tooWetStreak: tooWetStreak ?? this.tooWetStreak,
      lastWateredAt: lastWateredAt ?? this.lastWateredAt,
      lastRespondedAt: lastRespondedAt ?? this.lastRespondedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'photo_path': photoPath,
        'kind': kind.index,
        'light': light.index,
        'anchor_days': anchorDays,
        'anchor_source': anchorSource.index,
        'anchor_in_winter': anchorInWinter ? 1 : 0,
        'factor': factor,
        'settled_streak': settledStreak,
        'is_settled': isSettled ? 1 : 0,
        'event_count': eventCount,
        'too_wet_streak': tooWetStreak,
        'last_watered_at': lastWateredAt?.millisecondsSinceEpoch,
        'last_responded_at': lastRespondedAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'is_archived': isArchived ? 1 : 0,
      };

  factory Plant.fromMap(Map<String, Object?> m) {
    DateTime? ts(Object? v) => v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

    return Plant(
      id: m['id']! as String,
      name: m['name']! as String,
      photoPath: m['photo_path'] as String?,
      kind: PlantKind.values[(m['kind']! as num).toInt()],
      light: LightLevel.values[(m['light']! as num).toInt()],
      anchorDays: (m['anchor_days']! as num).toDouble(),
      anchorSource: AnchorSource.values[(m['anchor_source']! as num).toInt()],
      anchorInWinter: (m['anchor_in_winter']! as num).toInt() == 1,
      factor: (m['factor']! as num).toDouble(),
      settledStreak: (m['settled_streak']! as num).toInt(),
      isSettled: (m['is_settled']! as num).toInt() == 1,
      eventCount: (m['event_count']! as num).toInt(),
      tooWetStreak: (m['too_wet_streak']! as num).toInt(),
      lastWateredAt: ts(m['last_watered_at']),
      lastRespondedAt: ts(m['last_responded_at']),
      createdAt: ts(m['created_at'])!,
      updatedAt: ts(m['updated_at'])!,
      isArchived: (m['is_archived']! as num).toInt() == 1,
    );
  }
}
