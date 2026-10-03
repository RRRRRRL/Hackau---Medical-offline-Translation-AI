/// Offline, rule-based extraction of medical key information from source text.
///
/// This is a pure-language port of the planned backend emergency_nlp layer.
/// It runs fully on-device with no ML dependencies. It recognises negation,
/// medical entities (via the bundled glossary) and whether the utterance is
/// a question, so the app can surface structured signals to the responder.
library;

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Negation markers per language. A negation flips the meaning of the
/// adjacent entity (e.g. "no pain" -> the patient is NOT in pain).
const Map<String, List<String>> _negationMarkers = {
  'en': ['no', 'not', "don't", 'dont', 'never', 'none'],
  'ru': ['нет', 'не', 'ни', 'никакой'],
  'zh': ['不', '没', '没有', '无'],
};

/// Question markers: whether an utterance is a question (for responder
/// prompts) vs a statement (patient report).
const Map<String, List<String>> _questionMarkers = {
  'en': ['?', 'do you', 'are you', 'can you', 'did you', 'where', 'what'],
  'ru': ['?', 'ли', 'ли вы', 'где', 'что', 'вы можете'],
  'zh': ['？', '吗', '哪', '什么', '能'],
};

class Entity {
  final String category;
  final String label;
  const Entity(this.category, this.label);

  Map<String, String> toJson() => {'category': category, 'label': label};
}

class KeyInformation {
  final bool isQuestion;
  final bool negated;
  final List<Entity> entities;
  final List<String> categories;
  const KeyInformation({
    required this.isQuestion,
    required this.negated,
    required this.entities,
    required this.categories,
  });

  Map<String, dynamic> toJson() => {
        'is_question': isQuestion,
        'negated': negated,
        'entities': entities.map((e) => e.toJson()).toList(),
        'categories': categories,
      };
}

class NlpService {
  /// category -> list of marker words (lowercased for en/ru; zh is exact).
  Map<String, List<String>> _glossary = {};

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/data/glossary.json');
    final list = jsonDecode(raw) as List;
    _glossary = {};
    for (final entry in list) {
      final map = entry as Map<String, dynamic>;
      final category = map['category'] as String;
      final markers = <String>[];
      for (final lang in ['en', 'ru', 'zh']) {
        for (final word in (map[lang] as List).cast<String>()) {
          markers.add(word.toLowerCase());
        }
      }
      _glossary[category] = markers;
    }
  }

  KeyInformation extract(String text, String language) {
    final lowered = text.toLowerCase();
    final negated = _hasNegation(lowered, language);
    final isQuestion = _isQuestion(text, language);
    final entities = <Entity>[];
    final categories = <String>[];

    _glossary.forEach((category, markers) {
      final found = markers.where(lowered.contains).toList();
      if (found.isNotEmpty) {
        categories.add(category);
        entities.add(Entity(category, found.first));
      }
    });

    return KeyInformation(
      isQuestion: isQuestion,
      negated: negated,
      entities: entities,
      categories: categories,
    );
  }

  bool _hasNegation(String lowered, String language) {
    final markers = _negationMarkers[language] ?? const [];
    for (final marker in markers) {
      if (lowered.contains(marker)) return true;
    }
    return false;
  }

  bool _isQuestion(String text, String language) {
    final markers = _questionMarkers[language] ?? const [];
    for (final marker in markers) {
      if (text.toLowerCase().contains(marker)) return true;
    }
    return false;
  }
}