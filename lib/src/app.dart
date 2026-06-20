import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth/auth_gate.dart';

class UmmahAssistApp extends StatelessWidget {
  const UmmahAssistApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Ummah Assist',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        textTheme: GoogleFonts.anekBanglaTextTheme(),
        scaffoldBackgroundColor: const Color(0xFFF7FAF8),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
      builder: (context, child) {
        return _MobilePreviewFrame(child: child ?? const SizedBox.shrink());
      },
      home: AuthGate(firebaseReady: firebaseReady),
    );
  }
}

class _MobilePreviewFrame extends StatelessWidget {
  const _MobilePreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return child;
        }

        final height = (constraints.maxHeight - 48).clamp(620.0, 900.0);

        return ColoredBox(
          color: const Color(0xFFEFF7F3),
          child: Center(
            child: Container(
              width: 430,
              height: height,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(42),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 42,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Column(
                  children: [
                    const _PhoneStatusBar(),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhoneStatusBar extends StatelessWidget {
  const _PhoneStatusBar();

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final minute = now.minute.toString().padLeft(2, '0');

    return Container(
      height: 34,
      color: const Color(0xFFF7FAF8),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Text(
            '${now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod}:$minute',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const Spacer(),
          Container(
            width: 70,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const Spacer(),
          const Icon(Icons.signal_cellular_alt, size: 15),
          const SizedBox(width: 5),
          const Icon(Icons.wifi, size: 15),
          const SizedBox(width: 5),
          const Icon(Icons.battery_full, size: 16),
        ],
      ),
    );
  }
}
