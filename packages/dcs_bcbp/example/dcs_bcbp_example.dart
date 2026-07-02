import 'package:dcs_bcbp/dcs_bcbp.dart';

void main() {
  final data = BcbpData.parse(
    'M1DOE/JOHN            EABC1234IKADXB123Y012A0001'.padRight(60),
  );
  print('${data.passengerName.surname}: ${data.legs.single.origin}-${data.legs.single.destination}');
}
