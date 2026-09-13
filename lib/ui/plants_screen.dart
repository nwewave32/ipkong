import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/watering_schedule.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'add_plant_screen.dart';
import 'plant_detail_screen.dart';

class PlantsScreen extends ConsumerWidget {
  const PlantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final plants = ref.watch(plantListProvider);
    final photos = ref.watch(photoStoreProvider);
    final climate = ref.watch(climateProvider);
    final winter = ref.watch(winterModeProvider);
    final today = WateringSchedule.dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(s.tabPlants),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddPlantScreen()),
            ),
          ),
        ],
      ),
      body: plants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🪴', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AddPlantScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(s.addPlant),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final plant = list[i];
              final due = WateringSchedule.nextNotifyDate(
                plant,
                today,
                climate: climate,
                winterModeEnabled: winter,
              );
              final dday = due.difference(today).inDays;
              final photo = photos.fileFor(plant.photoPath);

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlantDetailScreen(plantId: plant.id),
                  ),
                ),
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          // 파일이 사라졌거나 깨졌으면 자리표시자로 떨어진다.
                          // 그리기 전에 존재를 확인하지 않는 이유는
                          // [PhotoStore.fileFor] 주석 참고.
                          child: photo == null
                              ? const _PhotoPlaceholder()
                              : Image.file(
                                  photo,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const _PhotoPlaceholder(),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    plant.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (plant.isSettled)
                                  const Icon(Icons.check_circle,
                                      size: 14, color: Colors.green),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dday <= 0 ? 'D-Day' : 'D-$dday',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 사진이 없거나 읽지 못했을 때의 자리.
class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Center(child: Text('🪴', style: TextStyle(fontSize: 40))),
    );
  }
}
