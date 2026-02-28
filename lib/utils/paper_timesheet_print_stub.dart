/// Stub: paper timesheet print is only supported on web (opens print dialog; user can Save as PDF).
Future<bool> printPaperTimesheet() async => false;

/// Stub: no-op on non-web.
void openTimesheetPrintWindow(String mode) {}

/// Stub: no-op on non-web.
void resizePrintWindowTo(int width, int height) {}

/// Stub: no-op on non-web.
void forcePrintViewportSize() {}
