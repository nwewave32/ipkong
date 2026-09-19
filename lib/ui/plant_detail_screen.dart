import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../domain/models/watering_event.dart';
import '../domain/watering_schedule.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'edit_plant_screen.dart';

class PlantDetailScreen extends ConsumerWidget {
  const PlantDetailScreen({required this.plantId, super.key});

  final String plantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final plants = ref.watch(plantListProvider).value ?? const <Plant>[];
    final matches = plants.where((p) => p.id == plantId);
    final plant = matches.isEmpty ? null : matches.first;

    if (plant == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }

    final climate = ref.watch(climateProvider);
    final winter = ref.watch(winterModeProvider);
    final photo = ref.watch(photoStoreProvider).fileFor(plant.photoPath);
    final today = WateringSchedule.dateOnly(DateTime.now());
    final interval = WateringSchedule.nextInterval(
      plant,
      today,
      climate: climate,
      winterModeEnabled: winter,
    );
    final due = WateringSchedule.nextNotifyDate(
      plant,
      today,
      climate: climate,
      winterModeEnabled: winter,
    );
    final settleAt = plant.anchorSource == AnchorSource.user ? 2 : 3;

    return Scaffold(
      appBar: AppBar(
        title: Text(plant.name),
        actions: [
          IconButton(
            tooltip: s.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EditPlantScreen(plant: plant),
              ),
            ),
          ),
          IconButton(
            tooltip: s.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, plant),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                photo,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                // 파일이 사라졌으면 자리를 비운다 — 상세 화면에는 이미 이름과
                // 기록이 있어서 빈 액자를 보여줄 이유가 없다.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 16),

          // 배수 경고 — 주기 문제가 아니라 화분 문제라는 신호.
          if (WateringSchedule.suspectsDrainageIssue(plant))
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Text('💧', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.drainageWarning)),
                  ],
                ),
              ),
            ),

          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(s.intervalLabel),
                  trailing: Text(
                    s.days(interval),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  // 밀린 식물은 예정일이 과거일 수 있다. 오늘로 보여준다.
                  title: Text(
                    s.nextCheckIn(
                      due.difference(today).inDays.clamp(0, 1 << 30),
                    ),
                  ),
                  trailing: Text(s.date(due.isBefore(today) ? today : due)),
                ),
                ListTile(
                  title: Text(
                    plant.isSettled
                        ? s.settledDone
                        : s.settledHint(
                            (settleAt - plant.settledStreak)
                                .clamp(1, settleAt),
                          ),
                  ),
                  leading: Icon(
                    plant.isSettled
                        ? Icons.check_circle
                        : Icons.school_outlined,
                    color: plant.isSettled ? Colors.green : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: () =>
                ref.read(plantListProvider.notifier).waterNow(plant.id),
            icon: const Icon(Icons.water_drop_outlined),
            label: Text(s.waterNow),
          ),
          const SizedBox(height: 24),

          Text(s.history, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _History(plantId: plant.id),
        ],
      ),
    );
  }

  /// 삭제는 아이콘 한 번으로 끝나면 안 된다. 되돌릴 수 없는 유일한 동작이다.
  /// (실제로는 이벤트 로그 보존을 위해 아카이브하지만, 사용자에게는
  /// 되살릴 방법이 없으므로 삭제라고 말하는 편이 정직하다.)
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Plant plant,
  ) async {
    final s = AppStrings.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.deleteConfirmTitle),
        content: Text(s.deleteConfirmBody(plant.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(plantListProvider.notifier).archive(plant.id);
    navigator.pop();
  }
}

class _History extends ConsumerWidget {
  const _History({required this.plantId});

  final String plantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final repo = ref.watch(plantRepositoryProvider);

    return FutureBuilder<List<WateringEvent>>(
      future: repo.eventsFor(plantId),
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <WateringEvent>[];
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('—'),
          );
        }
        return Column(
          children: events.map((e) {
            // 답변 버튼과 **같은 문구·같은 이모지**를 쓴다. 기록을 훑는
            // 사람은 자기가 누른 버튼을 찾는 것이지 새 어휘를 배우려는 게
            // 아니다.
            final (icon, label) = switch (e.type) {
              EventType.tooWet => ('💧', s.tooWet),
              EventType.justRight => ('👌', s.justRight),
              EventType.tooDry => ('🏜️', s.tooDry),
              EventType.watered => ('🚿', s.watered),
            };
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(icon, style: const TextStyle(fontSize: 18)),
              title: Text(label),
              subtitle: Text(s.dateTime(e.occurredAt)),
            );
          }).toList(),
        );
      },
    );
  }
}
