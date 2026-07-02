import 'package:dcs_common/dcs_common.dart';

void main() {
  const endpoint = DcsEndpoint(host: '127.0.0.1', port: 4000);
  print('CUPPS endpoint: $endpoint valid=${endpoint.isValid}');
}
