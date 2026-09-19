import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/enums.dart';
import 'notification_backend.dart';

/// 백그라운드 isolate 에서 처리하지 못한 알림 액션을 쌓아두는 큐.
///
/// 백그라운드에서 DB 를 직접 건드리는 대신 SharedPreferences 에만 적어두고,
/// 앱이 다음에 열릴 때 [drain] 이 비우면서 반영한다.
///
/// ⚠️ **여기는 isolate 두 개가 같은 저장소를 본다.** `SharedPreferences` 는
/// isolate 마다 메모리 캐시를 들고 있고, `getInstance()` 는 그 캐시를 돌려준다.
/// 앱의 인스턴스는 `main()` 에서 한 번 만들어진 뒤 그대로이므로, 백그라운드
/// isolate 가 적은 값을 **그냥 읽으면 보이지 않는다.** 그래서 읽기 전에 반드시
/// [SharedPreferences.reload] 로 네이티브 저장소를 다시 읽어야 한다.
///
/// 이걸 빠뜨리면 증상이 고약하다. 잠금화면에서 "축축했어요" 를 누르고 앱을
/// 열면 그 식물이 여전히 미응답으로 보여 한 번 더 답하게 되고, 다음 콜드
/// 스타트에서 묵혀둔 큐가 그제서야 반영되면서 **같은 응답이 두 번 적용된다.**
/// 학습 factor 와 축축 연속 카운트가 조용히 틀어진다.
class PendingActions {
  const PendingActions._();

  static const _key = 'pending_notification_actions';

  static Future<void> enqueue(String actionId, String payload) async {
    final prefs = await SharedPreferences.getInstance();
    // 읽고-고쳐-쓰기 전에 최신 상태를 가져온다. 이 isolate 가 재사용되는 동안
    // 앱 쪽에서 큐를 비웠을 수 있고, 낡은 캐시로 덮어쓰면 그 삭제가 되살아난다.
    await prefs.reload();
    final queue = prefs.getStringList(_key) ?? <String>[];
    queue.add(
      jsonEncode({
        'action': actionId,
        'payload': payload,
        'at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    await prefs.setStringList(_key, queue);
  }

  static Future<List<PendingAction>> drain() async {
    final prefs = await SharedPreferences.getInstance();
    // 백그라운드 isolate 가 적어둔 값은 이 한 줄이 없으면 보이지 않는다.
    // 클래스 주석 참고 — 빠뜨리면 응답이 중복 적용된다.
    await prefs.reload();
    final raw = prefs.getStringList(_key) ?? <String>[];
    if (raw.isEmpty) return const [];
    await prefs.remove(_key);

    final out = <PendingAction>[];
    for (final line in raw) {
      try {
        final m = jsonDecode(line) as Map<String, Object?>;
        final action = parse(m['action']! as String, m['payload']! as String);
        if (action != null) out.add(action);
      } catch (e) {
        debugPrint('[ipkong] failed to parse pending action: $e');
      }
    }
    return out;
  }

  /// 알림 액션 하나를 도메인 의미로 해석한다.
  /// 묶음(digest) 알림에는 액션이 없으므로 식물이 하나일 때만 유효하다.
  static PendingAction? parse(String actionId, String payload) {
    final plantId = singlePlantIdFrom(payload);
    if (plantId == null) return null;
    return PendingAction(
      plantId: plantId,
      response: responseFromActionId(actionId),
    );
  }

  /// payload 가 가리키는 식물 하나. 알림 **본문**을 탭했을 때 쓴다.
  ///
  /// 버튼과 달리 답이 실려 있지 않다 — "이 식물을 물어보려던 알림"이라는
  /// 사실만 알 수 있다. 묶음 알림은 식물이 여럿이라 하나를 고를 수 없으므로
  /// null 이고, 그 경우 앱은 평소처럼 '오늘' 목록을 보여준다.
  static String? singlePlantIdFrom(String payload) {
    try {
      final decoded = jsonDecode(payload) as Map<String, Object?>;
      final ids = (decoded['plantIds'] as List?)?.cast<String>() ?? const [];
      return ids.length == 1 ? ids.first : null;
    } catch (e) {
      debugPrint('[ipkong] failed to parse payload: $e');
      return null;
    }
  }

  static SoilResponse? responseFromActionId(String id) => switch (id) {
        kActionTooWet => SoilResponse.tooWet,
        kActionJustRight => SoilResponse.justRight,
        kActionTooDry => SoilResponse.tooDry,
        _ => null, // kActionWatered — 단순 물주기
      };
}

class PendingAction {
  const PendingAction({required this.plantId, required this.response});

  final String plantId;

  /// null 이면 흙 상태 응답 없이 "줬어요" 만 누른 것이다.
  final SoilResponse? response;
}
