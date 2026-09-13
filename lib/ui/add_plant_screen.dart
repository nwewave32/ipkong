import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/watering_schedule.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'plant_form_fields.dart';

class AddPlantScreen extends ConsumerStatefulWidget {
  const AddPlantScreen({super.key});

  @override
  ConsumerState<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends ConsumerState<AddPlantScreen> {
  final _nameController = TextEditingController();
  PlantKind _kind = PlantKind.normal;
  LightLevel _light = LightLevel.medium;
  String? _photoPath;

  /// 사용자가 제안값을 고쳤는가. 고쳤다면 anchorSource = user 가 된다.
  bool _intervalEdited = false;
  int _intervalDays = WateringSchedule.defaultAnchorDays.round();

  @override
  void initState() {
    super.initState();
    _syncSuggestion();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 종류·위치가 바뀌면 제안값을 다시 계산한다.
  /// 사용자가 이미 직접 고쳤다면 건드리지 않는다.
  void _syncSuggestion() {
    if (_intervalEdited) return;
    setState(() {
      _intervalDays = WateringSchedule.baselineDays(_kind, _light).round();
    });
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final typed = _nameController.text.trim();
    // 화면을 닫은 뒤에 띄우므로 messenger 를 미리 잡아 둔다.
    final messenger = ScaffoldMessenger.of(context);

    final outcome = await ref
        .read(plantListProvider.notifier)
        .addPlant(
          name: typed.isEmpty ? s.plantNameHint : typed,
          kind: _kind,
          light: _light,
          // 고치지 않았으면 테이블 값이므로 null 을 넘겨 anchorSource=table 로 둔다.
          userIntervalDays: _intervalEdited ? _intervalDays.toDouble() : null,
          photoPath: _photoPath,
        );
    if (mounted) Navigator.of(context).pop();

    // 사진만 실패했으면 저장은 그대로 두되 조용히 넘어가지는 않는다 —
    // 사용자는 사진을 넣은 줄 알고 화면을 떠난다.
    if (outcome == SaveOutcome.savedWithoutPhoto) {
      messenger.showSnackBar(SnackBar(content: Text(s.photoSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.addPlant),
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
              file: ref.watch(photoStoreProvider).fileFor(_photoPath),
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

            // Q1. 종류 — 종 식별 대신 아이콘 3택
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

            // Q2. 위치
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
              _intervalEdited ? s.intervalUserNote : s.intervalSuggestedNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
