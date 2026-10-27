import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFFF4F7F5);
  static const ink = Color(0xFF1D3029);
  static const muted = Color(0xFF586C62);
  static const brand = Color(0xFF087568);
  static const brandSoft = Color(0xFFE4F2EB);
  static const border = Color(0xFFDCE5DF);
  static const success = Color(0xFF26724B);
  static const warning = Color(0xFF8A5A17);
  static const danger = Color(0xFFB33939);
  static const information = Color(0xFF42649E);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand).copyWith(
      primary: AppColors.brand,
      onPrimary: Colors.white,
      primaryContainer: AppColors.brandSoft,
      onPrimaryContainer: const Color(0xFF164B3D),
      secondary: const Color(0xFF476B5B),
      secondaryContainer: const Color(0xFFEDF3EE),
      onSecondaryContainer: AppColors.ink,
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: const Color(0xFF82958A),
      outlineVariant: AppColors.border,
      error: AppColors.danger,
      errorContainer: const Color(0xFFFCEDEC),
      onErrorContainer: const Color(0xFF702C2C),
    );
    const text = TextTheme(
      displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          height: 1.35,
          letterSpacing: -0.6),
      headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.4,
          letterSpacing: -0.5),
      headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.4,
          letterSpacing: -0.4),
      headlineSmall:
          TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.45),
      titleLarge:
          TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.5),
      titleMedium:
          TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.5),
      titleSmall:
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5),
      bodyLarge: TextStyle(fontSize: 16, height: 1.65),
      bodyMedium: TextStyle(fontSize: 14.5, height: 1.65),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.6),
      labelLarge:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
      labelMedium:
          TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4),
      labelSmall:
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.4),
    );
    final typography = text.apply(
        fontFamily: 'AnekBangla',
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink);
    final controlShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'AnekBangla',
      textTheme: typography,
      scaffoldBackgroundColor: AppColors.canvas,
      drawerTheme: const DrawerThemeData(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder()),
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: 68,
          titleTextStyle: typography.titleMedium,
          shape: const Border(bottom: BorderSide(color: AppColors.border))),
      cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: controlShape,
              textStyle: typography.labelLarge)),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: controlShape,
              side: const BorderSide(color: Color(0xFFC8D6CE)),
              textStyle: typography.labelLarge)),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: controlShape,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle: typography.labelLarge)),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.muted,
              shape: controlShape)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 2,
          focusElevation: 3,
          hoverElevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          extendedTextStyle: typography.labelLarge),
      inputDecorationTheme: InputDecorationTheme(
          errorMaxLines: 3,
          helperMaxLines: 3,
          filled: true,
          fillColor: const Color(0xFFFAFCFA),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          labelStyle: typography.bodyMedium?.copyWith(color: AppColors.muted),
          hintStyle: typography.bodyMedium?.copyWith(color: AppColors.muted),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFC8D6CE))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.brand, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.danger)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.danger, width: 2))),
      listTileTheme: ListTileThemeData(
          selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.45),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          minVerticalPadding: 12,
          iconColor: AppColors.muted,
          titleTextStyle: typography.titleSmall,
          subtitleTextStyle:
              typography.bodyMedium?.copyWith(color: AppColors.muted)),
      chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF0F4F1),
          selectedColor: const Color(0xFFDCEFE4),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: typography.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      checkboxTheme: CheckboxThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
      dividerTheme: const DividerThemeData(
          color: AppColors.border, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          indicatorColor: AppColors.brandSoft,
          indicatorShape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          labelTextStyle: WidgetStateProperty.resolveWith((states) =>
              typography.labelMedium?.copyWith(
                  color: states.contains(WidgetState.selected)
                      ? AppColors.brand
                      : AppColors.muted))),
      navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.white,
          indicatorColor: AppColors.brandSoft,
          indicatorShape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          selectedIconTheme: const IconThemeData(color: AppColors.brand),
          unselectedIconTheme: const IconThemeData(color: AppColors.muted),
          selectedLabelTextStyle:
              typography.labelLarge?.copyWith(color: AppColors.brand),
          unselectedLabelTextStyle:
              typography.labelLarge?.copyWith(color: AppColors.muted)),
      dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: typography.titleLarge,
          contentTextStyle: typography.bodyMedium),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.brandSoft,
        headerForegroundColor: AppColors.ink,
        headerHeadlineStyle: typography.titleLarge,
        headerHelpStyle: typography.labelLarge,
        toggleButtonTextStyle: typography.labelMedium?.copyWith(fontSize: 13),
        weekdayStyle: typography.labelMedium,
        dayStyle: typography.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          constraints: BoxConstraints(maxWidth: 640),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          contentTextStyle:
              typography.bodyMedium?.copyWith(color: Colors.white),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.brand,
          linearTrackColor: AppColors.brandSoft,
          linearMinHeight: 6),
      tooltipTheme: TooltipThemeData(
          textStyle: typography.bodySmall?.copyWith(color: Colors.white),
          decoration: BoxDecoration(
              color: AppColors.ink, borderRadius: BorderRadius.circular(8))),
    );
  }
}
