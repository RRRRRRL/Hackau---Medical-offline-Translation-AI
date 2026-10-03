/// FieldTalk language configuration.
///
/// Mirrors backend/config.py. Supports English, Russian and Chinese.
/// Chinese <-> Russian is translated through an English pivot because no
/// direct translation model is bundled for that pair.
class LanguageConfig {
  static const Map<String, String> labels = {
    'en': 'English',
    'zh': 'Chinese',
    'ru': 'Russian',
  };

  static const Set<String> languages = {'en', 'zh', 'ru'};

  static const String pivotLanguage = 'en';

  static const Set<(String, String)> pivotPairs = {
    ('ru', 'zh'),
    ('zh', 'ru'),
  };

  static const Set<(String, String)> supportedPairs = {
    ('en', 'zh'),
    ('zh', 'en'),
    ('en', 'ru'),
    ('ru', 'en'),
    ('ru', 'zh'),
    ('zh', 'ru'),
  };

  static bool isSupported(String source, String target) =>
      supportedPairs.contains((source, target));

  static bool isPivot(String source, String target) =>
      pivotPairs.contains((source, target));
}