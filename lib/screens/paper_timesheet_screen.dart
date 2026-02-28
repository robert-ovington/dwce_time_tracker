import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/utils/paper_timesheet_print.dart' show forcePrintViewportSize, openTimesheetPrintWindow, printPaperTimesheet;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Shown when the app is opened with ?print=margins (new window). Layout is trimmed 20px on all sides.
class PaperTimesheetPrintOnlyView extends StatefulWidget {
  const PaperTimesheetPrintOnlyView({super.key});

  @override
  State<PaperTimesheetPrintOnlyView> createState() => _PaperTimesheetPrintOnlyViewState();
}

class _PaperTimesheetPrintOnlyViewState extends State<PaperTimesheetPrintOnlyView> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      forcePrintViewportSize();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        forcePrintViewportSize();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        forcePrintViewportSize();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        await printPaperTimesheet();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const PaperTimesheetScreen(printOnly: true);
  }
}

/// Row descriptor for Period section. Horizontal lines are row borders (no separate Line rows).
class PeriodRowSpec {
  PeriodRowSpec({
    required this.type,
    required this.rowHeight,
    required this.borderBottomWidth,
    this.borderTopWidth = 0,
    required this.visible,
  });
  /// 'Header' or day name (Monday..Sunday).
  final String type;
  /// Row height in nominal units (scaled to fit 720px).
  final double rowHeight;
  /// Bottom border width in px (the horizontal line under this row).
  final double borderBottomWidth;
  /// Top border width in px (e.g. 4 for first row so top line is not doubled with table border).
  final double borderTopWidth;
  bool visible;
}

/// Paper timesheet – five sections with red border each, exact sizes. Scrollable so no overflow.
/// 1. Header 1078×20  2. Footer 1078×20  3. Period 876×720 (Day 26px, table 850px)  4. Admin 202×… (no right margin)
/// 4. Admin Header 202×20, Admin 182×560, Admin Days 20×560, Admin Bottom 202×140 (right)  5. Border 20×720 (right).
class PaperTimesheetScreen extends StatelessWidget {
  const PaperTimesheetScreen({super.key, this.printOnly = false});

  /// When true, build only the timesheet content (no AppBar). Full page fits in viewport for reliable print.
  final bool printOnly;

  static const double _headerWidth = 1078; // Weekday (26) + Period table (850) + Admin/Office (202)
  static const double _headerHeight = 20;
  static const double _footerWidth = 1078;
  static const double _footerHeight = 20;
  static const double _periodWidth = 876;
  static const double _periodHeight = 720;
  static const double _adminWidth = 202;
  static const double _adminHeaderHeight = 20.0;
  static const double _adminMainHeight = 560.0; // 580 - 20 (Admin Header)
  static const double _adminMainWidth = 182.0;  // 202 - 20 (Admin Days)
  static const double _adminDaysWidth = 20.0;
  static const double _adminDaysSectionHeight = 80.0;
  static const List<String> _adminDayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const double _adminBottomHeight = 140;
  static const double _adminBorderHeight = 720.0;

  /// Print view: 2x scale for resolution. Page size is fixed in HTML (2156×1520) so display area matches.
  static const double _printScale = 2.0;

  @override
  Widget build(BuildContext context) {
    if (printOnly) {
      const contentWidth = _headerWidth;
      const contentHeight = _headerHeight + _adminBorderHeight + _footerHeight; // 760
      final scaledWidth = contentWidth * _printScale;
      final scaledHeight = contentHeight * _printScale;
      return Scaffold(
        backgroundColor: Colors.white,
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: scaledWidth,
            height: scaledHeight,
            child: Transform.scale(
              scale: _printScale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: buildBodyContent(),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paper Timesheet (Template)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print / Save as PDF (trimmed 20px on all sides)',
            onPressed: () async {
              if (kIsWeb) {
                openTimesheetPrintWindow('margins');
              } else {
                final ok = await printPaperTimesheet();
                if (context.mounted && !ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Print is available on web: use the Print button, then choose "Save as PDF". Layout is trimmed 20px on all sides; use landscape and "Fit to page" for best results.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: buildBodyContent(),
          ),
        ),
      ),
    );
  }

  /// The timesheet content (header + middle row + footer) for both normal and print view.
  Widget buildBodyContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        SizedBox(
          height: _adminBorderHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PeriodSectionWidget(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _section(
                    'Office',
                    _adminWidth,
                    _adminHeaderHeight,
                    borderColor: Colors.black,
                    borderWidthTop: 2,
                    borderWidthRight: 2,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAdminGrid(),
                      _buildAdminDays(),
                    ],
                  ),
                  _buildAdminBottomSection(),
                ],
              ),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  /// Header: 1078×20. 16px text row.
  /// Proportional to: 16, 80, 309, 120, 152, 120, 299, 16 (scaled to fit 1078 with 7 dividers).
  Widget _buildHeader() {
    const textRowHeight = 16.0;
    final totalContent = _headerWidth - 7.0; // width minus 7 dividers
    const specTotal = 1122.0; // 16+80+309+120+152+120+299+16
    final scale = totalContent / specTotal;
    final widths = [
      16 * scale, 80 * scale, 309 * scale, 120 * scale,
      152 * scale, 120 * scale, 299 * scale, 16 * scale,
    ];

    const labels = ['Employer:', 'Week Beginning:', 'Employee Name:'];
    const values = ['FELLONWOOD LIMITED', 'Mon 00/00/0000', 'Employee Name'];

    return Container(
      width: _headerWidth,
      height: _headerHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Row(
          children: [
            SizedBox(width: widths[0]),
            _headerDivider(textRowHeight),
            _headerCell(widths[1], labels[0], textRowHeight, bold: true, isData: false),
            _headerDivider(textRowHeight),
            _headerCell(widths[2], values[0], textRowHeight, bold: false, isData: true),
            _headerDivider(textRowHeight),
            _headerCell(widths[3], labels[1], textRowHeight, bold: true, isData: false),
            _headerDivider(textRowHeight),
            _headerCell(widths[4], values[1], textRowHeight, bold: false, isData: true),
            _headerDivider(textRowHeight),
            _headerCell(widths[5], labels[2], textRowHeight, bold: true, isData: false),
            _headerDivider(textRowHeight),
            _headerCell(widths[6], values[2], textRowHeight, bold: false, isData: true),
            _headerDivider(textRowHeight),
            SizedBox(width: widths[7]),
          ],
        ),
      ),
    );
  }

  Widget _headerDivider(double height) {
    return Container(
      width: 1,
      height: height,
      color: Colors.white,
    );
  }

  Widget _headerCell(double w, String text, double height, {bool bold = false, bool isData = false}) {
    return SizedBox(
      width: w,
      height: height,
      child: Align(
        alignment: isData ? Alignment.topCenter : Alignment.topRight,
        child: Text(
          text,
          textAlign: isData ? TextAlign.center : TextAlign.right,
          style: TextStyle(
            fontSize: isData ? 15 : 12,
            color: Colors.black,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Footer: 1078×20. 14px text row.
  /// Text: PW - Paperwork, ET - Extra Travel, OC - On Call, MS - Miscellaneous, etc.
  Widget _buildFooter() {
    const footerText =
        'PW - Paperwork, ET - Extra Travel, OC - On Call, MS - Miscellaneous, '
        'NW - Non Worked Hours, EA - Eating Allowance, FT - Flat Time, '
        'TH - Time & Half, DT - Double Time, CM - Country Money';
    const textHeight = 14.0;

    return Container(
      width: _footerWidth,
      height: _footerHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: textHeight,
          child: Text(
            footerText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  static Widget cell(String text, double h, {bool bold = false}) {
    return SizedBox(
      height: h,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: Colors.black,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Admin grid: 7 weekdays × (6 cols A–F × 4 rows). A/C/E = labels, B/D/F = data. Columns 22,34,34,34,22,36 px; row 20 px.
  static const List<String> _adminColALabels = ['PW', 'ET', 'OC', 'MS'];
  static const List<String> _adminColCLabels = ['NW FT', 'NW FH', 'NW DT', 'EA'];
  static const List<String> _adminColELabels = ['FT', 'TH', 'DT', 'CM'];

  Widget _buildAdminGrid() {
    const colWidths = [22.0, 34.0, 34.0, 34.0, 22.0, 36.0];
    const rowHeight = 20.0;
    final rowCount = (_adminMainHeight / rowHeight).floor();

    return Container(
      width: _adminMainWidth,
      height: _adminMainHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Table(
        border: TableBorder.all(color: Colors.black, width: 1),
        columnWidths: {
          for (var i = 0; i < colWidths.length; i++) i: FixedColumnWidth(colWidths[i]),
        },
        children: List.generate(
          rowCount,
          (r) {
            final rowInDay = r % 4;
            final isFourthRow = (r + 1) % 4 == 0;
            return TableRow(
              decoration: isFourthRow
                  ? BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.black, width: 1),
                      ),
                    )
                  : null,
              children: [
                _adminGridCell(rowHeight, _adminColALabels[rowInDay]),
                _adminGridCell(rowHeight, ''),
                _adminGridCell(rowHeight, _adminColCLabels[rowInDay]),
                _adminGridCell(rowHeight, ''),
                _adminGridCell(rowHeight, _adminColELabels[rowInDay]),
                _adminGridCell(rowHeight, ''),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _adminGridCell(double height, String text) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, color: Colors.black),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Admin Days: 7 sections 20×80 px, 1 px border each, weekday labels rotated anticlockwise 90° (Monday top → Sunday bottom).
  Widget _buildAdminDays() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _adminDayNames.length; i++)
          Container(
            width: _adminDaysWidth,
            height: _adminDaysSectionHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: const BorderSide(color: Colors.black, width: 1),
                right: const BorderSide(color: Colors.black, width: 2),
                bottom: const BorderSide(color: Colors.black, width: 1),
                left: const BorderSide(color: Colors.black, width: 1),
              ),
            ),
            alignment: Alignment.center,
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                _adminDayNames[i],
                style: const TextStyle(fontSize: 10, color: Colors.black),
              ),
            ),
          ),
      ],
    );
  }

  /// Admin Section (Bottom): 202×140, 6 cols (A–F) × 4 rows. 1px borders; outer border black.
  /// Col widths (scaled to fit 202 with 1px borders): 39,42,39,42,39,42 → 197 content + 5 = 202.
  /// Row heights: 35 px per row (4 × 35 = 140).
  static const List<String> _adminBottomColALabels = ['PW', 'ET', 'OC', 'MS'];
  static const List<String> _adminBottomColCLabels = ['NW FT', 'NW FH', 'NW DT', 'EA'];
  static const List<String> _adminBottomColELabels = ['FT', 'TH', 'DT', 'CM'];

  Widget _buildAdminBottomSection() {
    const targetColSum = 39 + 42 + 39 + 42 + 39 + 42; // 243
    const verticalBorderPx = 5.0; // 6 columns → 5 internal vertical borders
    final contentWidth = _adminWidth - verticalBorderPx; // 197
    // First and fifth columns −2 px each; third column +4 px (net 0).
    final colWidths = [
      (39 / targetColSum) * contentWidth - 2,
      (42 / targetColSum) * contentWidth,
      (39 / targetColSum) * contentWidth + 4,
      (42 / targetColSum) * contentWidth,
      (39 / targetColSum) * contentWidth - 2,
      (42 / targetColSum) * contentWidth,
    ];
    const rowHeight = 35.0;

    return Container(
      width: _adminWidth,
      height: _adminBottomHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: const BorderSide(color: Colors.black, width: 1),
          right: const BorderSide(color: Colors.black, width: 1),
          bottom: const BorderSide(color: Colors.black, width: 2),
          left: const BorderSide(color: Colors.black, width: 1),
        ),
      ),
      child: Table(
        border: TableBorder.all(color: Colors.black, width: 1),
        columnWidths: {
          for (var i = 0; i < colWidths.length; i++) i: FixedColumnWidth(colWidths[i]),
        },
        children: [
          for (var r = 0; r < 4; r++)
            TableRow(
              children: [
                _adminGridCell(rowHeight, _adminBottomColALabels[r]),
                _adminGridCell(rowHeight, ''),
                _adminGridCell(rowHeight, _adminBottomColCLabels[r]),
                _adminGridCell(rowHeight, ''),
                _adminGridCell(rowHeight, _adminBottomColELabels[r]),
                _adminGridCell(rowHeight, ''),
              ],
            ),
        ],
      ),
    );
  }

  Widget _section(
    String name,
    double width,
    double height, {
    Color borderColor = Colors.black,
    double borderWidthTop = 1,
    double borderWidthRight = 1,
    double borderWidthBottom = 1,
    double borderWidthLeft = 1,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: borderColor, width: borderWidthTop),
          right: BorderSide(color: borderColor, width: borderWidthRight),
          bottom: BorderSide(color: borderColor, width: borderWidthBottom),
          left: BorderSide(color: borderColor, width: borderWidthLeft),
        ),
      ),
      alignment: Alignment.center,
      child: Center(
        child: Text(
          '$name\n${width.toInt()} × ${height.toInt()}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

/// Max 15 rows per day. Row spec: type (Line/Header/weekday), thickness, visible. Scale visible to 720px.
class _PeriodSectionWidget extends StatefulWidget {
  const _PeriodSectionWidget();

  @override
  State<_PeriodSectionWidget> createState() => _PeriodSectionWidgetState();
}

class _PeriodSectionWidgetState extends State<_PeriodSectionWidget> {
  static const double _periodWidth = 876;
  static const double _lineW = 1.0;
  static const double _tableTopW = 1.0;
  static const double _tableBottomW = 0.0;
  static const double _periodLeftBorderW = 2.0;
  static const double _periodHeaderTopBorderW = 2.0;
  static const double _periodBottomBorderW = 2.0;
  static const double _horizontalInsideW = 0.0;
  static const double _verticalInsideW = 1.0;

  static const List<String> _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const Map<String, String> _weekdayShort = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed', 'Thursday': 'Thu',
    'Friday': 'Fri', 'Saturday': 'Sat', 'Sunday': 'Sun',
  };

  late List<PeriodRowSpec> _spec;

  @override
  void initState() {
    super.initState();
    _spec = _buildFallbackSpec();
    _loadSpecFromDb();
  }

  /// Load row spec from public.paper_timesheet_rows (row, type, visible). Fallback to built-in on error.
  Future<void> _loadSpecFromDb() async {
    try {
      final data = await SupabaseService.client
          .from('paper_timesheet_rows')
          .select('row, type, visible')
          .order('row', ascending: true);
      if (data == null || data.isEmpty) return;
      final list = <PeriodRowSpec>[];
      for (final e in data) {
        final type = e['type']?.toString() ?? 'Monday';
        final visible = e['visible'] == true;
        final rowHeight = type == 'Header' ? 17.0 : 18.0;
        list.add(PeriodRowSpec(
          type: type,
          rowHeight: rowHeight,
          borderBottomWidth: _lineW,
          borderTopWidth: 0,
          visible: visible,
        ));
      }
      if (list.isNotEmpty && mounted) {
        setState(() => _spec = list);
      }
    } catch (e) {
      // Keep fallback spec on error
    }
  }

  /// Fallback when DB is unavailable or empty. 15 rows per day; Mon–Fri 7 visible, Sat 3, Sun 1.
  static List<PeriodRowSpec> _buildFallbackSpec() {
    final list = <PeriodRowSpec>[];
    list.add(PeriodRowSpec(type: 'Header', rowHeight: 17, borderBottomWidth: _lineW, borderTopWidth: 0, visible: true));
    for (var d = 0; d < _weekdays.length; d++) {
      final day = _weekdays[d];
      int visibleDataRows = 7;
      if (day == 'Saturday') visibleDataRows = 3;
      if (day == 'Sunday') visibleDataRows = 1;
      for (var i = 0; i < 15; i++) {
        list.add(PeriodRowSpec(
          type: day,
          rowHeight: 18,
          borderBottomWidth: _lineW,
          borderTopWidth: 0,
          visible: i < visibleDataRows,
        ));
      }
    }
    return list;
  }

  static const double _periodDayColumnWidth = 26.0;
  /// Column widths: Day column = 26, table cols = 850 (17 columns: Project 190, Job No. 60, Start/Break/Finish 40 each, Plant 1–6 + Mob 1–4 @ 40 each, Travel 40, Check 40).
  static Map<int, double> _tableColWidths() {
    return {
      0: 190.0, 1: 60.0, 2: 40.0, 3: 40.0, 4: 40.0,
      5: 40.0, 6: 40.0, 7: 40.0, 8: 40.0, 9: 40.0,
      10: 40.0, 11: 40.0, 12: 40.0, 13: 40.0, 14: 40.0,
      15: 40.0, 16: 40.0,
    };
  }

  /// Day column label: 1 row = 3 chars no rotation; 2–3 rows = 3 chars rotated; >3 rows = full name rotated.
  Widget _dayColumnLabel(int visibleRowCount, String dayName) {
    final short = _weekdayShort[dayName] ?? dayName.substring(0, 3);
    final text = visibleRowCount > 3 ? dayName : short;
    final label = Text(
      text,
      style: const TextStyle(fontSize: 10, color: Colors.black),
    );
    if (visibleRowCount == 1) return label;
    return RotatedBox(
      quarterTurns: 3,
      child: label,
    );
  }

  /// Row index label for column A: 0–99 as digits; 100+ as letter + digit (e.g. A0–A9, B0–…) to avoid 3‑digit overflow.
  static String _rowIndexLabel(int rowIndex) {
    if (rowIndex < 100) return '$rowIndex';
    final tens = rowIndex ~/ 10;
    final units = rowIndex % 10;
    final letter = String.fromCharCode(65 + (tens - 10));
    return '$letter$units';
  }

  static const double _periodHeaderRowHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = _spec.asMap().entries.where((e) => e.value.visible).toList();
    if (visibleEntries.isEmpty) return Container(width: _periodWidth, color: Colors.white);

    // Height model: section must be at least 720 so it fills the main Row (no gap to footer). Body = one height for both table and weekday column.
    final dataEntries = visibleEntries.where((e) => e.value.type != 'Header').toList();
    final dataRowHeights = dataEntries.map((e) => e.value.rowHeight.toDouble()).toList();
    final dataTotalHeight = _tableTopW + dataRowHeights.fold<double>(0.0, (s, h) => s + h);
    final periodHeaderSectionHeight = _periodHeaderTopBorderW + _periodHeaderRowHeight + _periodBottomBorderW;
    const minPeriodHeight = 720.0;
    final contentHeight = periodHeaderSectionHeight + dataTotalHeight;
    final sectionHeight = contentHeight.clamp(minPeriodHeight, double.infinity); // min 720 so no gap to footer
    final effectiveTableHeight = (sectionHeight - periodHeaderSectionHeight).clamp(0.0, dataTotalHeight); // one body height for table and weekday column
    final tableWidth = _periodWidth - _periodDayColumnWidth; // 850

    // Per-day visible row heights and row counts (7 weekdays) for the separate Day column.
    final dayHeights = List.filled(7, 0.0);
    final dayRowCounts = List.filled(7, 0);
    for (var i = 0; i < dataEntries.length; i++) {
      final dayIndex = _weekdays.indexOf(dataEntries[i].value.type);
      if (dayIndex >= 0) {
        dayHeights[dayIndex] += dataRowHeights[i];
        dayRowCounts[dayIndex] += 1;
      }
    }
    final dayHeightsSum = dayHeights.fold<double>(0.0, (s, h) => s + h);

    // Period Header: single table 876 px wide. Day (26) then Project..Finish, single "Plant 1" (width Plant 1–6), single "Mob 1" (width Mob 1–4), Travel, Check. Data table unchanged (still 17 cols).
    final tableCols = _tableColWidths();
    final plant1To6Width = tableCols[5]! + tableCols[6]! + tableCols[7]! + tableCols[8]! + tableCols[9]! + tableCols[10]!;
    final mob1To4Width = tableCols[11]! + tableCols[12]! + tableCols[13]! + tableCols[14]!;
    final periodHeaderColumnWidths = <int, double>{
      0: _periodDayColumnWidth,
      1: tableCols[0]!, 2: tableCols[1]!, 3: tableCols[2]!, 4: tableCols[3]!, 5: tableCols[4]!,
      6: plant1To6Width,
      7: mob1To4Width,
      8: tableCols[15]!, 9: tableCols[16]!,
    };
    final periodHeaderSection = SizedBox(
      width: tableWidth + _periodDayColumnWidth,
      child: Container(
        color: Colors.white,
        child: Table(
          border: TableBorder(
            left: BorderSide(color: Colors.black, width: _periodLeftBorderW),
            top: BorderSide(color: Colors.black, width: _periodHeaderTopBorderW),
            right: BorderSide(color: Colors.black, width: _lineW),
            bottom: BorderSide(color: Colors.black, width: _periodBottomBorderW),
            horizontalInside: BorderSide(color: Colors.black, width: _horizontalInsideW),
            verticalInside: BorderSide(color: Colors.black, width: _verticalInsideW),
          ),
          columnWidths: periodHeaderColumnWidths.map((k, v) => MapEntry(k, FixedColumnWidth(v))),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.black, width: _lineW)),
              ),
              children: [
                PaperTimesheetScreen.cell('Day', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Project', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Job No.', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Start', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Break', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Finish', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Plant Number / Hired Plant', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Mobilised Plant', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Travel', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Check', _periodHeaderRowHeight, bold: true),
              ],
            ),
          ],
        ),
      ),
    );

    // Data rows: no bottom between 1 and 104; only last row has bottom. Top: first row (i==0) 0px; 2px above start of each day (key 15,30,45,60,75,90 → display 16,31,46,61,76,91); else 1px.
    final tableRows = <TableRow>[];
    for (var i = 0; i < dataEntries.length; i++) {
      final key = dataEntries[i].key;
      final h = dataRowHeights[i];
      final hasBottom = i == dataEntries.length - 1;
      final topW = i == 0 ? 0.0 : (key % 15 == 0 && key > 0 ? 2.0 : _lineW);
      final bottomW = hasBottom ? _lineW : 0.0;
      final rowBorder = Border(
        top: BorderSide(color: Colors.black, width: topW),
        bottom: BorderSide(color: Colors.black, width: bottomW),
      );
      final rowDecoration = BoxDecoration(color: Colors.white, border: rowBorder);
      tableRows.add(TableRow(
        decoration: rowDecoration,
        children: List.generate(17, (_) => SizedBox(height: h)),
      ));
    }

    final tableSection = SizedBox(
      width: tableWidth,
      height: effectiveTableHeight,
      child: Table(
        border: TableBorder(
          left: BorderSide.none,
          top: BorderSide.none,
          right: BorderSide(color: Colors.black, width: _lineW),
          bottom: BorderSide(color: Colors.black, width: _periodBottomBorderW),
          horizontalInside: BorderSide(color: Colors.black, width: _horizontalInsideW),
          verticalInside: BorderSide(color: Colors.black, width: _verticalInsideW),
        ),
        columnWidths: _tableColWidths().map((k, v) => MapEntry(k, FixedColumnWidth(v))),
        children: tableRows,
      ),
    );

    final periodTableSection = Container(
      width: tableWidth,
      height: effectiveTableHeight,
      color: Colors.white,
      child: tableSection,
    );

    // Weekday column: same height as Period table (effectiveTableHeight); no top border; 7 sections scaled by day row counts; 2 px bottom/left border; 2 px internal borders.
    const dayColumnHorizontalBorderW = 2.0; // internal horizontal borders in Weekday column
    const dayColumnTopBorderW = 0.0; // no top border
    const dayColumnBottomBorderW = 2.0; // bottom border of column
    const dayColumnLeftBorderW = 2.0; // left border of column
    final dataHeight = (effectiveTableHeight - dayColumnTopBorderW).clamp(0.0, double.infinity);
    final scale = dayHeightsSum > 0 ? dataHeight / dayHeightsSum : 1.0;
    final scaledDayHeights = dayHeightsSum > 0
        ? dayHeights.map((h) => h * scale).toList()
        : List.filled(7, dataHeight / 7);
    if (dayHeightsSum > 0 && scaledDayHeights.length == 7) {
      final sumFirst6 = scaledDayHeights.sublist(0, 6).fold<double>(0.0, (s, h) => s + h);
      scaledDayHeights[6] = (dataHeight - sumFirst6).clamp(1.0, double.infinity);
    }
    final periodDayColumn = SizedBox(
      width: _periodDayColumnWidth,
      height: effectiveTableHeight,
      child: Container(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              height: dayColumnTopBorderW,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide.none,
                  left: BorderSide(color: Colors.black, width: dayColumnLeftBorderW),
                  right: BorderSide(color: Colors.black, width: _lineW),
                ),
              ),
            ),
            for (var i = 0; i < 6; i++)
              Container(
                height: scaledDayHeights[i].clamp(1.0, double.infinity),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(color: Colors.black, width: dayColumnLeftBorderW),
                    right: BorderSide(color: Colors.black, width: _lineW),
                    bottom: BorderSide(color: Colors.black, width: dayColumnHorizontalBorderW),
                  ),
                ),
                alignment: Alignment.center,
                child: _dayColumnLabel(dayRowCounts[i], _weekdays[i]),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(color: Colors.black, width: dayColumnLeftBorderW),
                    right: BorderSide(color: Colors.black, width: _lineW),
                    bottom: BorderSide(color: Colors.black, width: dayColumnBottomBorderW),
                  ),
                ),
                alignment: Alignment.center,
                child: _dayColumnLabel(dayRowCounts[6], _weekdays[6]),
              ),
            ),
          ],
        ),
      ),
    );

    return SizedBox(
      width: _periodWidth,
      height: sectionHeight,
      child: ClipRect(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            periodHeaderSection,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  periodDayColumn,
                  periodTableSection,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
