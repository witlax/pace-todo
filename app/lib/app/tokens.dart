import 'package:flutter/material.dart';
import '../core/i18n/i18n.dart';

/// 重要性四档的唯一色板（ADR-0012）。所有视图共用，不另设颜色。
enum Emphasis {
  none(0),
  low(1),
  medium(2),
  high(3);

  const Emphasis(this.value);
  final int value;

  static Emphasis fromValue(int v) => Emphasis.values.firstWhere(
    (e) => e.value == v,
    orElse: () => Emphasis.none,
  );

  String get label => switch (this) {
    Emphasis.none => tr('无'),
    Emphasis.low => tr('低'),
    Emphasis.medium => tr('中'),
    Emphasis.high => tr('高'),
  };
}

class Palette {
  const Palette({
    required this.high,
    required this.medium,
    required this.low,
    required this.none,
  });

  final Color high;
  final Color medium;
  final Color low;
  final Color none;

  Color of(Emphasis e) => switch (e) {
    Emphasis.high => high,
    Emphasis.medium => medium,
    Emphasis.low => low,
    Emphasis.none => none,
  };

  /// 色觉友好：品红 / 琥珀 / 青 / 灰（不依赖红绿区分）。
  static const colorBlindSafe = Palette(
    high: Color(0xFFA21CAF),
    medium: Color(0xFFB45309),
    low: Color(0xFF0F6E56),
    none: Color(0xFF9AA0A8),
  );
}

/// 整套配色方案。
///
/// 取色思路借鉴 PaletteMaker 的「低饱和主色 + 中性底 + 一个暖色强调」：
/// 中性色承担大部分面积，主色只出现在可交互元素上，暖色只标「今天 / 进行中」。
/// 每个方案给浅色与深色两套底，重要性四色跟着主色调整色相，避免
/// 「主色蓝同时又被当成低优先级蓝」这种语义打架。
enum AppPaletteName {
  teal('青瓷', '墨绿主色 + 陶土强调，最耐看'),
  steel('钢蓝', '冷蓝主色 + 琥珀强调，偏工具感'),
  clay('陶土', '砖红主色 + 橄榄灰，偏生活感');

  const AppPaletteName(this._label, this._hint);
  final String _label;
  final String _hint;

  /// 枚举值本身不能调函数（隐式 const），所以存原文、用时再翻。
  String get label => tr(_label);
  String get hint => tr(_hint);

  static AppPaletteName parse(String? raw) =>
      AppPaletteName.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => AppPaletteName.teal,
      );

  AppPaletteScheme get scheme => switch (this) {
    AppPaletteName.teal => AppPaletteScheme.teal,
    AppPaletteName.steel => AppPaletteScheme.steel,
    AppPaletteName.clay => AppPaletteScheme.clay,
  };
}

class AppPaletteScheme {
  const AppPaletteScheme({
    required this.name,
    required this.seed,
    required this.bgLight,
    required this.bgDark,
    required this.accent,
    required this.done,
    required this.warn,
    required this.palette,
    required this.paletteDark,
  });

  final AppPaletteName name;

  /// 主色种子：ColorScheme.fromSeed 由它派生整套 primary / secondary。
  final Color seed;
  final Color bgLight;
  final Color bgDark;

  /// 强调色（今天、等级、进行中）——只出现在少数位置，才叫强调。
  final Color accent;

  /// 完成态（勾选、达标、连续天数）。
  final Color done;

  /// 逾期、破坏性提示。
  final Color warn;

  final Palette palette;
  final Palette paletteDark;

  Palette paletteFor(Brightness b) =>
      b == Brightness.dark ? paletteDark : palette;

  /// 青瓷：墨绿主色，陶土橙强调。默认方案，与图标同色系。
  static const teal = AppPaletteScheme(
    name: AppPaletteName.teal,
    seed: Color(0xFF1E6E63),
    bgLight: Color(0xFFF4F7F5),
    bgDark: Color(0xFF0E1413),
    accent: Color(0xFFC2703A),
    done: Color(0xFF2A7F63),
    warn: Color(0xFFB3402A),
    palette: Palette(
      high: Color(0xFFB3402A),
      medium: Color(0xFFB7791F),
      low: Color(0xFF3D7A8C),
      none: Color(0xFF98A09C),
    ),
    paletteDark: Palette(
      high: Color(0xFFE38B74),
      medium: Color(0xFFD9A85A),
      low: Color(0xFF7FB6C4),
      none: Color(0xFF7E8884),
    ),
  );

  /// 钢蓝：冷调工具感，配合琥珀强调。
  static const steel = AppPaletteScheme(
    name: AppPaletteName.steel,
    seed: Color(0xFF245C8A),
    bgLight: Color(0xFFF3F6F9),
    bgDark: Color(0xFF0D1219),
    accent: Color(0xFFD9822B),
    done: Color(0xFF2E7D57),
    warn: Color(0xFFC2413A),
    palette: Palette(
      high: Color(0xFFC2413A),
      medium: Color(0xFFB45309),
      low: Color(0xFF4B7FA6),
      none: Color(0xFF98A0AB),
    ),
    paletteDark: Palette(
      high: Color(0xFFE08B86),
      medium: Color(0xFFD79E5C),
      low: Color(0xFF8FB4CE),
      none: Color(0xFF7C8493),
    ),
  );

  /// 陶土：砖红主色，配橄榄灰与金。暖，但不吵。
  static const clay = AppPaletteScheme(
    name: AppPaletteName.clay,
    seed: Color(0xFF9A4B2E),
    bgLight: Color(0xFFFAF6F2),
    bgDark: Color(0xFF161110),
    accent: Color(0xFFB7791F),
    done: Color(0xFF4E7A57),
    warn: Color(0xFFA93400),
    palette: Palette(
      high: Color(0xFFA93400),
      medium: Color(0xFFB7791F),
      low: Color(0xFF5A6E8C),
      none: Color(0xFFA39A93),
    ),
    paletteDark: Palette(
      high: Color(0xFFE09A72),
      medium: Color(0xFFD9B15E),
      low: Color(0xFF93A7C1),
      none: Color(0xFF8B827C),
    ),
  );

  static AppPaletteScheme of(AppPaletteName name) => name.scheme;
}

/// 语义色扩展：页面不直接写十六进制，统一从这里取。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.accent,
    required this.done,
    required this.warn,
    required this.palette,
  });

  final Color accent;
  final Color done;
  final Color warn;

  /// 重要性四色，跟随配色方案与明暗。
  final Palette palette;

  @override
  AppColors copyWith({
    Color? accent,
    Color? done,
    Color? warn,
    Palette? palette,
  }) => AppColors(
    accent: accent ?? this.accent,
    done: done ?? this.done,
    warn: warn ?? this.warn,
    palette: palette ?? this.palette,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      done: Color.lerp(done, other.done, t) ?? done,
      warn: Color.lerp(warn, other.warn, t) ?? warn,
      palette: palette,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      AppColors(
        accent: Color(0xFFC2703A),
        done: Color(0xFF2A7F63),
        warn: Color(0xFFB3402A),
        palette: Palette(
          high: Color(0xFFB3402A),
          medium: Color(0xFFB7791F),
          low: Color(0xFF3D7A8C),
          none: Color(0xFF98A09C),
        ),
      );
}

class AppTokens {
  static const radiusCard = 12.0;
  static const radiusButton = 10.0;
  static const rowHeight = 56.0;
  static const gutter = 16.0;
}
