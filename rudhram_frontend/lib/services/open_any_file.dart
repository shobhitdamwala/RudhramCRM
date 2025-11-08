import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class OpenAnyFile {
  /// Opens a local file path with open_file.
  static Future<OpenResult> openLocal(String path) async {
    return OpenFile.open(path);
  }

  /// Downloads a remote URL to temp and opens it.
  /// Returns the local file path it saved to.
  static Future<String> openFromUrl(String url, {String? suggestedName}) async {
    final bytes = await http.get(Uri.parse(url));
    if (bytes.statusCode != 200) {
      throw Exception('Failed to download: ${bytes.statusCode}');
    }

    final dir = await getTemporaryDirectory();
    final fname = suggestedName ??
        url.split('?').first.split('/').last.trim().replaceAll('%20', ' ');
    final file = File('${dir.path}/$fname');

    await file.writeAsBytes(bytes.bodyBytes);
    await OpenFile.open(file.path);
    return file.path;
  }
}
