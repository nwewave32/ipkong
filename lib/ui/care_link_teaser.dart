import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// v1.1 돌봄 위탁 링크 예고 티저.
///
/// 기능은 아직 없지만 곧 나온다는 사실은 알린다. 강요하지 않는다 —
/// 홈 화면 배너나 팝업으로 가로막지 않고, 설정 안에 조용히 둔다.
///
/// ⚠️ 관심 표시는 **로컬 플래그로만** 저장한다. 서버로 보내면
/// "데이터 수집 안 함" 프라이버시 라벨이 깨진다. 수요 데이터는 포기하되,
/// v1.1 업데이트 후 첫 실행 때 이 플래그를 읽어 안내한다.
///
/// ⚠️ 스토어 설명·스크린샷에는 이 기능을 넣지 않는다. 미출시 기능을
/// 스토어 메타데이터에 홍보하면 심사 리젝 사유가 될 수 있다.
class CareLinkTeaser extends ConsumerStatefulWidget {
  const CareLinkTeaser({super.key});

  @override
  ConsumerState<CareLinkTeaser> createState() => _CareLinkTeaserState();
}

class _CareLinkTeaserState extends ConsumerState<CareLinkTeaser> {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final settings = ref.watch(settingsRepositoryProvider);
    final interested = settings.interestedInCareLink;

    return Card(
      // 설정 행·섹션 라벨의 좌우 여백(16)과 같은 선에 카드 모서리를 맞춘다.
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('✈️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.careLinkTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(s.careLinkBody,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 폰 폭(393pt)에서 버튼과 나란히 두면 1.5px 넘친다.
                // 문구가 남은 폭 안에서 접히게 한다.
                Expanded(
                  child: Text(
                    s.careLinkNextUpdate,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 12),
                if (interested)
                  Text(
                    s.careLinkNoted,
                    style: Theme.of(context).textTheme.labelSmall,
                  )
                else
                  OutlinedButton(
                    onPressed: () async {
                      await settings.setInterestedInCareLink(true);
                      if (mounted) setState(() {});
                    },
                    child: Text(s.careLinkNotifyMe),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
