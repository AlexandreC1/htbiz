import 'dart:io';

Future<bool> networkAvailable() async {
  final addresses = await InternetAddress.lookup('supabase.co')
      .timeout(const Duration(seconds: 4));
  return addresses.any((address) => address.rawAddress.isNotEmpty);
}
