import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/data/plant_repository.dart';

/// 내보내기에서 디바이스 키가 빠지는지 지킨다.
///
/// 이 파일이 지키는 건 스타일이 아니라 **되돌릴 수 없는 실수**다.
/// `device_id` 는 v1.1 돌봄 링크에서 계정 없이 소유자를 인증하는 열쇠고
/// (명세 §11), 내보낸 파일은 메일·드라이브로 나가라고 만든 물건이다.
/// 한 번 남에게 건너간 파일은 회수할 방법이 없으므로, 서버가 없는 지금
/// 시점부터 빠져 있어야 한다.
void main() {
  group('내보내기 이벤트 검열', () {
    test('device_id 가 제거된다', () {
      final rows = PlantRepository.redactEvents([
        {
          'id': 'e1',
          'plant_id': 'p1',
          'occurred_at': 1,
          'type': 0,
          'actor': 0,
          'device_id': 'secret-owner-key',
          'created_at': 1,
        },
      ]);

      expect(rows.single.containsKey('device_id'), isFalse);
      expect(rows.single.values, isNot(contains('secret-owner-key')));
    });

    test('사용자에게 필요한 값은 그대로 남는다', () {
      final rows = PlantRepository.redactEvents([
        {
          'id': 'e1',
          'plant_id': 'p1',
          'occurred_at': 1735689600000,
          'type': 1,
          'actor': 0,
          'device_id': 'secret',
          'created_at': 1735689600000,
        },
      ]);

      expect(rows.single, {
        'id': 'e1',
        'plant_id': 'p1',
        'occurred_at': 1735689600000,
        'type': 1,
        'actor': 0,
        'created_at': 1735689600000,
      });
    });

    test('행이 여러 개여도 모두 검열된다', () {
      final rows = PlantRepository.redactEvents([
        {'id': 'e1', 'device_id': 'a'},
        {'id': 'e2', 'device_id': 'b'},
        {'id': 'e3', 'device_id': 'c'},
      ]);

      expect(rows.every((r) => !r.containsKey('device_id')), isTrue);
      expect(rows.map((r) => r['id']), ['e1', 'e2', 'e3']);
    });

    test('원본 행을 건드리지 않는다', () {
      final original = <String, Object?>{'id': 'e1', 'device_id': 'a'};
      PlantRepository.redactEvents([original]);

      expect(
        original['device_id'],
        'a',
        reason: '검열은 사본에만 적용돼야 한다. DB 에서 읽은 행을 그대로 '
            '쓰는 다른 경로가 생기면 조용히 깨진다',
      );
    });
  });

  group('내보내기 식물 검열', () {
    test('photo_path 가 제거된다', () {
      // 사진 파일은 내보내기에 실리지 않는다. 파일 이름만 남기면 받는 쪽에서는
      // 있지도 않은 파일을 가리키는 쓸모없는 값이 된다.
      final rows = PlantRepository.redactPlants([
        {
          'id': 'p1',
          'name': '몬스테라',
          'photo_path': '3f1c0e5a-2b77-4f10-9a0f-0c9d1e2f3a4b.jpg',
          'anchor_days': 10.0,
        },
      ]);

      expect(rows.single.containsKey('photo_path'), isFalse);
      expect(rows.single['name'], '몬스테라');
      expect(rows.single['anchor_days'], 10.0);
    });
  });
}
