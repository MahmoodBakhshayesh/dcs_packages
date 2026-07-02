import 'package:dcs_mrz/dcs_mrz.dart';

void main() {
  final document = MrzTd3Document.parse(
    'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
    'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
  );
  print('${document.primaryIdentifier}, valid=${document.valid}');
}
