import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../pages/prayer_time_settings_sheet.dart';
import '../prayer_times_service.dart';

class PrayerPlacePicker extends StatefulWidget {
  const PrayerPlacePicker({super.key, this.initial});
  final PrayerTimeConfig? initial;
  @override
  State<PrayerPlacePicker> createState() => _PrayerPlacePickerState();
}

class _PrayerPlacePickerState extends State<PrayerPlacePicker> {
  bool _busy = false;
  String? _error;

  Future<void> _current() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (latitude, longitude) =
          await PrayerLocationService.currentCoordinates();
      final zone = await FlutterTimezone.getLocalTimezone();
      final config = PrayerTimeConfig(
          latitude: latitude,
          longitude: longitude,
          placeName: 'আমার অবস্থান',
          timeZoneId: zone.identifier);
      if (mounted) Navigator.pop(context, config);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'অবস্থান পাওয়া যায়নি। শহর বেছে নিন বা হাতে স্থান লিখুন।');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advanced() async {
    final config = await showModalBottomSheet<PrayerTimeConfig>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => PrayerTimeSettingsSheet(initial: widget.initial));
    if (mounted && config != null) Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('আপনার নামাজের সময়',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'স্থান ফোনেই থাকে। সময় দেখার জন্য প্রতিদিন ইন্টারনেট লাগবে না।'),
              const SizedBox(height: 18),
              FilledButton.icon(
                  onPressed: _busy ? null : _current,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                  label: Text(_busy
                      ? 'অবস্থান নেওয়া হচ্ছে…'
                      : 'আমার অবস্থান ব্যবহার করুন')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 20),
              Text('শহর থেকে বেছে নিন',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text('শহরের কেন্দ্র · করাচি পদ্ধতি · হানাফি আসর'),
              const SizedBox(height: 10),
              for (final city in const [
                ('ঢাকা', 23.81, 90.41),
                ('চট্টগ্রাম', 22.36, 91.78),
                ('সিলেট', 24.89, 91.87)
              ])
                ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: const Icon(Icons.location_city_outlined),
                    title: Text(city.$1),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () => Navigator.pop(
                            context,
                            PrayerTimeConfig(
                                latitude: city.$2,
                                longitude: city.$3,
                                placeName: city.$1,
                                timeZoneId: 'Asia/Dhaka'))),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _advanced,
                  icon: const Icon(Icons.tune),
                  label: const Text('অন্য স্থান বা হিসাবের পদ্ধতি')),
            ]),
      ));
}
