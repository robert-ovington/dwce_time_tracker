/// Stub: picking list print is only supported on web (opens print dialog).
Future<bool> printPickingListByUser({
  required List<({String userName, String dateStr, List<Map<String, dynamic>> items})> groups,
  required String Function(Map<String, dynamic>) sizeDisplay,
  required String Function(String?) ppeName,
}) async => false;

Future<bool> printPickingListByItem({
  required List<Map<String, dynamic>> rows,
}) async => false;
