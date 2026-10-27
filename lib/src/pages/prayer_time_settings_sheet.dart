import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../models.dart';
import '../prayer_times_service.dart';

class PrayerTimeSettingsSheet extends StatefulWidget {
  const PrayerTimeSettingsSheet({super.key, this.initial});

  final PrayerTimeConfig? initial;

  @override
  State<PrayerTimeSettingsSheet> createState() =>
      _PrayerTimeSettingsSheetState();
}

class _PrayerTimeSettingsSheetState extends State<PrayerTimeSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _place;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _timeZone;
  late final Map<String, TextEditingController> _adjustments;
  late String _method;
  late String _madhab;
  bool _findingLocation = false;

  @override
  void initState() {
    super.initState();
    final config = widget.initial;
    _place = TextEditingController(text: config?.placeName ?? '');
    _latitude = TextEditingController(text: config?.latitude.toString() ?? '');
    _longitude =
        TextEditingController(text: config?.longitude.toString() ?? '');
    _timeZone = TextEditingController(text: config?.timeZoneId ?? '');
    _method = config?.method ?? 'karachi';
    _madhab = config?.madhab ?? 'hanafi';
    _adjustments = {
      for (final key in prayerKeys)
        key: TextEditingController(text: '${config?.adjustments[key] ?? 0}'),
    };
    if (config == null) _fillDeviceTimeZone();
  }

  @override
  void dispose() {
    _place.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _timeZone.dispose();
    for (final controller in _adjustments.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fillDeviceTimeZone() async {
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      if (mounted && _timeZone.text.isEmpty) {
        setState(() => _timeZone.text = zone.identifier);
      }
    } catch (_) {
      // The user can still enter a time zone manually.
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _findingLocation = true);
    try {
      final (latitude, longitude) =
          await PrayerLocationService.currentCoordinates();
      final zone = await FlutterTimezone.getLocalTimezone();
      if (!mounted) return;
      setState(() {
        _latitude.text = latitude.toStringAsFixed(2);
        _longitude.text = longitude.toStringAsFixed(2);
        _timeZone.text = zone.identifier;
        if (_place.text.trim().isEmpty) _place.text = 'আমার অবস্থান';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('অবস্থান পাওয়া যায়নি। হাতে স্থান লিখতে পারেন।'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _findingLocation = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    try {
      final config = PrayerTimeConfig(
        latitude: double.parse(_latitude.text.trim()),
        longitude: double.parse(_longitude.text.trim()),
        placeName: _place.text.trim(),
        timeZoneId: _timeZone.text.trim(),
        method: _method,
        madhab: _madhab,
        adjustments: {
          for (final key in prayerKeys)
            key: int.parse(_adjustments[key]!.text.trim()),
        },
      );
      Navigator.of(context).pop(config);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সেটিংস যাচাই করুন।')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight =
        (MediaQuery.sizeOf(context).height - keyboardHeight - 24)
            .clamp(240.0, 700.0);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'নামাজের সময় সেট করুন',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                    'সময় আপনার ফোনেই হিসাব করা হয়। অবস্থান সার্ভারে পাঠানো হয় না।'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _findingLocation ? null : _useCurrentLocation,
                  icon: _findingLocation
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: const Text('বর্তমান অবস্থান ব্যবহার করুন'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _place,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'স্থানের নাম'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'স্থানের নাম দিন'
                      : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _CoordinateField(
                        controller: _latitude,
                        label: 'অক্ষাংশ',
                        min: -90,
                        max: 90,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CoordinateField(
                        controller: _longitude,
                        label: 'দ্রাঘিমাংশ',
                        min: -180,
                        max: 180,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _timeZone,
                  decoration: const InputDecoration(
                    labelText: 'টাইম জোন',
                    hintText: 'Asia/Dhaka',
                  ),
                  validator: (value) {
                    try {
                      PrayerTimeService.location(value?.trim() ?? '');
                      return null;
                    } catch (_) {
                      return 'সঠিক টাইম জোন দিন, যেমন Asia/Dhaka';
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'হিসাবের পদ্ধতি'),
                  items: [
                    for (final method in prayerCalculationMethods.entries)
                      DropdownMenuItem(
                        value: method.key,
                        child: Text(
                          method.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _method = value;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _madhab,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'আসর পদ্ধতি'),
                  items: const [
                    DropdownMenuItem(value: 'hanafi', child: Text('হানাফি')),
                    DropdownMenuItem(value: 'shafi', child: Text('শাফেয়ি')),
                  ],
                  onChanged: (value) {
                    if (value != null) _madhab = value;
                  },
                ),
                const SizedBox(height: 10),
                ExpansionTile(
                  title: const Text('সময় সমন্বয়'),
                  subtitle: const Text(
                      'স্থানীয় মসজিদের সময় অনুযায়ী মিনিট যোগ বা বিয়োগ'),
                  children: [
                    for (final key in prayerKeys)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: TextFormField(
                          controller: _adjustments[key],
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                          ),
                          decoration: InputDecoration(
                            labelText: '${prayerLabels[key]} (মিনিট)',
                          ),
                          validator: (value) {
                            final minutes = int.tryParse(value?.trim() ?? '');
                            return minutes == null || minutes.abs() > 60
                                ? '-৬০ থেকে ৬০ মিনিট দিন'
                                : null;
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                    onPressed: _save, child: const Text('সময় সংরক্ষণ করুন')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoordinateField extends StatelessWidget {
  const _CoordinateField({
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
  });

  final TextEditingController controller;
  final String label;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = double.tryParse(value?.trim() ?? '');
        return number == null ||
                !number.isFinite ||
                number < min ||
                number > max
            ? 'সঠিক মান দিন'
            : null;
      },
    );
  }
}
