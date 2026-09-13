import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/data/photo_store.dart';

/// 사진 보관소.
///
/// 여기서 지키려는 건 두 가지다.
///
/// 1. **DB 에 들어가는 값에 경로가 섞이지 않는 것.** iOS 앱 컨테이너 경로에는
///    앱 업데이트·백업 복원 때 바뀌는 UUID 가 들어 있어서, 절대 경로를 저장하면
///    업데이트 한 번에 모든 사진이 깨진다. 눈에 띄지 않고 나중에 터지는 종류다.
/// 2. **남의 파일을 지우지 않는 것.** 저장소는 자기가 복사해 온 파일만 책임진다.
void main() {
  late Directory root;
  late PhotoStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ipkong_photo_test');
    store = PhotoStore(Directory('${root.path}/photos')..createSync());
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// 사진을 고른 직후의 상태 — 앱 바깥 임시 폴더에 놓인 파일.
  File pickedFile({String name = 'picked.jpg'}) {
    final file = File('${root.path}/tmp_$name')..createSync();
    file.writeAsBytesSync([1, 2, 3]);
    return file;
  }

  group('adopt — 고른 사진을 들인다', () {
    test('DB 에 들어가는 값에는 경로가 섞이지 않는다', () async {
      final name = await store.adopt(pickedFile().path);

      expect(name, isNotNull);
      expect(name, isNot(contains('/')), reason: '절대 경로가 저장되면 앱 업데이트 때 깨진다');
      expect(File('${store.dir!.path}/$name').existsSync(), isTrue);
    });

    test('원본을 옮기지 않고 복사한다', () async {
      // 원본은 OS 가 관리하는 임시 파일이다. 우리가 치울 물건이 아니다.
      final source = pickedFile();
      await store.adopt(source.path);
      expect(source.existsSync(), isTrue);
    });

    test('확장자를 지킨다', () async {
      final name = await store.adopt(pickedFile(name: 'shot.png').path);
      expect(name, endsWith('.png'));
    });

    test('확장자가 없으면 jpg 로 둔다', () async {
      final file = File('${root.path}/noext')..writeAsBytesSync([1]);
      expect(await store.adopt(file.path), endsWith('.jpg'));
    });

    test('이미 저장소의 파일이면 그대로 둔다', () async {
      final first = await store.adopt(pickedFile().path);

      // 이름만 고치려고 수정 화면에 들어온 경우다. 다시 복사하면 같은 사진이
      // 두 벌 쌓인다.
      expect(await store.adopt(first), first);
      expect(store.dir!.listSync(), hasLength(1));
    });

    test('사라진 파일은 사진 없음으로 떨어진다', () async {
      expect(await store.adopt('${root.path}/없는파일.jpg'), isNull);
      expect(await store.adopt(null), isNull);
    });

    test('보관소를 열지 못했으면 저장하지 않는다', () async {
      const broken = PhotoStore.unavailable();
      expect(await broken.adopt(pickedFile().path), isNull);
    });
  });

  group('fileFor — 그릴 파일을 찾는다', () {
    test('저장된 이름을 실제 파일로 되돌린다', () async {
      final name = await store.adopt(pickedFile().path);
      expect(store.fileFor(name)?.existsSync(), isTrue);
    });

    test('아직 저장 전인 임시 경로도 그릴 수 있다', () {
      // 폼은 저장 버튼을 누르기 전까지 임시 경로를 들고 있고, 그동안에도
      // 미리보기가 보여야 한다.
      final source = pickedFile();
      expect(store.fileFor(source.path)?.path, source.path);
    });

    test('사진이 없을 때만 null 이다', () {
      expect(store.fileFor(null), isNull);
      expect(store.fileFor(''), isNull);
    });

    test('파일이 있는지는 확인하지 않는다', () {
      // 이 메서드는 build 안에서 (그리드 셀마다, 프레임마다) 불린다. 여기서
      // existsSync 를 돌리면 UI 스레드에서 동기 파일 I/O 를 하게 된다.
      // 사라진 파일은 Image.errorBuilder 가 자리표시자로 받는다.
      final missing = store.fileFor('사라진이름.jpg');
      expect(missing, isNotNull);
      expect(missing!.existsSync(), isFalse);
    });

    test('보관소를 열지 못했으면 저장된 사진은 없는 것으로 본다', () {
      expect(const PhotoStore.unavailable().fileFor('a.jpg'), isNull);
    });
  });

  group('deleteQuietly', () {
    test('저장소의 파일을 지운다', () async {
      final name = await store.adopt(pickedFile().path);
      await store.deleteQuietly(name);
      expect(store.fileFor(name)!.existsSync(), isFalse);
    });

    test('저장소 바깥의 파일은 건드리지 않는다', () async {
      final source = pickedFile();
      await store.deleteQuietly(source.path);
      expect(source.existsSync(), isTrue, reason: '우리가 만들지 않은 파일이다');
    });

    test('없는 파일을 지워도 터지지 않는다', () async {
      // 정리 단계의 실패로 저장 결과를 뒤집지 않는다.
      await store.deleteQuietly('없는이름.jpg');
      await store.deleteQuietly(null);
    });
  });
}
