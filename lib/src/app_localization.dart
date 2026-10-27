import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

abstract final class AppLocalization {
  static const locale = Locale('bn');
  static const supportedLocales = [Locale('bn'), Locale('en')];
  static const delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}
