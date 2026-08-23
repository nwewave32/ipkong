import 'enums.dart';

/// 물주기 이벤트. append-only 로만 쌓는다.
///
/// 상태(마지막 물 준 날)가 아니라 이벤트로 저장하는 이유:
///  - v1.1 돌봄 링크에서 대리인(sitter)의 기록을 병합할 수 있다
///  - 알고리즘을 고쳤을 때 과거 데이터로 재학습이 가능하다
///  - factor 는 언제든 이 로그로부터 재계산할 수 있다 (진실의 원천)
class WateringEvent {
  const WateringEvent({
    required this.id,
    required this.plantId,
    required this.occurredAt,
    required this.type,
    required this.deviceId,
    required this.createdAt,
    this.actor = Actor.owner,
  });

  final String id; // UUID
  final String plantId;
  final DateTime occurredAt;
  final EventType type;
  final Actor actor;
  final String deviceId; // 익명 기기 키
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'plant_id': plantId,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'type': type.index,
        'actor': actor.index,
        'device_id': deviceId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory WateringEvent.fromMap(Map<String, Object?> m) => WateringEvent(
        id: m['id']! as String,
        plantId: m['plant_id']! as String,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          (m['occurred_at']! as num).toInt(),
        ),
        type: EventType.values[(m['type']! as num).toInt()],
        actor: Actor.values[(m['actor']! as num).toInt()],
        deviceId: m['device_id']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (m['created_at']! as num).toInt(),
        ),
      );
}
