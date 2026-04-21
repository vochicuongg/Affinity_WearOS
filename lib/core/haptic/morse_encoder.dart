// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — morse_encoder.dart
//
//  Responsibilities:
//   1. TEXT → MORSE:  "SOS" → "... --- ..." → vibration int-list
//   2. TAP → MORSE:   tap-duration discriminator (dot < 300ms, dash ≥ 300ms)
//   3. PATTERN BUILDER: assembles the final [wait,vibe,wait,vibe,...] list
//      that the `vibration` package consumes directly.
//
//  Vibration pattern convention (milliseconds):
//    [0, dotMs, gapMs, dashMs, gapMs, ...]
//    where index 0 is always 0 (no initial wait) and
//    even indices are silence, odd indices are vibration.
// ═══════════════════════════════════════════════════════════════════════════

abstract final class MorseEncoder {
  // ── Morse alphabet ────────────────────────────────────────────────────────
  static const Map<String, String> _alphabet = {
    'A': '.-',   'B': '-...', 'C': '-.-.', 'D': '-..',  'E': '.',
    'F': '..-.', 'G': '--.',  'H': '....', 'I': '..',   'J': '.---',
    'K': '-.-',  'L': '.-..', 'M': '--',   'N': '-.',   'O': '---',
    'P': '.--.', 'Q': '--.-', 'R': '.-.',  'S': '...',  'T': '-',
    'U': '..-',  'V': '...-', 'W': '.--',  'X': '-..-', 'Y': '-.--',
    'Z': '--..',
    '0': '-----','1': '.----','2': '..---','3': '...--','4': '....-',
    '5': '.....','6': '-....','7': '--...','8': '---..','9': '----.',
  };

  // ── Timing constants (ms) ─────────────────────────────────────────────────
  static const int dotMs        = 120;   // dot vibration duration
  static const int dashMs       = 360;   // dash vibration duration
  static const int symbolGapMs  = 120;   // gap between dots/dashes in one letter
  static const int letterGapMs  = 360;   // gap between letters
  static const int wordGapMs    = 840;   // gap between words
  static const int tapThresholdMs = 300; // taps shorter than this → dot

  // ═════════════════════════════════════════════════════════════════════════
  //  1. TEXT → VIBRATION PATTERN
  // ═════════════════════════════════════════════════════════════════════════

  /// Converts [text] to a Wear OS vibration pattern list.
  ///
  /// Returns a list suitable for `Vibration.vibrate(pattern: result)`.
  /// Even indices = silence duration, odd indices = vibration duration.
  /// The list always starts with 0 (no initial delay).
  ///
  /// Example:  "SOS" → [0,120,120,120,120,120,360,120,120,120,120,120,120,...]
  static List<int> textToPattern(String text) {
    final words = text.toUpperCase().split(' ');
    final pattern = <int>[];

    for (var w = 0; w < words.length; w++) {
      final word = words[w];
      for (var c = 0; c < word.length; c++) {
        final morse = _alphabet[word[c]];
        if (morse == null) continue; // skip unknown characters

        for (var s = 0; s < morse.length; s++) {
          // Leading silence: 0 at start, symbolGap between symbols, letterGap between letters
          if (pattern.isEmpty) {
            pattern.add(0);
          } else if (s == 0) {
            // Start of a new letter: overwrite the trailing silence to letterGap
            pattern[pattern.length - 1] = letterGapMs;
            pattern.add(0); // placeholder for next vibration's leading silence
          } else {
            pattern.add(symbolGapMs);
          }
          // Vibration duration
          pattern.add(morse[s] == '.' ? dotMs : dashMs);
          // Trailing silence placeholder
          pattern.add(symbolGapMs); // will be overwritten at next iteration
        }
      }

      // Between words: replace the trailing silence with wordGap
      if (w < words.length - 1 && pattern.isNotEmpty) {
        pattern[pattern.length - 1] = wordGapMs;
      }
    }

    // Clean up: remove trailing silence if present
    if (pattern.isNotEmpty && pattern.last == symbolGapMs) {
      pattern.removeLast();
    }

    return pattern.isEmpty ? [0, dotMs] : pattern;
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  2. TAP SEQUENCE → VIBRATION PATTERN
  // ═════════════════════════════════════════════════════════════════════════

  /// Converts a list of tap durations (ms) directly into a vibration pattern.
  ///
  /// Each duration < [tapThresholdMs] → dot, otherwise → dash.
  /// Inter-tap gaps use [symbolGapMs]; pattern always starts with 0.
  ///
  /// Usage:  final pattern = MorseEncoder.tapsToPattern([80, 350, 90]);
  ///         // → short, long, short → · − · → "R" in Morse
  static List<int> tapsToPattern(List<int> tapDurationsMs) {
    if (tapDurationsMs.isEmpty) return [0, dotMs];
    final pattern = <int>[0];
    for (var i = 0; i < tapDurationsMs.length; i++) {
      pattern.add(tapDurationsMs[i] < tapThresholdMs ? dotMs : dashMs);
      if (i < tapDurationsMs.length - 1) pattern.add(symbolGapMs);
    }
    return pattern;
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  3. MORSE STRING → VIBRATION PATTERN (internal, exported for testing)
  // ═════════════════════════════════════════════════════════════════════════

  /// Converts a raw Morse string like `"... --- ..."` into a vibration pattern.
  static List<int> morseStringToPattern(String morse) {
    return textToPattern(
      morse
          .split(' ')
          .map((code) => _alphabet.entries
              .firstWhere((e) => e.value == code,
                  orElse: () => const MapEntry('?', ''))
              .key)
          .join(),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  4. PATTERN → HUMAN READABLE MORSE (for logging / debugging)
  // ═════════════════════════════════════════════════════════════════════════

  /// Returns the Morse representation of [text], e.g. `"SOS" → "... --- ..."`.
  static String textToMorseString(String text) {
    return text
        .toUpperCase()
        .split('')
        .map((c) => _alphabet[c] ?? '')
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  /// Decodes a sequence of tap durations into the closest Morse letter.
  /// Returns `'?'` if no match is found.
  static String tapsToLetter(List<int> tapDurationsMs) {
    final morse = tapDurationsMs
        .map((d) => d < tapThresholdMs ? '.' : '-')
        .join();
    return _alphabet.entries
        .firstWhere((e) => e.value == morse, orElse: () => const MapEntry('?', ''))
        .key;
  }
}
