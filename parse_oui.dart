import 'dart:io';
import 'dart:convert';

void main() async {
  final file = File('assets/oui.txt');
  if (!await file.exists()) {
    print('oui.txt not found');
    return;
  }

  final lines = await file.readAsLines();
  final Map<String, String> vendors = {};

  final hexRegex = RegExp(r'^([0-9A-F]{2}-[0-9A-F]{2}-[0-9A-F]{2})\s+\(hex\)\s+(.*)$');

  for (final line in lines) {
    final match = hexRegex.firstMatch(line.trim());
    if (match != null) {
      final mac = match.group(1)!.replaceAll('-', ':');
      final vendor = match.group(2)!.trim();
      vendors[mac] = vendor;
    }
  }

  final outFile = File('assets/mac_vendors.json');
  await outFile.writeAsString(jsonEncode(vendors));
  print('Wrote ${vendors.length} vendors to mac_vendors.json');
}
