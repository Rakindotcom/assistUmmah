/// Formats app-generated numbers for the Bengali interface.
/// Keep stored values, identifiers, and user-entered text in their original form.
String banglaNumber(num value) => banglaDigits(value.toString());

/// Localizes digits in an app-generated date, time, or other numeric label.
String banglaDigits(String value) => value.replaceAllMapped(
      RegExp('[0-9]'),
      (match) => '০১২৩৪৫৬৭৮৯'[int.parse(match[0]!)],
    );
