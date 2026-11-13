import 'national_id_ocr.dart';

// Villes tunisiennes courantes (en français et arabe) pour détection automatique du lieu de naissance
const _tunisianCities = [
  'Tunis', 'Sfax', 'Sousse', 'Bizerte', 'Nabeul', 'Kairouan', 'Gabès', 'Gabes',
  'Ariana', 'Ben Arous', 'Monastir', 'Médenine', 'Medenine', 'Mahdia', 'Kasserine',
  'Gafsa', 'Jendouba', 'Zaghouan', 'Siliana', 'Tozeur', 'Kébili', 'Kebili',
  'Tataouine', 'Béja', 'Beja', 'Le Kef', 'Kef', 'La Marsa', 'Carthage', 'Hammamet',
  'Djerba', 'Zarzis', 'Menzel Bourguiba', 'Hammam Lif', 'Radès', 'Rades',
  'تونس', 'صفاقس', 'سوسة', 'بنزرت', 'نابل', 'القيروان', 'قابس', 'أريانة', 'اريانة',
  'بن عروس', 'المنستير', 'مدنين', 'المهدية', 'القصرين', 'قفصة', 'جندوبة', 'زغوان',
  'سليانة', 'توزر', 'قبلي', 'تطاوين', 'باجة', 'الكاف', 'المرسى', 'قرطاج', 'الحمامات',
  'جربة', 'جرجيس', 'منزل بورقيبة', 'حمام الأنف', 'رادس'
];

final _firstNameLabels = [
  RegExp(
    r'^\s*(?:pr[eé]nom(?:\(s\))?|first\s+names?|given\s+names?)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
  RegExp(r'^\s*(?:الإسم|الاسم)\s*[:：\-–]?\s*(.*)$'),
];

final _lastNameLabels = [
  RegExp(
    r'^\s*(?:nom(?:\s+de\s+famille)?|surname|last\s+name)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
  RegExp(r'^\s*(?:اللقب)\s*[:：\-–]?\s*(.*)$'),
];

final _fatherLabels = [
  RegExp(
    r'^\s*(?:إسم\s+الأب\s+والجد|إسم\s+الأب|اسم\s+الاب|الأب|الاب|p[eè]re|father)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
];

final _motherLabels = [
  RegExp(
    r'^\s*(?:إسم\s+الأم\s+ولقبها|إسم\s+الأم|اسم\s+الام|الأم|الام|m[eè]re|mother)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
];

final _placeLabels = [
  RegExp(
    r'^\s*(?:lieu\s+de\s+naissance|place\s+of\s+birth)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
  RegExp(r'^\s*(?:مكان\s+(?:الولادة|الميلاد))\s*[:：\-–]?\s*(.*)$'),
];

final _professionLabels = [
  RegExp(
    r'^\s*(?:المهنة|مهنة|profession|occupation|job)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
];

final _addressLabels = [
  RegExp(
    r'^\s*(?:العنوان|الإقامة|الاقامة|adresse|address)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
];

final _issueDateLabels = [
  RegExp(
    r'^\s*(?:سلمت\s+في|تاريخ\s+الإصدار|تاريخ\s+الاصدار|d[eé]livr[eé]e?\s+le|issue\s+date|date\s+of\s+issue)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
];

final _birthDateLabels = [
  RegExp(
    r'\b(?:date\s+de\s+naissance|date\s+of\s+birth|born\s+on|n[eé]e?\s+le)\b'
    r'\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
  RegExp(r'(?:تاريخ\s+(?:الولادة|الميلاد))\s*[:：\-–]?\s*(.*)$'),
];

final _expirationDateLabels = [
  RegExp(
    r'\b(?:date\s+d.{0,2}(?:expiration|expiry|validity)|date\s+of\s+'
    r'(?:expiration|expiry)|expiration|expiry|expires?|valid\s+until|'
    r'valable\s+jusqu.{0,3})\b\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
  RegExp(r'(?:تاريخ\s+انتهاء\s+الصلاحية)\s*[:：\-–]?\s*(.*)$'),
];

final _documentNumberLabels = [
  RegExp(
    r'^\s*(?:n\s*[°ºo]\s*(?:(?:de\s*)?(?:la\s*)?carte(?:\s+d.{0,3}identit[eé])?|cin)?|'
    r'num[eé]ro\s+(?:de\s+)?(?:la\s+)?carte(?:\s+d.{0,3}identit[eé])?|'
    r'c\.?i\.?n\.?(?:\s*(?:n[°ºo]?|num[eé]ro))?|'
    r'identity\s+card(?:\s+(?:number|no))?|id\s+(?:number|no))'
    r'\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
  RegExp(
    r'^\s*(?:رقم\s+بطاقة\s+التعريف\s+الوطنية|'
    r'رقم\s+بطاقة\s+التعريف|رقم\s+بطاقة|رقم|ب\.?ت\.?و\.?)\s*[:：\-–]?\s*(.*)$',
  ),
];

final _passportNumberLabels = [
  RegExp(
    r'^\s*(?:passport\s*(?:no\.?|number|n[°ºo])|'
    r'passport\s+number|num[eé]ro\s+(?:du\s+)?passeport|'
    r'n[°ºo]\s*(?:du\s+)?passeport)\s*[:：\-–]?\s*(.*)$',
    caseSensitive: false,
  ),
  RegExp(r'^\s*(?:رقم\s+)?جواز\s+السفر\s*[:：\-–]?\s*(.*)$'),
];

final _allFieldLabels = [
  ..._firstNameLabels,
  ..._lastNameLabels,
  ..._fatherLabels,
  ..._motherLabels,
  ..._placeLabels,
  ..._professionLabels,
  ..._addressLabels,
  ..._issueDateLabels,
  ..._documentNumberLabels,
  ..._passportNumberLabels,
  ..._expirationDateLabels,
];

// Regex dates (formats JJ/MM/AAAA, JJ.MM.AAAA, JJ-MM-AAAA)
final _datePattern = RegExp(
  r'(?<!\d)(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{4})(?!\d)|'
  r'(?<!\d)(\d{4})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{1,2})(?!\d)',
);

NationalIdOcrResult parseTunisianNationalIdText(String text) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  String? docNumber = _extractDocumentNumber(lines, text);
  String? firstName = _extractLabeledValue(lines, _firstNameLabels);
  String? lastName = _extractLabeledValue(lines, _lastNameLabels);
  String? birthDate = _extractBirthDate(lines);
  String? place = _extractLabeledValue(lines, _placeLabels) ??
      _extractPlaceFromKnownCities(text) ??
      _extractPlaceFromBirthDateLine(lines);

  return NationalIdOcrResult(
    firstName: firstName,
    lastName: lastName,
    fatherName: _extractLabeledValue(lines, _fatherLabels),
    motherName: _extractLabeledValue(lines, _motherLabels),
    dateOfBirth: birthDate,
    placeOfBirth: place,
    documentNumber: docNumber,
    profession: _extractLabeledValue(lines, _professionLabels),
    address: _extractLabeledValue(lines, _addressLabels),
    issueDate: _extractIssueDate(lines),
    gender: _extractGender(text),
    expirationDate: _extractExpirationDate(lines),
    rawText: text,
  );
}

NationalIdOcrResult parsePassportText(String text) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  return NationalIdOcrResult(
    firstName: _extractLabeledValue(lines, _firstNameLabels),
    lastName: _extractLabeledValue(lines, _lastNameLabels),
    dateOfBirth: _extractBirthDate(lines),
    expirationDate: _extractExpirationDate(lines),
    placeOfBirth: _extractLabeledValue(lines, _placeLabels),
    documentNumber: _extractPassportNumber(lines),
    rawText: text,
  );
}

String? _extractLabeledValue(List<String> lines, List<RegExp> labels) {
  for (var index = 0; index < lines.length; index++) {
    for (final label in labels) {
      final match = label.firstMatch(lines[index]);
      if (match == null) continue;

      final rawInlineValue = match.group(1) ?? '';
      if (rawInlineValue.trim().isNotEmpty) {
        final inlineValue = _cleanValue(rawInlineValue);
        if (inlineValue != null) return inlineValue;
        continue;
      }

      if (index + 1 < lines.length && !_startsWithAnyLabel(lines[index + 1])) {
        return _cleanValue(lines[index + 1]);
      }
    }
  }
  return null;
}

/// Extrait la date de naissance (priorise les dates avant aujourd'hui)
String? _extractBirthDate(List<String> lines) {
  for (var index = 0; index < lines.length; index++) {
    for (final label in _birthDateLabels) {
      final match = label.firstMatch(lines[index]);
      if (match == null) continue;
      final inlineValue = match.group(1) ?? '';
      final inlineDate = _parseBirthDate(inlineValue);
      if (inlineDate != null) return inlineDate;

      if (inlineValue.trim().isEmpty && index + 1 < lines.length) {
        final followingDate = _parseBirthDate(lines[index + 1]);
        if (followingDate != null) return followingDate;
      }
    }
  }

  return null;
}

String? _extractPlaceFromKnownCities(String text) {
  for (final city in _tunisianCities) {
    final pattern = RegExp('\\b${RegExp.escape(city)}\\b', caseSensitive: false);
    if (pattern.hasMatch(text)) {
      return city;
    }
  }
  return null;
}

String? _extractPlaceFromBirthDateLine(List<String> lines) {
  for (final line in lines) {
    final match = RegExp(
      r'(?:\d{1,2}[/.-]\d{1,2}[/.-]\d{4})\s*(?:بـ?|à\s+)?([A-Za-z\u0600-\u06FF\s]{3,30})',
    ).firstMatch(line);
    if (match != null) {
      final candidate = _cleanValue(match.group(1) ?? '');
      if (candidate != null) return candidate;
    }
  }
  return null;
}

String? _extractIssueDate(List<String> lines) {
  for (var index = 0; index < lines.length; index++) {
    for (final label in _issueDateLabels) {
      final match = label.firstMatch(lines[index]);
      if (match == null) continue;
      final inlineValue = match.group(1) ?? '';
      final inlineDate = _parseDate(inlineValue);
      if (inlineDate != null) return _formatDate(inlineDate);

      if (index + 1 < lines.length) {
        final nextDate = _parseDate(lines[index + 1]);
        if (nextDate != null) return _formatDate(nextDate);
      }
    }
  }
  return null;
}

String? _extractGender(String text) {
  if (RegExp(r'\b(?:ذكر|masculin|\bM\b)\b', caseSensitive: false).hasMatch(text)) {
    return 'Masculin';
  }
  if (RegExp(r'\b(?:أنثى|feminin|féminin|\bF\b)\b', caseSensitive: false).hasMatch(text)) {
    return 'Féminin';
  }
  return null;
}

String? _extractExpirationDate(List<String> lines) {
  for (var index = 0; index < lines.length; index++) {
    for (final label in _expirationDateLabels) {
      final match = label.firstMatch(lines[index]);
      if (match == null) continue;
      final inlineValue = match.group(1) ?? '';
      final inlineDate = _parseExpirationDate(inlineValue);
      if (inlineDate != null) return inlineDate;

      if (inlineValue.trim().isEmpty && index + 1 < lines.length) {
        final followingDate = _parseExpirationDate(lines[index + 1]);
        if (followingDate != null) return followingDate;
      }
    }
  }
  return null;
}

/// Extrait le numéro de CIN tunisienne (8 chiffres)
/// Gère la normalisation des caractères OCR (O -> 0, I -> 1, espaces inter-chiffres)
String? _extractDocumentNumber(List<String> lines, String fullText) {
  // 1. Recherche avec labels explicites
  for (var index = 0; index < lines.length; index++) {
    for (final label in _documentNumberLabels) {
      final match = label.firstMatch(lines[index]);
      if (match == null) continue;

      final rawInlineValue = match.group(1) ?? '';
      final num = _parseDocumentNumber(rawInlineValue);
      if (num != null) return num;

      if (index + 1 < lines.length) {
        final nextNum = _parseDocumentNumber(lines[index + 1]);
        if (nextNum != null) return nextNum;
      }
    }
  }

  return null;
}

String? _extractPassportNumber(List<String> lines) {
  final pattern = RegExp(r'(?<![A-Z0-9])[A-Z0-9]{6,12}(?![A-Z0-9])');
  for (var index = 0; index < lines.length; index++) {
    for (final label in _passportNumberLabels) {
      final match = label.firstMatch(lines[index]);
      if (match == null) continue;

      final inlineValue = _normalizeDigits(match.group(1) ?? '').toUpperCase();
      final inlineNumber = pattern.firstMatch(inlineValue);
      if (inlineNumber != null) return inlineNumber.group(0);

      if (inlineValue.trim().isEmpty && index + 1 < lines.length) {
        final nextLine = _normalizeDigits(lines[index + 1]).toUpperCase();
        final nextNumber = pattern.firstMatch(nextLine);
        if (nextNumber != null) return nextNumber.group(0);
      }
    }
  }
  return null;
}

String? _parseBirthDate(String text) {
  final date = _parseDate(text);
  if (date == null || date.isAfter(DateTime.now())) return null;
  return _formatDate(date);
}

String? _parseExpirationDate(String text) {
  final date = _parseDate(text);
  return date == null ? null : _formatDate(date);
}

DateTime? _parseDate(String text) {
  final normalized = _normalizeDigits(text);
  final match = _datePattern.firstMatch(normalized);
  if (match == null) return null;

  final day = int.tryParse(match.group(1) ?? match.group(6) ?? '');
  final month = int.tryParse(match.group(2) ?? match.group(5) ?? '');
  final year = int.tryParse(match.group(3) ?? match.group(4) ?? '');
  if (day == null || month == null || year == null) return null;

  final date = DateTime(year, month, day);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      year < 1920) {
    return null;
  }
  return date;
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String? _parseDocumentNumber(String text) {
  final normalized = _normalizeOcrDigits(text);
  // Recherche 8 chiffres consécutifs
  final match = RegExp(r'(?<!\d)\d{8}(?!\d)').firstMatch(normalized);
  return match?.group(0);
}

String? _cleanValue(String value) {
  final cleaned = value
      .replaceFirst(RegExp(r'^[\s:：\-–]+'), '')
      .replaceFirst(RegExp(r'[\s:：\-–]+$'), '')
      .trim();
  if (cleaned.isEmpty ||
      cleaned.length > 80 ||
      RegExp(r'\d').hasMatch(cleaned) ||
      !_hasNameCharacter(cleaned)) {
    return null;
  }
  return cleaned;
}

bool _hasNameCharacter(String value) =>
    RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(value);

bool _startsWithAnyLabel(String value) =>
    _allFieldLabels.any((label) => label.hasMatch(value)) ||
    _birthDateLabels.any((label) => label.hasMatch(value));

String _normalizeDigits(String text) {
  final result = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      result.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      result.writeCharCode(0x30 + rune - 0x06F0);
    } else {
      result.writeCharCode(rune);
    }
  }
  return result.toString();
}

String _normalizeOcrDigits(String text) {
  final arabicDigitsNormalized = _normalizeDigits(text);
  // Remplace les confusions OCR courantes sur les numéros
  return arabicDigitsNormalized
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('O', '0')
      .replaceAll('o', '0');
}
