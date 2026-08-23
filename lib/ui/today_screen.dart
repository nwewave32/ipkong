import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../domain/watering_schedule.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'plant_detail_screen.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final today = ref.watch(todayPlantsProvider);
    final all = ref.watch(plantListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.tabToday)),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (_) => today.isEmpty
            ? _EmptyToday(strings: s)
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: today.length,
                itemBuilder: (_, i) => _TodayCard(plant: today[i]),
              ),
      ),
    );
  }
}

class _EmptyToday extends ConsumerWidget {
  const _EmptyToday({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plants = ref.watch(plantListProvider).value ?? const <Plant>[];
    final climate = ref.watch(climateProvider);
    final winter = ref.watch(winterModeProvider);
    final today = WateringSchedule.dateOnly(DateTime.now());

    int? soonest;
    for (final p in plants) {
      final due = WateringSchedule.nextNotifyDate(
        p,
        today,
        climate: climate,
        winterModeEnabled: winter,
      );
      final days = due.difference(today).inDays.clamp(0, 1 << 30);
      if (soonest == null || days < soonest) soonest = days;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🌿', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(strings.todayEmpty, style: Theme.of(context).textTheme.bodyLarge),
          if (soonest != null) ...[
            const SizedBox(height: 8),
            Text(
              strings.nextCheckIn(soonest),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.plant});

  final Plant plant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final notifier = ref.read(plantListProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _Avatar(path: plant.photoPath),
              title: Text(
                plant.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(plant.isSettled ? '' : s.soilQuestion),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlantDetailScreen(plantId: plant.id),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // 정착 전에는 흙 상태 3택, 정착 후에는 단순 2택.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: plant.isSettled
                  ? [
                      FilledButton(
                        onPressed: () => notifier.waterNow(plant.id),
                        child: Text(s.watered),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            notifier.respond(plant.id, SoilResponse.tooWet),
                        child: Text(s.stillMoist),
                      ),
                    ]
                  : [
                      OutlinedButton(
                        onPressed: () =>
                            notifier.respond(plant.id, SoilResponse.tooWet),
                        child: Text(s.tooWet),
                      ),
                      FilledButton(
                        onPressed: () =>
                            notifier.respond(plant.id, SoilResponse.justRight),
                        child: Text(s.justRight),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            notifier.respond(plant.id, SoilResponse.tooDry),
                        child: Text(s.tooDry),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return const CircleAvatar(radius: 24, child: Text('🪴'));
    }
    return CircleAvatar(radius: 24, backgroundImage: FileImage(File(path!)));
  }
}
