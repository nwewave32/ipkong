import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/models/enums.dart';
import '../l10n/app_localizations.dart';

/// 식물 추가 / 수정이 공유하는 입력 조각들.
///
/// 명세 §4.3 은 추가와 수정을 한 화면으로 묶어 기술한다. 두 화면이 같은
/// 질문을 다르게 묻기 시작하면 사용자는 수정하러 들어올 때마다 새 화면을
/// 배워야 한다. 위젯을 공유해 그럴 여지를 없앤다.

/// 사진 (선택). 탭하면 갤러리, 길게 누르면 카메라.
class PhotoField extends StatelessWidget {
  const PhotoField({
    required this.path,
    required this.onChanged,
    super.key,
  });

  final String? path;
  final ValueChanged<String?> onChanged;

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked != null) onChanged(picked.path);
  }

  /// 사진이 이미 있으면 바꿀지 지울지 먼저 묻는다. 지우기를 탭 한 번으로
  /// 두면 사진을 바꾸려던 사람이 실수로 지운다.
  Future<void> _onTap(BuildContext context) async {
    final s = AppStrings.of(context);
    if (path == null) {
      await _pick(ImageSource.gallery);
      return;
    }

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.photoFromGallery),
              onTap: () => Navigator.of(sheet).pop(_PhotoAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.photoFromCamera),
              onTap: () => Navigator.of(sheet).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(s.photoRemove),
              onTap: () => Navigator.of(sheet).pop(_PhotoAction.remove),
            ),
          ],
        ),
      ),
    );

    // null 은 시트를 그냥 닫은 경우다.
    if (action == null) return;
    switch (action) {
      case _PhotoAction.gallery:
        await _pick(ImageSource.gallery);
      case _PhotoAction.camera:
        await _pick(ImageSource.camera);
      case _PhotoAction.remove:
        onChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    final label = path == null ? s.photoOptional : s.photoChange;

    return Center(
      child: Column(
        children: [
          // 맨 GestureDetector 는 스크린 리더에 그냥 이미지로 읽힌다.
          // 버튼이라는 사실과 무엇을 하는 버튼인지를 직접 알려준다.
          Semantics(
            button: true,
            label: '${s.photo}, $label',
            child: InkWell(
              onTap: () => _onTap(context),
              customBorder: const CircleBorder(),
              child: ExcludeSemantics(
                child: CircleAvatar(
                  radius: 48,
                  backgroundImage: path == null ? null : FileImage(File(path!)),
                  child: path == null
                      ? const Icon(Icons.add_a_photo_outlined, size: 28)
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 위 버튼이 같은 문구를 이미 읽어준다. 두 번 읽지 않게 한다.
          ExcludeSemantics(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진 액션 시트의 선택지. 문자열 대신 타입으로 넘겨서, 오타가 나면
/// 조용히 아무 일도 안 일어나는 대신 컴파일이 깨지게 한다.
enum _PhotoAction { gallery, camera, remove }

/// 아이콘 + 라벨 3택. 종류(§4.3-3)와 위치(§4.3-4)가 함께 쓴다.
class ChoiceList<T> extends StatelessWidget {
  const ChoiceList({
    required this.value,
    required this.onChanged,
    required this.options,
    super.key,
  });

  final T value;
  final ValueChanged<T> onChanged;

  /// (값, 이모지, 라벨)
  final List<(T, String, String)> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((o) {
        final selected = o.$1 == value;
        return Card(
          color:
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            // 선택을 색과 체크 아이콘으로만 표시하면 스크린 리더 사용자는
            // 지금 무엇이 골라져 있는지 알 수 없다. ListTile 은 이 값을
            // Semantics(selected:) 로 넘겨준다.
            selected: selected,
            // selected 는 글자색을 primary 로 바꾸는데, 배경이 이미
            // primaryContainer 라 대비가 떨어진다. 짝이 맞는 색으로 고정한다.
            selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
            // 이모지는 장식이다. 읽어주면 "선인장 다육 · 선인장"이 된다.
            leading: ExcludeSemantics(
              child: Text(o.$2, style: const TextStyle(fontSize: 24)),
            ),
            title: Text(o.$3),
            trailing: selected
                ? const ExcludeSemantics(child: Icon(Icons.check))
                : null,
            onTap: () => onChanged(o.$1),
          ),
        );
      }).toList(),
    );
  }
}

/// 주기 — 빈 입력칸이 아니라 '미리 채워진 수정 가능한 제안값'.
/// 아는 사람은 고치고, 모르는 사람은 그냥 넘어간다.
class IntervalStepper extends StatelessWidget {
  const IntervalStepper({
    required this.days,
    required this.onChanged,
    super.key,
  });

  static const minDays = 2;
  static const maxDays = 60;

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(s.intervalLabel)),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed:
                  days <= minDays ? null : () => onChanged(days - 1),
            ),
            Text(
              s.days(days),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed:
                  days >= maxDays ? null : () => onChanged(days + 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// 종류·위치 선택지. 추가와 수정이 같은 순서·같은 이모지를 쓰게 한다.
List<(PlantKind, String, String)> kindOptions(AppStrings s) => [
      (PlantKind.succulent, '🌵', s.kindSucculent),
      (PlantKind.normal, '🪴', s.kindNormal),
      (PlantKind.thinLeaf, '🌿', s.kindThinLeaf),
    ];

List<(LightLevel, String, String)> lightOptions(AppStrings s) => [
      (LightLevel.bright, '☀️', s.lightBright),
      (LightLevel.medium, '⛅', s.lightMedium),
      (LightLevel.low, '🌥️', s.lightLow),
    ];
