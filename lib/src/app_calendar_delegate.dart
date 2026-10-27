import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Retains the standard Gregorian picker and uses a compact localized month
/// label so the year remains visible on small screens with enlarged text.
class AppCalendarDelegate extends GregorianCalendarDelegate {
  const AppCalendarDelegate(this.locale);
  final Locale locale;

  @override
  String formatMonthYear(DateTime date, MaterialLocalizations localizations) =>
      DateFormat.yMMM(locale.toString()).format(date);
}
