// Web: open HTML in new window and trigger print (user can Save as PDF).
// Uses Blob URL + script-in-page so print() runs in the new window (avoids "user gesture" block).
import 'dart:html' as html;

/// Set to true to log steps to the browser console (F12 -> Console) for diagnosis.
bool _debugPrint = true;
void _log(String msg) {
  if (_debugPrint) {
    // ignore: avoid_print
    print('[PickingListPrint] $msg');
  }
}

Future<bool> printPickingListByUser({
  required List<({String userName, String dateStr, List<Map<String, dynamic>> items})> groups,
  required String Function(Map<String, dynamic>) sizeDisplay,
  required String Function(String?) ppeName,
}) async {
  _log('printPickingListByUser called, groups: ${groups.length}');
  final buffer = StringBuffer();
  buffer.writeln('<!DOCTYPE html><html><head><meta charset="utf-8"><title>PPE Picking List by User</title>');
  buffer.writeln(_tableStyles);
  buffer.writeln('</head><body>');
  for (final g in groups) {
    buffer.writeln('<h3>${_escape(g.userName)}</h3>');
    buffer.writeln('<p>Requested: ${_escape(g.dateStr)}</p>');
    buffer.writeln('<table><thead><tr><th>PPE Item</th><th class="c">Size</th><th class="c">Required</th><th class="c">Picked</th></tr></thead><tbody>');
    for (final r in g.items) {
      final name = ppeName(r['ppe_id']?.toString());
      final size = sizeDisplay(r);
      final qty = r['quantity'];
      final qtyStr = (qty is int) ? '$qty' : (qty != null ? qty.toString() : '1');
      buffer.writeln('<tr><td>${_escape(name)}</td><td class="c">${_escape(size)}</td><td class="c">${_escape(qtyStr)}</td><td class="c"></td></tr>');
    }
    buffer.writeln('</tbody></table>');
  }
  buffer.writeln(_printScript);
  buffer.writeln('</body></html>');
  final htmlContent = buffer.toString();
  _log('HTML length: ${htmlContent.length}');
  _openAndPrint(htmlContent);
  return true;
}

Future<bool> printPickingListByItem({
  required List<Map<String, dynamic>> rows,
}) async {
  _log('printPickingListByItem called, rows: ${rows.length}');
  final buffer = StringBuffer();
  buffer.writeln('<!DOCTYPE html><html><head><meta charset="utf-8"><title>PPE Picking List by Item</title>');
  buffer.writeln(_tableStyles);
  buffer.writeln('</head><body>');
  buffer.writeln('<h2>PPE Picking List (By Item)</h2>');
  buffer.writeln('<table><thead><tr><th>PPE Item</th><th class="c">Size</th><th class="c">Required</th><th class="c">Picked</th></tr></thead><tbody>');
  for (final row in rows) {
    buffer.writeln('<tr><td>${_escape(row['name'] as String)}</td><td class="c">${_escape(row['size'] as String)}</td><td class="c">${row['qty']}</td><td class="c"></td></tr>');
  }
  buffer.writeln('</tbody></table>');
  buffer.writeln(_printScript);
  buffer.writeln('</body></html>');
  final htmlContent = buffer.toString();
  _log('HTML length: ${htmlContent.length}');
  _openAndPrint(htmlContent);
  return true;
}

/// Inline script: when the new window loads, call print(). Running in the new document avoids async user-gesture block.
const String _printScript = r'<script>window.onload=function(){try{window.print();}catch(e){console.error("Print failed:",e);}}</script>';

/// Table styles to match popup: PPE Item left-aligned; Size, Required, Picked center-aligned; padding 12px; header grey; font sizes 20/22.
const String _tableStyles = '''<style>
body{font-family:sans-serif;padding:32px;font-size:20px;}
h2{font-size:28px;} h3{font-size:28px;} p{font-size:24px;}
table{border-collapse:collapse;margin:12px 0;width:100%;}
th,td{border:1px solid #333;padding:12px;}
th{background:#ddd;font-size:22px;font-weight:bold;}
td{font-size:20px;}
th.c,td.c{text-align:center;}
th:first-child,td:first-child{text-align:left;}
</style>''';

String _escape(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

void _openAndPrint(String htmlContent) {
  try {
    _log('Creating Blob and URL...');
    final blob = html.Blob([htmlContent], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    _log('Opening new window with Blob URL...');
    final win = html.window.open(url, '_blank', 'noopener,noreferrer');
    if (win == null) {
      _log('ERROR: window.open returned null (popup may be blocked)');
      html.Url.revokeObjectUrl(url);
      return;
    }
    _log('New window opened; print will run when document loads.');
    // Revoke URL after a delay so the new window has time to load
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
  } catch (e, st) {
    _log('ERROR: $e');
    _log('Stack: $st');
  }
}
