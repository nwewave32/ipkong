import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../domain/watering_schedule.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'plant_form_fields.dart';

/// 식물 수정 (명세 §4.3 — 추가와 같은 화면 구성).
///
/// 추가 화면과 다른 점은 두 가지뿐이다.
///
/// 1. **주기 스테퍼가 anchor 가 아니라 지금 적용 중인 주기를 보여준다.**
///    상세 화면이 "물주기 12일"이라고 말해놓고 수정 화면을 열었더니 10일이면
///    사용자는 둘 중 뭐가 진짜인지 알 수 없다. 겨울 배율과 학습된 factor 가
///    이미 곱해진 값, 즉 실제로 알림이 오는 간격을 보여주고 그 값을 고치게
///    한다. 저장할 때 [WateringSchedule.setUserInterval] 이 고른 값이 곧
///    다음 주기가 되도록 factor 와 anchorInWinter 를 맞춰준다.
///
/// 2. **바뀐 항목만 저장한다.** 이름만 고치러 들어온 사람의 학습값을
///    날리지 않기 위해서다. 주기는 스테퍼를 실제로 누른 경우에만 넘긴다.
class EditPlantScreen extends ConsumerStatefulWidget {
  const EditPlantScreen({required this.plant, super.key});

  final Plant plant;

  @override
  ConsumerState<EditPlantScreen> createState() => _EditPlantScreenState();
}

class _EditPlantScreenState extends ConsumerState<EditPlantScreen> {
  late final TextEditingController _nameController;
  late PlantKind _kind;
  late LightLevel _light;
  late String? _photoPath;

  bool _intervalEdited = false;
  late int _intervalDays;

  Plant get _plant => widget.plant;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _plant.name);
    _kind = _plant.kind;
    _light = _plant.light;
    _photoPath = _plant.photoPath;
    _intervalDays = _effectiveInterval(_plant);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 지금 실제로 적용 중인 주기(일). 상세 화면이 보여주는 것과 같은 값이다.
  int _effectiveInterval(Plant p) => WateringSchedule.nextInterval(
    p,
    DateTime.now(),
    climate: ref.read(climateProvider),
    winterModeEnabled: ref.read(winterModeProvider),
  );

  /// 종류·위치를 바꾸면 주기 제안값도 따라 움직인다.
  /// 저장 시 돌 계산을 그대로 미리 돌려 보여준다 — 화면의 숫자와 저장 결과가
  /// 어긋나지 않게 하는 가장 확실한 방법이다.
  void _syncSuggestion() {
    if (_intervalEdited) return;
    final projected = WateringSchedule.reclassify(
      _plant,
      kind: _kind,
      light: _light,
      now: DateTime.now(),
    );
    setState(() => _intervalDays = _effectiveInterval(projected));
  }

  bool get _photoRemoved => _photoPath == null && _plant.photoPath != null;

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final typed = _nameController.text.trim();

    await ref
        .read(plantListProvider.notifier)
        .editPlant(
          plantId: _plant.id,
          name: typed.isEmpty ? s.plantNameHint : typed,
          kind: _kind,
          light: _light,
          userIntervalDays: _intervalEdited ? _intervalDays.toDouble() : null,
          photoPath: _photoPath,
          clearPhoto: _photoRemoved,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final relearns =
        !_intervalEdited &&
        (_kind != _plant.kind || _light != _plant.light) &&
        _plant.isSettled;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.editPlant),
        actions: [TextButton(onPressed: _save, child: Text(s.save))],
      ),
      // Scaffold 는 body 에 하단 안전영역을 넣어주지 않는다. 그대로 두면
      // 마지막 안내 문구가 홈 인디케이터에 깔린다.
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PhotoField(
              path: _photoPath,
              onChanged: (p) => setState(() => _photoPath = p),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: s.plantName,
                hintText: s.plantNameHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            Text(s.kindQuestion, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ChoiceList<PlantKind>(
              value: _kind,
              onChanged: (v) {
                setState(() => _kind = v);
                _syncSuggestion();
              },
              options: kindOptions(s),
            ),
            const SizedBox(height: 24),

            Text(
              s.lightQuestion,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ChoiceList<LightLevel>(
              value: _light,
              onChanged: (v) {
                setState(() => _light = v);
                _syncSuggestion();
              },
              options: lightOptions(s),
            ),
            const SizedBox(height: 24),

            IntervalStepper(
              days: _intervalDays,
              onChanged: (v) => setState(() {
                _intervalDays = v;
                _intervalEdited = true;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              _intervalEdited ? s.intervalUserNote : s.intervalCurrentNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),

            // 정착된 식물의 자리를 옮기면 다시 흙 상태를 묻게 된다.
            // 저장하고 나서 알게 되면 고장으로 보이므로 미리 말해둔다.
            if (relearns) ...[
              const SizedBox(height: 16),
              _Note(text: s.relocateResetsSettling),
            ],
            if (_intervalEdited) ...[
              const SizedBox(height: 16),
              _Note(text: s.intervalOverrideWarning),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
