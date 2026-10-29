import 'display_formatters.dart';

class QuranDua {
  const QuranDua(
      {required this.id,
      required this.title,
      required this.category,
      required this.arabic,
      required this.meaning,
      required this.reference,
      required this.verseKey});

  final String id, title, category, arabic, meaning, reference, verseKey;
  String get sourceUrl => 'https://quran.com/$verseKey';
  String get displayReference => banglaDigits(reference);
  String get copyText => '$title\n\n$arabic\n\nবাংলা অর্থ: $meaning\n\n'
      '$displayReference · দোয়ার অংশ\n$sourceUrl';

  bool matches(String query) => normalizeDuaSearch(
          '$title $category $arabic $meaning $reference $verseKey')
      .contains(normalizeDuaSearch(query.trim()));
}

String normalizeDuaSearch(String value) {
  var text = value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '');
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll('০১২৩৪৫৬৭৮৯'[i], '$i');
  }
  return text;
}

QuranDua duaForDay(DateTime day) =>
    quranDuas[DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(2026))
            .inDays %
        quranDuas.length];

/// Quranic supplication excerpts, checked against the linked full ayahs.
/// Bengali meanings are editorial paraphrases; no recitation reward is claimed.
const quranDuas = [
  QuranDua(
      id: 'knowledge',
      title: 'জ্ঞান বৃদ্ধির দোয়া',
      category: 'জ্ঞান ও কাজ',
      arabic: 'رَبِّ زِدْنِي عِلْمًا',
      meaning: 'হে আমার রব, আমার জ্ঞান বাড়িয়ে দিন।',
      reference: 'সূরা ত্বহা 20:114',
      verseKey: '20/114'),
  QuranDua(
      id: 'goodness',
      title: 'দুনিয়া ও আখিরাতের কল্যাণ',
      category: 'কল্যাণ',
      arabic:
          'رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ',
      meaning:
          'হে আমাদের রব, দুনিয়ায় ও আখিরাতে আমাদের কল্যাণ দিন এবং আগুনের শাস্তি থেকে রক্ষা করুন।',
      reference: 'সূরা আল-বাকারা 2:201',
      verseKey: '2/201'),
  QuranDua(
      id: 'parents',
      title: 'বাবা-মায়ের জন্য দোয়া',
      category: 'পরিবার',
      arabic: 'رَبِّ ارْحَمْهُمَا كَمَا رَبَّيَانِي صَغِيرًا',
      meaning:
          'হে আমার রব, তাঁদের প্রতি দয়া করুন, যেমন তাঁরা ছোটবেলায় আমাকে লালন-পালন করেছেন।',
      reference: 'সূরা আল-ইসরা 17:24',
      verseKey: '17/24'),
  QuranDua(
      id: 'guidance',
      title: 'হিদায়াতের পথে থাকার দোয়া',
      category: 'হিদায়াত',
      arabic:
          'رَبَّنَا لَا تُزِغْ قُلُوبَنَا بَعْدَ إِذْ هَدَيْتَنَا وَهَبْ لَنَا مِنْ لَدُنْكَ رَحْمَةً إِنَّكَ أَنْتَ الْوَهَّابُ',
      meaning:
          'হে আমাদের রব, হিদায়াত দেওয়ার পর আমাদের অন্তরকে বিপথে যেতে দেবেন না। আপনার কাছ থেকে আমাদের রহমত দিন; আপনিই মহান দাতা।',
      reference: 'সূরা আলে ইমরান 3:8',
      verseKey: '3/8'),
  QuranDua(
      id: 'ease',
      title: 'কাজ সহজ হওয়ার দোয়া',
      category: 'জ্ঞান ও কাজ',
      arabic:
          'رَبِّ اشْرَحْ لِي صَدْرِي ۝ وَيَسِّرْ لِي أَمْرِي ۝ وَاحْلُلْ عُقْدَةً مِنْ لِسَانِي ۝ يَفْقَهُوا قَوْلِي',
      meaning:
          'হে আমার রব, আমার অন্তর প্রশস্ত করুন, আমার কাজ সহজ করুন এবং আমার জিহ্বার জড়তা দূর করুন, যাতে তারা আমার কথা বুঝতে পারে।',
      reference: 'সূরা ত্বহা 20:25–28',
      verseKey: '20/25-28'),
  QuranDua(
      id: 'provision',
      title: 'রবের অনুগ্রহ চাওয়ার দোয়া',
      category: 'কল্যাণ',
      arabic: 'رَبِّ إِنِّي لِمَا أَنْزَلْتَ إِلَيَّ مِنْ خَيْرٍ فَقِيرٌ',
      meaning:
          'হে আমার রব, আপনি আমার প্রতি যে কল্যাণ পাঠান, আমি তার মুখাপেক্ষী।',
      reference: 'সূরা আল-কাসাস 28:24',
      verseKey: '28/24'),
  QuranDua(
      id: 'family',
      title: 'পরিবারের কল্যাণের দোয়া',
      category: 'পরিবার',
      arabic:
          'رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا',
      meaning:
          'হে আমাদের রব, আমাদের জীবনসঙ্গী ও সন্তানদের আমাদের চোখের প্রশান্তি করুন এবং আমাদের মুত্তাকিদের জন্য অনুসরণীয় করুন।',
      reference: 'সূরা আল-ফুরকান 25:74',
      verseKey: '25/74'),
  QuranDua(
      id: 'forgiveness',
      title: 'ক্ষমা ও রহমতের দোয়া',
      category: 'ক্ষমা',
      arabic:
          'رَبَّنَا ظَلَمْنَا أَنْفُسَنَا وَإِنْ لَمْ تَغْفِرْ لَنَا وَتَرْحَمْنَا لَنَكُونَنَّ مِنَ الْخَاسِرِينَ',
      meaning:
          'হে আমাদের রব, আমরা নিজেদের ওপর অন্যায় করেছি। আপনি ক্ষমা ও দয়া না করলে আমরা অবশ্যই ক্ষতিগ্রস্ত হব।',
      reference: 'সূরা আল-আরাফ 7:23',
      verseKey: '7/23'),
];
