import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// 알림 시간 바텀시트.
///
/// 시계 앱의 알람 설정에서 **휠 한 줄만** 남긴 모양이다. 반복·레이블·사운드·
/// 다시 알림 행은 전부 뺐다 — 잎콩은 하루에 알림이 하나뿐이라 반복이라는 개념이
/// 없고, 알림 문구도 앱이 정한다. 고를 게 시각 하나뿐이면 화면도 그만큼이어야
/// 한다.
///
/// `showTimePicker` 대신 직접 만든 이유는 그 반대다. Material 기본 피커는
/// 다이얼·키보드 전환, 도움말, 확인/취소 버튼까지 달고 나와서 "시각 하나 고르기"
/// 에 비해 화면이 너무 무겁다.
Future<TimeOfDay?> showNotifyTimeSheet(
  BuildContext context, {
  required TimeOfDay initial,
}) => showModalBottomSheet<TimeOfDay>(
  context: context,
  isScrollControlled: true,
  // 시트 모양을 직접 그린다 (위쪽만 둥근 모서리, 손잡이).
  backgroundColor: Colors.transparent,
  builder: (_) => _NotifyTimeSheet(initial: initial),
);

/// 한 칸 높이. 선택 밴드도 같은 높이라 값이 어긋나면 밴드가 글자를 반쯤 문다.
const _itemExtent = 40.0;
const _wheelHeight = 220.0;

/// 분은 5분 단위다. 물주기 알림을 07:23 에 맞출 이유가 없고, 칸이 12개면
/// 한 바퀴가 손가락 한 번에 들어온다.
const _minuteStep = 5;

class _NotifyTimeSheet extends StatefulWidget {
  const _NotifyTimeSheet({required this.initial});

  final TimeOfDay initial;

  @override
  State<_NotifyTimeSheet> createState() => _NotifyTimeSheetState();
}

class _NotifyTimeSheetState extends State<_NotifyTimeSheet> {
  /// 12시간제에서 시 칸에 보이는 순서. 자정·정오가 12 로 맨 위에 온다.
  static const _hours12 = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  static final _hours24 = List.generate(24, (i) => i);
  static final _minutes = List.generate(
    60 ~/ _minuteStep,
    (i) => i * _minuteStep,
  );

  /// 자주 쓰는 시간. 아침에 흙을 만져보고 출근 전에 물을 주는 게 가장 흔한
  /// 리듬이고, 저녁 한 칸은 아침에 시간이 없는 사람 몫이다. 휠을 돌리지 않고
  /// 한 번에 갈 수 있게 두되, 확정은 여전히 ✓ 로만 한다 — 누르는 순간 시트가
  /// 닫히면 잘못 눌렀을 때 되돌릴 방법이 없다.
  static const _presets = [
    TimeOfDay(hour: 7, minute: 0),
    TimeOfDay(hour: 9, minute: 0),
    TimeOfDay(hour: 19, minute: 0),
  ];

  late final bool _use24;
  late final FixedExtentScrollController _apCtrl;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  late int _apIndex;
  late int _hourIndex;
  late int _minuteIndex;

  bool _ready = false;

  /// 칩이 휠을 굴리는 중인가.
  ///
  /// 휠은 굴러가면서 지나가는 칸마다 선택이 바뀌었다고 알린다. 그걸 그대로
  /// 받으면 값이 목표를 향해 한 칸씩 흘러가고, 그 사이에 ✓ 를 누른 사람은
  /// 고르지도 않은 중간 시각(오전 7시를 눌렀는데 10시)을 받는다.
  bool _presetAnimating = false;

  int get _hourCount => _use24 ? 24 : 12;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;

    // 12/24시간제는 기기 설정을 따른다. 24시간제에서는 오전·오후 칸이 의미가
    // 없으므로 아예 빼고 두 칸으로 돈다.
    _use24 = MediaQuery.alwaysUse24HourFormatOf(context);

    final hour = widget.initial.hour;
    // 5분 단위로 스냅한다. 55분을 넘겨 반올림되면 시가 넘어가야 하는데,
    // 그건 사용자가 고른 적 없는 시각이므로 55분에 붙인다.
    final minute = ((widget.initial.minute / _minuteStep).round() * _minuteStep)
        .clamp(0, 60 - _minuteStep);

    _apIndex = hour < 12 ? 0 : 1;
    _hourIndex = _use24 ? hour : hour % 12;
    _minuteIndex = minute ~/ _minuteStep;

    _apCtrl = FixedExtentScrollController(initialItem: _apIndex);
    _hourCtrl = FixedExtentScrollController(initialItem: _hourIndex);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minuteIndex);
  }

  @override
  void dispose() {
    _apCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  /// 지금 휠이 가리키는 시각.
  TimeOfDay get _value {
    if (_use24) {
      return TimeOfDay(
        hour: _hours24[_hourIndex],
        minute: _minutes[_minuteIndex],
      );
    }
    // 화면의 12 는 0시(자정) 또는 12시(정오)다.
    final shown = _hours12[_hourIndex];
    return TimeOfDay(
      hour: shown % 12 + _apIndex * 12,
      minute: _minutes[_minuteIndex],
    );
  }

  void _onChanged(void Function() apply) {
    HapticFeedback.selectionClick();
    setState(apply);
  }

  /// 휠이 알려준 선택 변화. 칩이 굴리는 중에 지나가는 칸은 받지 않는다.
  void _onWheelChanged(void Function() apply) {
    if (_presetAnimating) return;
    _onChanged(apply);
  }

  /// 칩을 누르면 휠이 그 자리로 굴러간다.
  ///
  /// 값은 누르는 순간 목표로 확정하고, 굴러가는 동안의 알림은 무시한다.
  Future<void> _applyPreset(TimeOfDay t) async {
    final apIndex = t.hour < 12 ? 0 : 1;
    final hourIndex = _use24 ? t.hour : t.hour % 12;
    final minuteIndex = t.minute ~/ _minuteStep;

    _onChanged(() {
      _apIndex = apIndex;
      _hourIndex = hourIndex;
      _minuteIndex = minuteIndex;
    });

    const duration = Duration(milliseconds: 260);
    const curve = Curves.easeOut;
    _presetAnimating = true;
    await Future.wait([
      if (!_use24)
        _apCtrl.animateToItem(apIndex, duration: duration, curve: curve),
      _hourCtrl.animateToItem(
        _nearestLoopIndex(_hourCtrl, hourIndex, _hourCount),
        duration: duration,
        curve: curve,
      ),
      _minuteCtrl.animateToItem(
        _nearestLoopIndex(_minuteCtrl, minuteIndex, _minutes.length),
        duration: duration,
        curve: curve,
      ),
    ]);
    _presetAnimating = false;

    // 시트가 먼저 닫혔으면 컨트롤러는 이미 폐기됐다.
    if (!mounted) return;

    // 사용자가 굴러가는 휠을 손으로 잡으면 애니메이션이 중간에 끊기고, 이
    // future 도 그때 끝난다. 그동안 무시한 칸 변화를 잃지 않도록, 휠이 실제로
    // 멈춘 자리에서 값을 다시 읽는다.
    setState(() {
      if (!_use24) _apIndex = _apCtrl.selectedItem.clamp(0, 1);
      _hourIndex = _wrap(_hourCtrl.selectedItem, _hourCount);
      _minuteIndex = _wrap(_minuteCtrl.selectedItem, _minutes.length);
    });
  }

  /// 무한 회전 휠에서 목표 값에 **가장 가까운** 인덱스를 고른다.
  ///
  /// 회전 휠의 실제 인덱스는 한 바퀴마다 계속 커진다. 지금 21번(=9시)에
  /// 있는데 그냥 9번으로 애니메이션하면 휠이 한 바퀴를 거꾸로 돈다.
  static int _nearestLoopIndex(
    FixedExtentScrollController controller,
    int target,
    int length,
  ) {
    final current = controller.selectedItem;
    final base = current - _wrap(current, length);
    final candidates = [
      base + target - length,
      base + target,
      base + target + length,
    ]..sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
    return candidates.first;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final material = MaterialLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabHandle(scheme),
              _header(context, s, theme, scheme),
              _wheels(s, scheme, material),
              _presetChips(material),
              Padding(
                // 좌우 여백을 더 주면 한글이 단어 중간에서 끊긴다
                // ("십수 분 늦 / 을 수 있습니다"). 시트 자체 여백 20px 로 충분하다.
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  s.notifySheetNote,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChips(MaterialLocalizations material) {
    final use24 = _use24;
    final now = _value;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final preset in _presets)
            ChoiceChip(
              label: Text(
                material.formatTimeOfDay(preset, alwaysUse24HourFormat: use24),
              ),
              // 칩 셋이 한 줄에 들어가야 훑어보기 쉽다. 선택 여부는 채움색으로
              // 보이고, 스크린 리더에는 ChoiceChip 이 '선택됨'으로 읽어준다.
              showCheckmark: false,
              selected: preset == now,
              onSelected: (_) => _applyPreset(preset),
            ),
        ],
      ),
    );
  }

  Widget _grabHandle(ColorScheme scheme) => SizedBox(
    height: 20,
    child: Center(
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    ),
  );

  Widget _header(
    BuildContext context,
    AppStrings s,
    ThemeData theme,
    ColorScheme scheme,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
    child: Row(
      children: [
        _RoundButton(
          icon: Icons.close,
          iconSize: 22,
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
          semanticLabel: s.cancel,
          onTap: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Text(
            s.notifyTime,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              letterSpacing: -0.2,
            ),
          ),
        ),
        _RoundButton(
          icon: Icons.check,
          iconSize: 24,
          background: scheme.primary,
          foreground: scheme.onPrimary,
          semanticLabel: s.save,
          onTap: () => Navigator.of(context).pop(_value),
        ),
      ],
    ),
  );

  Widget _wheels(
    AppStrings s,
    ColorScheme scheme,
    MaterialLocalizations material,
  ) => SizedBox(
    height: _wheelHeight,
    child: Stack(
      children: [
        // 선택 밴드. 휠 뒤에 깔려 있어야 페이드 마스크에 같이 흐려지지 않는다.
        Positioned(
          left: 0,
          right: 0,
          top: (_wheelHeight - _itemExtent) / 2,
          height: _itemExtent,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        // 위아래로 서서히 사라지게 한다 — 잘린 글자가 밴드 바깥에 남으면
        // 어느 줄이 선택된 건지 눈이 헷갈린다.
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_use24)
                _Wheel(
                  width: 96,
                  controller: _apCtrl,
                  alignment: Alignment.centerRight,
                  // 오전·오후는 돌지 않는다. 두 칸짜리 휠이 무한히 돌면
                  // 지금 어디인지 감각이 사라진다.
                  loop: false,
                  fontSize: 22,
                  labels: [
                    material.anteMeridiemAbbreviation,
                    material.postMeridiemAbbreviation,
                  ],
                  selected: _apIndex,
                  scheme: scheme,
                  semanticLabel: s.wheelAmPm,
                  onChanged: (i) => _onWheelChanged(() => _apIndex = i),
                ),
              _Wheel(
                width: 76,
                controller: _hourCtrl,
                alignment: Alignment.center,
                loop: true,
                fontSize: 23,
                labels: [
                  for (final h in _use24 ? _hours24 : _hours12)
                    _use24 ? h.toString().padLeft(2, '0') : h.toString(),
                ],
                selected: _hourIndex,
                scheme: scheme,
                semanticLabel: s.wheelHour,
                onChanged: (i) => _onWheelChanged(() => _hourIndex = i),
              ),
              _Wheel(
                width: 76,
                controller: _minuteCtrl,
                alignment: Alignment.center,
                loop: true,
                fontSize: 23,
                labels: [
                  for (final m in _minutes) m.toString().padLeft(2, '0'),
                ],
                selected: _minuteIndex,
                scheme: scheme,
                semanticLabel: s.wheelMinute,
                onChanged: (i) => _onWheelChanged(() => _minuteIndex = i),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 무한 회전 휠은 범위를 벗어난 인덱스를 준다 (음수도 온다).
int _wrap(int i, int n) => ((i % n) + n) % n;

/// 휠 한 칸.
class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.width,
    required this.controller,
    required this.labels,
    required this.selected,
    required this.loop,
    required this.alignment,
    required this.fontSize,
    required this.scheme,
    required this.semanticLabel,
    required this.onChanged,
  });

  final double width;
  final FixedExtentScrollController controller;
  final List<String> labels;
  final int selected;
  final bool loop;
  final Alignment alignment;
  final double fontSize;
  final ColorScheme scheme;

  /// 스크린 리더가 읽는 칸 이름 ("시", "분"). 값만 읽히면 "9" 가 무엇인지 모른다.
  final String semanticLabel;

  final ValueChanged<int> onChanged;

  /// 스크린 리더의 늘리기/줄이기 한 번에 한 칸씩 굴린다.
  void _step(int delta) {
    controller.animateToItem(
      controller.selectedItem + delta,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = labels.length;
    // 도는 휠은 양쪽 끝이 없다. 돌지 않는 휠(오전·오후)은 끝에서 그쪽 액션을
    // 아예 내놓지 않는다 — 눌러도 아무 일이 없는 액션을 읽어주면 헷갈린다.
    final canIncrease = loop || selected < count - 1;
    final canDecrease = loop || selected > 0;

    final children = [
      for (var i = 0; i < labels.length; i++)
        Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: fontSize,
                letterSpacing: -0.2,
                fontWeight: i == selected ? FontWeight.w500 : FontWeight.w400,
                // 선택된 줄은 밴드 위에 앉으므로 밴드 기준 대비색을 쓴다.
                color: i == selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                // 숫자가 바뀌어도 칸이 흔들리지 않게 고정폭 숫자를 쓴다.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
    ];

    // ListWheelScrollView 는 늘리기/줄이기 액션을 주지 않는다. 그대로 두면
    // VoiceOver·TalkBack 사용자는 휠을 돌릴 방법이 없어서 칩 세 개 말고는
    // 시각을 고를 수 없다. CupertinoPicker 가 따로 붙이는 것과 같은 일을 한다.
    return Semantics(
      container: true,
      label: semanticLabel,
      value: labels[selected],
      increasedValue: canIncrease ? labels[_wrap(selected + 1, count)] : null,
      decreasedValue: canDecrease ? labels[_wrap(selected - 1, count)] : null,
      onIncrease: canIncrease ? () => _step(1) : null,
      onDecrease: canDecrease ? () => _step(-1) : null,
      // 칸마다의 글자는 따로 읽히지 않게 한다. 위의 값 하나로 충분하다.
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: _itemExtent,
            // 밴드를 직접 그리므로 기본 확대경은 끈다.
            useMagnifier: false,
            // iOS 휠보다 완만하게 눕힌다. 곡률이 세면 위아래 글자가 너무 납작해져
            // 페이드와 겹치며 읽기 어려워진다.
            diameterRatio: 2.2,
            perspective: 0.002,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) => onChanged(_wrap(i, labels.length)),
            childDelegate: loop
                ? ListWheelChildLoopingListDelegate(children: children)
                : ListWheelChildListDelegate(children: children),
          ),
        ),
      ),
    );
  }
}

/// 시트 상단의 동그란 버튼 (닫기 · 확정).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.iconSize,
    required this.background,
    required this.foreground,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final Color background;
  final Color foreground;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // container 를 켜야 자기 노드를 갖는다. 빠뜨리면 가운데 제목과 한 덩어리로
    // 합쳐져 버튼 둘이 사라진다.
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}
