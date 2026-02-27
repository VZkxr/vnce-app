import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('../datos.json');
  final jsonString = file.readAsStringSync();
  final data = jsonDecode(jsonString) as List;
  final item = data.firstWhere((e) => e['tmdbId'] == 1061474);
  print('STREAM URL: ${item['streamUrl']}');
}
