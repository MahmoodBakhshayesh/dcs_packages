import 'package:dcs_baggage/dcs_baggage.dart';

void main() {
  const tag = BaggageTag(airlineNumericCode: '123', serialNumber: '456789');
  print('Bag tag ${tag.value} valid=${tag.isValid}');
}
