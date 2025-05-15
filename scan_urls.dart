import 'dart:io';

final List<String> suspiciousDomains = [
  'jsonplaceholder.typicode.com',
  'firestore.googleapis.com',
  'riogas.uy',
];

void main() async {
  final directory = Directory.current;

  print('🔍 Buscando URLs en archivos .dart en: ${directory.path}\n');

  final dartFiles = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  final urlRegex = RegExp(r'''["']https?:\/\/[^"']+["']''');

  for (final file in dartFiles) {
    final lines = await file.readAsLines();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final matches = urlRegex.allMatches(line);
      for (final match in matches) {
        final url = match.group(0)?.replaceAll('"', '').replaceAll("'", '');
        if (url != null) {
          final isSuspicious = suspiciousDomains.any((d) => url.contains(d));
          print(
              '${isSuspicious ? "🚨" : "🔗"} ${file.path} (línea ${i + 1}): $url');
        }
      }
    }
  }

  print('\n✅ Análisis completado.');
}
