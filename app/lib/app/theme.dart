import 'package:flutter/material.dart';

import 'tokens.dart';

/// 主题工厂。
///
/// 配色由 [AppPaletteScheme] 决定（主色种子 + 背景 + 强调/完成/逾期的语义色），
/// 组件样式在这里统一，页面只取 `Theme.of(context).colorScheme` 与
/// `context.appColors`，不再各写十六进制。
class AppTheme {
  static ThemeData light(AppPaletteScheme p) =>
      _build(Brightness.light, p);

  static ThemeData dark(AppPaletteScheme p) => _build(Brightness.dark, p);

  /// 深色主题下把语义色提亮，保证在深底上有足够对比。
  static Color _lift(Color c, bool isDark) =>
      isDark ? Color.lerp(c, Colors.white, 0.24)! : c;

  static ThemeData _build(Brightness brightness, AppPaletteScheme p) {
    final isDark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: p.seed,
      brightness: brightness,
    );
    // 浅色下用种子色本身做 primary（M3 默认会往灰里调），品牌色更明确。
    final scheme = isDark
        ? generated
        : generated.copyWith(primary: p.seed, onPrimary: Colors.white);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      extensions: [
        AppColors(
          accent: _lift(p.accent, isDark),
          done: _lift(p.done, isDark),
          warn: _lift(p.warn, isDark),
          palette: p.paletteFor(brightness),
        ),
      ],
    );

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? p.bgDark : p.bgLight,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusButton),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
      // 提示条跟随主题：浅色主题是浅底深字 + 细描边，深色主题是深底浅字。
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surface,
        actionTextColor: scheme.primary,
        contentTextStyle: TextStyle(
          fontSize: 12.5,
          color: scheme.onSurface,
          height: 1.4,
        ),
        elevation: 3,
        insetPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
      ),
      // FAB 用主色实心：默认的 primaryContainer 在高饱和方案里偏亮，压不住页面。
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? scheme.primary : p.seed,
        foregroundColor: isDark ? scheme.onPrimary : Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}
