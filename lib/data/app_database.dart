import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// sqflite 초기화 + 마이그레이션.
///
/// 설계 메모: 명세서는 Drift 를 적었으나 스캐폴딩 단계에서는 코드 생성
/// (build_runner) 의존을 하나 줄이기 위해 sqflite + 얇은 리포지토리로
/// 시작한다. 리포지토리 인터페이스를 그대로 두면 나중에 Drift 로
/// 갈아끼울 때 UI/도메인 코드는 손대지 않아도 된다.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'ipkong.db';

  /// 스키마 버전.
  ///
  /// v2 — `plants.last_responded_at` 추가 (minSnooze 하한의 기준점).
  ///      이걸 올리지 않으면 이미 앱을 실행한 기기에서 `onCreate` 도
  ///      `onUpgrade` 도 돌지 않아 컬럼 없이 남고, 쓰기가 전부 실패한다.
  static const _version = 2;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // 단계별로 누적 적용한다. 버전을 건너뛴 기기도 순서대로 따라온다.
        if (oldVersion < 2) await _migrateTo2(db);
      },
    );
  }

  Future<void> _createV1(Database db) async {
    // 모든 엔티티에 UUID 와 updated_at 를 둔다.
    // 나중에 돌봄 링크(v1.1)로 서버 동기화를 붙일 때 마이그레이션 지옥을
    // 피하기 위한 것으로, v1 에서는 쓰이지 않아도 반드시 넣어둔다.
    await db.execute('''
      CREATE TABLE plants (
        id                TEXT    PRIMARY KEY,
        name              TEXT    NOT NULL,
        photo_path        TEXT,
        kind              INTEGER NOT NULL,
        light             INTEGER NOT NULL,
        anchor_days       REAL    NOT NULL,
        anchor_source     INTEGER NOT NULL,
        anchor_in_winter  INTEGER NOT NULL DEFAULT 0,
        factor            REAL    NOT NULL DEFAULT 1.0,
        settled_streak    INTEGER NOT NULL DEFAULT 0,
        is_settled        INTEGER NOT NULL DEFAULT 0,
        event_count       INTEGER NOT NULL DEFAULT 0,
        too_wet_streak    INTEGER NOT NULL DEFAULT 0,
        last_watered_at   INTEGER,
        last_responded_at INTEGER,
        created_at        INTEGER NOT NULL,
        updated_at        INTEGER NOT NULL,
        is_archived       INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // append-only. UPDATE / DELETE 하지 않는다.
    await db.execute('''
      CREATE TABLE watering_events (
        id          TEXT    PRIMARY KEY,
        plant_id    TEXT    NOT NULL,
        occurred_at INTEGER NOT NULL,
        type        INTEGER NOT NULL,
        actor       INTEGER NOT NULL DEFAULT 0,
        device_id   TEXT    NOT NULL,
        created_at  INTEGER NOT NULL,
        FOREIGN KEY (plant_id) REFERENCES plants (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_events_plant ON watering_events (plant_id, occurred_at)',
    );
    await db.execute(
      'CREATE INDEX idx_plants_active ON plants (is_archived, created_at)',
    );
  }

  /// v1 → v2 : minSnooze 하한의 기준점을 추가한다.
  ///
  /// 기존 식물은 null 로 남고, 그때는 [Plant.scheduleBase] 가 대신 쓰이므로
  /// 동작에 문제가 없다. 다음 응답 때부터 값이 채워진다.
  Future<void> _migrateTo2(Database db) async {
    await db.execute(
      'ALTER TABLE plants ADD COLUMN last_responded_at INTEGER',
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
