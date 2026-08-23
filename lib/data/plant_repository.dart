import 'package:uuid/uuid.dart';

import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../domain/models/watering_event.dart';
import 'app_database.dart';

class PlantRepository {
  PlantRepository(this._db, this._deviceId);

  final AppDatabase _db;
  final String _deviceId;
  static const _uuid = Uuid();

  Future<List<Plant>> listActive() async {
    final db = await _db.database;
    final rows = await db.query(
      'plants',
      where: 'is_archived = 0',
      orderBy: 'created_at ASC',
    );
    return rows.map(Plant.fromMap).toList();
  }

  Future<Plant?> findById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'plants',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Plant.fromMap(rows.first);
  }

  Future<Plant> create({
    required String name,
    required PlantKind kind,
    required LightLevel light,
    required double anchorDays,
    required AnchorSource anchorSource,
    required bool anchorInWinter,
    String? photoPath,
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();
    final plant = Plant(
      id: _uuid.v4(),
      name: name,
      photoPath: photoPath,
      kind: kind,
      light: light,
      anchorDays: anchorDays,
      anchorSource: anchorSource,
      anchorInWinter: anchorInWinter,
      createdAt: ts,
      updatedAt: ts,
    );
    final db = await _db.database;
    await db.insert('plants', plant.toMap());
    return plant;
  }

  Future<void> update(Plant plant) async {
    final db = await _db.database;
    await db.update(
      'plants',
      plant.toMap(),
      where: 'id = ?',
      whereArgs: [plant.id],
    );
  }

  /// 삭제 대신 아카이브한다. 이벤트 로그를 보존하기 위해서다.
  Future<void> archive(String id) async {
    final db = await _db.database;
    await db.update(
      'plants',
      {'is_archived': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteForever(String id) async {
    final db = await _db.database;
    await db.delete('plants', where: 'id = ?', whereArgs: [id]);
  }

  /// 이벤트는 append 만 한다. 절대 수정·삭제하지 않는다.
  Future<void> appendEvent({
    required String plantId,
    required EventType type,
    DateTime? occurredAt,
    Actor actor = Actor.owner,
  }) async {
    final ts = occurredAt ?? DateTime.now();
    final event = WateringEvent(
      id: _uuid.v4(),
      plantId: plantId,
      occurredAt: ts,
      type: type,
      actor: actor,
      deviceId: _deviceId,
      createdAt: DateTime.now(),
    );
    final db = await _db.database;
    await db.insert('watering_events', event.toMap());
  }

  Future<List<WateringEvent>> eventsFor(String plantId, {int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      'watering_events',
      where: 'plant_id = ?',
      whereArgs: [plantId],
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(WateringEvent.fromMap).toList();
  }

  /// 내보내기에서 지우는 내부 전용 컬럼.
  ///
  /// `device_id` 는 v1.1 돌봄 링크에서 **계정 없이 소유자를 인증하는 열쇠**다
  /// (명세 §11). 내보낸 파일은 메일·드라이브·에어드롭으로 나가라고 만든
  /// 물건이라, 이 값이 실려 있으면 파일을 받은 사람이 곧 주인이 된다.
  /// 서버가 없는 v1.0 에서는 아무 일도 일어나지 않지만, **오늘 내보낸 파일은
  /// v1.1 이 나온 뒤에도 남아 있고 이미 보낸 파일은 되돌릴 수 없다.**
  ///
  /// 사용자에게는 어차피 의미 없는 값이므로 빼도 백업의 가치는 그대로다.
  static const redactedEventColumns = {'device_id'};

  /// 이벤트 행에서 [redactedEventColumns] 를 걷어낸다.
  ///
  /// DB 없이 검증할 수 있도록 순수 함수로 분리해 뒀다.
  static List<Map<String, Object?>> redactEvents(
    List<Map<String, Object?>> rows,
  ) =>
      rows
          .map(
            (r) => {...r}
              ..removeWhere((k, _) => redactedEventColumns.contains(k)),
          )
          .toList();

  /// 데이터 내보내기. 서버가 없으므로 사용자 보호 장치로 반드시 제공한다.
  Future<Map<String, Object?>> exportAll() async {
    final db = await _db.database;
    final plants = await db.query('plants');
    final events = await db.query('watering_events');
    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'plants': plants,
      'watering_events': redactEvents(events),
    };
  }
}
