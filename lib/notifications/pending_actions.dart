import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/enums.dart';
import 'notification_backend.dart';

/// 백그라운드 isolate 에서 처리하지 못한 알림 액션을 쌓아두는 큐.
///
/// 백그라운드에서 DB 를 직접 건드리는 대신 SharedPreferences 에만 적어두고,
/// 앱이 다음에 열릴 때 [drain] 이 비우면서 반영한다.
class PendingActions {
  const PendingActions._();

  static const _key = 'pending_notification_actions';

  static Future<void> enqueue(String actionId, String payload) async {
    final prefs = await SharedPreferences.getInstance();
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
    try {
      final decoded = jsonDecode(payload) as Map<String, Object?>;
      final ids = (decoded['plantIds'] as List?)?.cast<String>() ?? const [];
      if (ids.length != 1) return null;
      return PendingAction(
        plantId: ids.first,
        response: responseFromActionId(actionId),
      );
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
