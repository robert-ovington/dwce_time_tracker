// Web: open print dialog. User can print or choose "Save as PDF".
// The formatted area is 1122×794 px; use landscape and "Fit to page" (or "Actual size") for best results.
import 'dart:html' as html;

Future<bool> printPaperTimesheet() async {
  try {
    html.window.print();
    return true;
  } catch (e) {
    return false;
  }
}

/// Exact size of the upscaled print content. Window and viewport must match this so content
/// is not centered (which would show "left half of content on right half of screen").
const int printViewportWidth = 2156;
const int printViewportHeight = 1520;

/// Opens the app in a new window with ?print=margins so the first print uses the correct layout.
/// Window is opened at print content size so Flutter's viewport matches and content is not offset.
void openTimesheetPrintWindow(String mode) {
  assert(mode == 'margins' || mode == 'centered');
  final uri = Uri.base;
  final url = '${uri.origin}${uri.path}?print=$mode';
  html.window.open(
    url,
    '_blank',
    'noopener,noreferrer,width=$printViewportWidth,height=$printViewportHeight',
  );
}

/// Resizes the current window to the given size. Used by the print-only view so the
/// viewport matches the scaled content and the full page is captured when printing.
void resizePrintWindowTo(int width, int height) {
  try {
    html.window.resizeTo(width, height);
  } catch (_) {
    // Ignore: some browsers block resizeTo
  }
}

/// Force document and body to exact print viewport size and notify Flutter to re-layout.
/// Call when the print-only view loads so the viewport matches content even if the
/// window was not opened at the right size (e.g. browser ignored window.open features).
/// This prevents the engine from centering the content in a larger canvas (which causes
/// "left half of content on right half of screen").
void forcePrintViewportSize() {
  final doc = html.document;
  doc.documentElement.classes.add('print-timesheet-view');
  final body = doc.body;
  if (body == null) return;
  body.style.width = '${printViewportWidth}px';
  body.style.height = '${printViewportHeight}px';
  body.style.minWidth = '${printViewportWidth}px';
  body.style.minHeight = '${printViewportHeight}px';
  body.style.maxWidth = '${printViewportWidth}px';
  body.style.maxHeight = '${printViewportHeight}px';
  body.style.margin = '0';
  body.style.padding = '0';
  body.style.overflow = 'hidden';
  body.style.position = 'absolute';
  body.style.left = '0';
  body.style.top = '0';
  html.window.dispatchEvent(html.Event('resize'));
}
