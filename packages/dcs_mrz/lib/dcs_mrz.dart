/// Passport MRZ parsing and validation helpers.
library;

class MrzParseException implements Exception {
  const MrzParseException(this.message);

  final String message;

  @override
  String toString() => 'MrzParseException: $message';
}

class MrzTd3Document {
  const MrzTd3Document({
    required this.documentCode,
    required this.issuingState,
    required this.primaryIdentifier,
    required this.secondaryIdentifier,
    required this.documentNumber,
    required this.nationality,
    required this.birthDate,
    required this.sex,
    required this.expiryDate,
    required this.personalNumber,
    required this.valid,
  });

  final String documentCode;
  final String issuingState;
  final String primaryIdentifier;
  final String secondaryIdentifier;
  final String documentNumber;
  final String nationality;
  final String birthDate;
  final String sex;
  final String expiryDate;
  final String personalNumber;
  final bool valid;

  static MrzTd3Document parse(String line1, String line2) {
    final first = _normalize(line1);
    final second = _normalize(line2);
    if (first.length != 44 || second.length != 44) {
      throw const MrzParseException('TD3 MRZ requires two 44-character lines.');
    }

    final names = first.substring(5).split('<<');
    final documentNumber = second.substring(0, 9);
    final birthDate = second.substring(13, 19);
    final expiryDate = second.substring(21, 27);
    final personalNumber = second.substring(28, 42);

    final valid =
        checkDigit(documentNumber) == second[9] &&
        checkDigit(birthDate) == second[19] &&
        checkDigit(expiryDate) == second[27] &&
        checkDigit(personalNumber) == second[42];

    return MrzTd3Document(
      documentCode: first.substring(0, 2).replaceAll('<', ''),
      issuingState: first.substring(2, 5).replaceAll('<', ''),
      primaryIdentifier: names.first.replaceAll('<', ' ').trim(),
      secondaryIdentifier: names.length > 1
          ? names.skip(1).join(' ').replaceAll('<', ' ').trim()
          : '',
      documentNumber: documentNumber.replaceAll('<', ''),
      nationality: second.substring(10, 13).replaceAll('<', ''),
      birthDate: birthDate,
      sex: second.substring(20, 21),
      expiryDate: expiryDate,
      personalNumber: personalNumber.replaceAll('<', ''),
      valid: valid,
    );
  }
}

String checkDigit(String value) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < value.length; i += 1) {
    sum += _mrzValue(value.codeUnitAt(i)) * weights[i % weights.length];
  }
  return (sum % 10).toString();
}

String _normalize(String line) => line.trim().toUpperCase();

int _mrzValue(int codeUnit) {
  if (codeUnit >= 48 && codeUnit <= 57) return codeUnit - 48;
  if (codeUnit >= 65 && codeUnit <= 90) return codeUnit - 55;
  if (codeUnit == 60) return 0;
  throw const MrzParseException('MRZ contains an unsupported character.');
}
