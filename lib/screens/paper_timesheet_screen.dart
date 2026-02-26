import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:flutter/material.dart';

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
/// 1. Header 1122×40  2. Footer 1122×34  3. Period 900×720 (left)
/// 4. Admin Header 202×20, Admin 182×560, Admin Days 20×560, Admin Bottom 202×140 (right)  5. Border 20×720 (right).
class PaperTimesheetScreen extends StatelessWidget {
  const PaperTimesheetScreen({super.key});

  static const double _headerWidth = 1122;
  static const double _headerHeight = 40;
  static const double _footerWidth = 1122;
  static const double _footerHeight = 34;
  static const double _periodWidth = 900;
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
  static const double _adminBorderWidth = 20.0;
  static const double _adminBorderHeight = 720.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paper Timesheet (Template)'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
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
                      _section('Office', _adminWidth, _adminHeaderHeight),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAdminGrid(),
                          _buildAdminDays(),
                        ],
                      ),
                      _section('Admin Bottom', _adminWidth, _adminBottomHeight),
                    ],
                  ),
                  Container(
                    width: _adminBorderWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.red, width: 1),
                    ),
                  ),
                ],
                ),
              ),
              _buildFooter(),
            ],
            ),
          ),
        ),
      ),
    );
  }

  /// Header: 1122×40. Print border 16px L/R; 10px unused top, 30px text row.
  /// Proportional to: 16, 80, 309, 120, 152, 120, 299, 16 (scaled to fit 1122 with 7 dividers).
  Widget _buildHeader() {
    const topPadding = 10.0;
    const totalContent = 1113.0; // 1120 - 7 dividers
    const specTotal = 1122.0; // 16+80+309+120+152+120+299+16
    const scale = totalContent / specTotal;
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
        border: Border.all(color: Colors.red, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: topPadding),
        child: Row(
            children: [
              SizedBox(width: widths[0]),
              _headerDivider(),
              _headerCell(widths[1], labels[0], bold: true, isData: false),
              _headerDivider(),
              _headerCell(widths[2], values[0], bold: false, isData: true),
              _headerDivider(),
              _headerCell(widths[3], labels[1], bold: true, isData: false),
              _headerDivider(),
              _headerCell(widths[4], values[1], bold: false, isData: true),
              _headerDivider(),
              _headerCell(widths[5], labels[2], bold: true, isData: false),
              _headerDivider(),
              _headerCell(widths[6], values[2], bold: false, isData: true),
              _headerDivider(),
              SizedBox(width: widths[7]),
            ],
        ),
      ),
    );
  }

  Widget _headerDivider() {
    return Container(
      width: 1,
      height: 30,
      color: Colors.white,
    );
  }

  Widget _headerCell(double w, String text, {bool bold = false, bool isData = false}) {
    return SizedBox(
      width: w,
      height: 30,
      child: Align(
        alignment: isData ? Alignment.center : Alignment.centerRight,
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

  /// Footer: 1122×34. Print border 20px L/R; 18px text row, 16px unused bottom.
  /// Text: PW - Paperwork, ET - Extra Travel, OC - On Call, MS - Miscellaneous, etc.
  Widget _buildFooter() {
    const footerText =
        'PW - Paperwork, ET - Extra Travel, OC - On Call, MS - Miscellaneous, '
        'NW - Non Worked Hours, EA - Eating Allowance, FT - Flat Time, '
        'TH - Time & Half, DT - Double Time, CM - Country Money';
    const textHeight = 18.0;
    const bottomPadding = 16.0;
    const horizontalPadding = 19.0;

    return Container(
      width: _footerWidth,
      height: _footerHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.red, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: horizontalPadding,
          right: horizontalPadding,
          bottom: bottomPadding,
        ),
        child: Align(
          alignment: Alignment.center,
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
        border: Border.all(color: Colors.red, width: 1),
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
              border: Border.all(color: Colors.black, width: 1),
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

  Widget _section(String name, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.red, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '$name\n${width.toInt()} × ${height.toInt()}',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 15,
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
  static const double _periodWidth = 900;
  static const double _lineW = 1.0;
  static const double _tableTopW = 1.0;
  static const double _tableBottomW = 0.0;
  static const double _periodLeftBorderW = 2.0;
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

  static const double _columnAWidth = 20.0;
  static const double _periodDayColumnWidth = 30.0;
  /// Column widths: col A = 20, Day column = 30, table cols = 850 (17 columns: Project 190, Job No. 60, Start/Break/Finish 40 each, Plant 1–6 + Mob 1–4 @ 40 each, Travel 40, Check 40).
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
    final periodHeaderSectionHeight = _tableTopW + _periodHeaderRowHeight + _periodBottomBorderW;
    const minPeriodHeight = 720.0;
    final contentHeight = periodHeaderSectionHeight + dataTotalHeight;
    final sectionHeight = contentHeight.clamp(minPeriodHeight, double.infinity); // min 720 so no gap to footer
    final effectiveTableHeight = (sectionHeight - periodHeaderSectionHeight).clamp(0.0, dataTotalHeight); // one body height for table and weekday column
    final tableWidth = _periodWidth - _columnAWidth - _periodDayColumnWidth; // 850

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

    // Period Header: single table 880 px wide with "Day" (30 px) as first column then Project..Check (17 columns).
    final headerColumnWidths = <int, double>{0: _periodDayColumnWidth};
    _tableColWidths().forEach((k, v) => headerColumnWidths[k + 1] = v);
    final periodHeaderSection = SizedBox(
      width: tableWidth + _periodDayColumnWidth,
      child: Container(
        color: Colors.white,
        child: Table(
          border: TableBorder(
            left: BorderSide(color: Colors.black, width: _periodLeftBorderW), // Period Header: 2 px left border
            top: BorderSide(color: Colors.black, width: _tableTopW),
            right: BorderSide(color: Colors.black, width: _lineW),
            bottom: BorderSide(color: Colors.black, width: _periodBottomBorderW),
            horizontalInside: BorderSide(color: Colors.black, width: _horizontalInsideW),
            verticalInside: BorderSide(color: Colors.black, width: _verticalInsideW),
          ),
          columnWidths: headerColumnWidths.map((k, v) => MapEntry(k, FixedColumnWidth(v))),
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
                PaperTimesheetScreen.cell('Plant 1', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Plant 2', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Plant 3', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Plant 4', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Plant 5', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Plant 6', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Mob 1', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Mob 2', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Mob 3', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Mob 4', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Travel', _periodHeaderRowHeight, bold: true),
                PaperTimesheetScreen.cell('Check', _periodHeaderRowHeight, bold: true),
              ],
            ),
          ],
        ),
      ),
    );

    // Data rows (all visible entries; Day column is separate so 17 cells per row). Internal horizontal lines 1 px total (bottom only).
    final tableRows = <TableRow>[];
    for (var i = 0; i < dataEntries.length; i++) {
      final r = dataEntries[i].value;
      final h = dataRowHeights[i];
      final rowBorder = Border(
        bottom: BorderSide(color: Colors.black, width: _lineW),
      );
      final rowDecoration = BoxDecoration(color: Colors.white, border: rowBorder);
      tableRows.add(TableRow(
        decoration: rowDecoration,
        children: List.generate(17, (_) => SizedBox(height: h)),
      ));
    }

    // Column A: 20 px left strip – header row "0" then data row indices. Trim last row when constrained to avoid RenderFlex overflow.
    final columnAHeaderHeight = _tableTopW + _periodHeaderRowHeight;
    final columnADesiredHeight = columnAHeaderHeight + _tableTopW + dataRowHeights.fold<double>(0.0, (s, h) => s + h);
    final columnASection = LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        final overflow = (columnADesiredHeight - available).clamp(0.0, double.infinity);
        final rowHeights = List<double>.from(dataRowHeights);
        if (overflow > 0 && rowHeights.isNotEmpty) {
          final lastIdx = rowHeights.length - 1;
          rowHeights[lastIdx] = (rowHeights[lastIdx]! - overflow).clamp(1.0, double.infinity);
        }
        final contentHeight = columnAHeaderHeight + _tableTopW + rowHeights.fold<double>(0.0, (s, h) => s + h);
        return SizedBox(
          width: _columnAWidth,
          height: contentHeight,
          child: Container(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: _tableTopW),
                SizedBox(
                  height: _periodHeaderRowHeight,
                  child: Center(
                    child: Text(
                      _rowIndexLabel(0),
                      style: const TextStyle(fontSize: 10, color: Colors.black),
                    ),
                  ),
                ),
                for (var i = 0; i < dataEntries.length; i++)
                  SizedBox(
                    height: rowHeights[i],
                    child: Center(
                      child: Text(
                        _rowIndexLabel(dataEntries[i].key + 1),
                        style: const TextStyle(fontSize: 10, color: Colors.black),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

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

    // Weekday column: same height as Period table (effectiveTableHeight); no top border; 7 sections scaled by day row counts; 2 px bottom/left border.
    const dayColumnHorizontalBorderW = 1.0; // internal horizontal borders in Weekday column
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            columnASection,
            SizedBox(
              height: sectionHeight,
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
          ],
        ),
      ),
    );
  }
}
