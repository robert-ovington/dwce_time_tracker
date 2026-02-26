// IO (mobile/desktop) implementation
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> saveTextFile({
  required String filename,
  required String contents,
  required String mimeType,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsString(contents);
  return file.path;
}

