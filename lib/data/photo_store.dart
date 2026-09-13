import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 식물 사진의 보관소.
///
/// `image_picker` 가 돌려주는 경로는 OS 임시·캐시 폴더를 가리킨다. 저장공간이
/// 빠듯해지면 OS 가 예고 없이 비우고, 기기 백업에도 들어가지 않는다. 그래서
/// 고른 사진을 **앱 문서 폴더로 복사해** 두고, 그 뒤로는 이 폴더만 본다.
///
/// DB 에는 절대 경로가 아니라 **파일 이름만** 저장한다. iOS 앱 컨테이너 경로에는
/// UUID 가 들어 있고(`/var/mobile/Containers/Data/Application/<UUID>/…`),
/// 그 UUID 는 앱 업데이트나 백업 복원 때 바뀐다. 절대 경로를 넣어 두면
/// 업데이트 한 번에 모든 사진이 깨진다.
///
/// v1.1 에서 돌봄 링크가 사진을 서버로 올리게 되면, 여기서 쓰는 uuid 파일명이
/// 그대로 스토리지 객체 키가 된다 — 마이그레이션 없이 원격 구현을 덧붙일 수
/// 있도록 이름 규칙을 지금 맞춰 둔다.
class PhotoStore {
  const PhotoStore(this.dir);

  /// 폴더를 열지 못한 경우. 사진은 "없는 것"으로 취급하고 앱은 계속 돈다 —
  /// 사진은 부가 정보이고, 이것 때문에 물주기 앱이 멈추면 안 된다.
  const PhotoStore.unavailable() : dir = null;

  /// 사진을 두는 폴더. null 이면 쓸 수 없는 상태다 (테스트, 초기화 실패).
  final Directory? dir;

  static const _folderName = 'photos';

  /// 문서 폴더 아래에 사진 폴더를 준비한다.
  ///
  /// 문서 폴더를 고르는 이유는 사진이 **다시 만들 수 없는 사용자 콘텐츠**라
  /// 백업에 들어가야 하기 때문이다. 캐시나 지원 폴더는 OS 가 비울 수 있다.
  static Future<PhotoStore> open() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$_folderName');
      if (!dir.existsSync()) await dir.create(recursive: true);
      return PhotoStore(dir);
    } catch (e) {
      debugPrint('[ipkong] 사진 폴더를 열지 못했습니다 — 사진 없이 진행합니다: $e');
      return const PhotoStore.unavailable();
    }
  }

  /// 화면에 그릴 파일. 사진이 없으면 null 이다.
  ///
  /// [value] 는 두 가지 중 하나다:
  ///  - 저장소가 관리하는 **파일 이름** (DB 에서 읽은 값)
  ///  - 방금 고른 **임시 절대 경로** (폼이 아직 저장 전인 값)
  ///
  /// 폼은 저장하기 전까지 임시 경로를 들고 있으므로 둘 다 그릴 수 있어야 한다.
  /// 사진을 고르자마자 복사해 버리면 사용자가 취소했을 때 쓰레기 파일이 남는다.
  ///
  /// **파일이 실제로 있는지는 확인하지 않는다.** 이 메서드는 `build` 안에서
  /// 불리므로(그리드 셀마다, 프레임마다) 여기서 `existsSync` 를 돌리면 UI
  /// 스레드에서 동기 파일 I/O 를 하게 된다. 파일이 사라졌거나 깨진 경우는
  /// `Image.errorBuilder` / `CircleAvatar.onForegroundImageError` 가 받아서
  /// 자리표시자를 보여준다 — 프레임워크가 비동기로 이미 하는 일이고,
  /// 존재 확인만으로는 못 잡는 '파일은 있는데 깨진' 경우까지 덮는다.
  File? fileFor(String? value) => _resolve(value);

  /// 폼이 들고 있던 값을 영구 저장소로 들인다. 돌려주는 값이 DB 에 들어간다.
  ///
  /// 이미 저장소의 파일이면 그대로 둔다 — 이름만 고치려고 수정 화면에 들어온
  /// 사람의 사진을 괜히 다시 복사하지 않는다.
  Future<String?> adopt(String? value) async {
    if (value == null || value.isEmpty) return null;
    if (_isStoredName(value)) return value;

    final directory = dir;
    if (directory == null) return null;

    final source = File(value);
    if (!source.existsSync()) return null;

    // 식물 id 가 아니라 사진마다 새 이름을 쓴다. 사진을 바꿀 때 새 파일을 먼저
    // 쓰고 나중에 옛 파일을 지우므로, 복사가 실패해도 기존 사진이 살아남는다.
    final name = '${const Uuid().v4()}${_extensionOf(value)}';
    try {
      await source.copy('${directory.path}/$name');
      return name;
    } catch (e) {
      debugPrint('[ipkong] 사진 복사 실패 — 사진 없이 저장합니다: $e');
      return null;
    }
  }

  /// 저장소가 관리하는 파일을 지운다.
  ///
  /// 정리 단계의 실패로 저장 결과를 뒤집지는 않는다. 최악이라도 쓰지 않는
  /// 파일 하나가 남을 뿐이다.
  Future<void> deleteQuietly(String? value) async {
    if (value == null || !_isStoredName(value)) return;
    final file = _resolve(value);
    if (file == null) return;
    try {
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('[ipkong] 사진 삭제 실패: $e');
    }
  }

  File? _resolve(String? value) {
    if (value == null || value.isEmpty) return null;
    if (!_isStoredName(value)) return File(value);
    final directory = dir;
    return directory == null ? null : File('${directory.path}/$value');
  }

  /// 이름만 있으면 저장소의 것, 경로가 섞여 있으면 아직 바깥의 임시 파일이다.
  static bool _isStoredName(String value) => !value.contains('/');

  /// 확장자를 지킨다 — 갤러리에서 온 PNG·HEIC 를 `.jpg` 로 둔갑시키면
  /// 나중에 파일을 다룰 때 형식과 이름이 어긋난다.
  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot <= path.lastIndexOf('/') || dot == path.length - 1) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    return ext.length <= 5 ? ext : '.jpg';
  }
}
