# PDF Template Guide: Viewing and Exporting Data from Supabase

This guide explains how to format a PDF template so you can **view** and **export** data from your Supabase database—either in your Flutter app or via a server/Edge Function.

---

## 1. Overview

**Flow:**

1. **Fetch data** from Supabase (tables, RPC, or views).
2. **Map data** into a structured format (e.g. rows, headers, summary fields).
3. **Render** that data into a PDF using a template (layout + styling).
4. **View** (preview in-app) and/or **export** (save file, share).

Your app already uses `saveTextFile()` for CSV export (e.g. in **Admin Staff Summary**). PDF export follows the same idea: build content (PDF bytes instead of CSV text), then save or display it.

---

## 2. Choosing Where to Generate the PDF

| Approach | Best for | Notes |
|----------|----------|--------|
| **Flutter (Dart)** | Mobile/desktop app, simple reports | Use `pdf` + `printing` packages. Data is fetched in-app, PDF built on device. |
| **Supabase Edge Function** | Web-only or heavy reports | Fetch in Edge Function, use a JS/TS PDF lib (e.g. `pdf-lib`, `puppeteer`), return PDF URL or bytes. |
| **External service** | Complex layouts, HTML→PDF | Send data to a service that renders HTML/React to PDF; store result in Supabase Storage. |

For most in-app “export to PDF” flows, **Flutter + `pdf` package** is the simplest and fits your existing export pattern.

---

## 3. HTML-first: Display in HTML, Convert to PDF When Required

Yes, this is a valid option. You **show data in HTML** (styled to match the desired PDF layout), then **convert that HTML to PDF** only when the user exports. Whether it works efficiently on all platforms depends on how you do the conversion.

### 3.1 Why consider HTML-first

- **Single source of truth**: One HTML/CSS template for both on-screen view and PDF. What you see on screen matches the PDF.
- **Easier styling**: Use normal CSS (flexbox, grid, print styles). Designers can work with familiar HTML/CSS.
- **Reuse on web**: On Flutter web, you're already in a browser; showing HTML is natural and conversion can use the same engine.

### 3.2 How it fits your flow

1. Fetch data from Supabase (unchanged).
2. Inject data into an **HTML template** (e.g. replace placeholders or use a tiny templating step).
3. **Display** that HTML in-app (WebView or, on web, an iframe / `HtmlElementView`).
4. When the user taps "Export PDF", **convert** the current HTML to PDF and save or open.

So the "template" is HTML + CSS; the PDF is a rendered snapshot of that HTML.

### 3.3 Efficiency and platform support

| Platform | Display HTML | Convert HTML → PDF | Efficiency notes |
|----------|--------------|--------------------|------------------|
| **Web** | Native (iframe / browser). | `window.print()` → "Save as PDF", or jsPDF + html2canvas, or send HTML to Edge Function. | Very efficient. No extra runtime; print is built-in. |
| **Android** | `webview_flutter`: load HTML in WebView. | Use **PrintManager**: print the WebView and choose "Save as PDF". Or send HTML to Edge Function. | Efficient for display. PDF conversion is either native (no server) or one network call. |
| **iOS** | Same: WebView. | WKWebView print → "Save as PDF", or send HTML to Edge Function. | Same as Android. |
| **Windows / macOS / Linux** | WebView or in-app browser. | Usually: send HTML to **Edge Function** (Puppeteer/Playwright) and get PDF back. Native "print to PDF" from WebView is possible but less uniform. | Display is fine; conversion is most reliable via server so behaviour is consistent. |

So: **displaying** HTML in a format similar to the PDF works well on all platforms. **Converting** to PDF is:

- **Most uniform and predictable**: Use a **Supabase Edge Function** (or other backend) that receives HTML (or URL + data), renders it with a headless browser (e.g. Puppeteer) or an HTML-to-PDF library, and returns the PDF. Then every platform just displays HTML and, on export, posts to that endpoint and saves the returned PDF. Same behaviour everywhere.
- **Efficient without a server**: On **web**, use `window.print()` or a client-side HTML→PDF lib. On **mobile**, use the system "Print → Save as PDF" from the WebView. That avoids a round-trip but quality and layout control (e.g. page breaks) can vary by device.

### 3.4 Practical recommendation for "all platforms"

- **View**: Always render Supabase data in **HTML** in a WebView (or web equivalent), with CSS that matches your desired PDF (same fonts, margins, table layout). Use `@media print { ... }` so the print/PDF output looks right.
- **Export PDF**:
  - **Option A (simplest, consistent)**: From every platform, send the **current HTML** (or a stored template + data) to a **Supabase Edge Function** that runs Puppeteer (or similar) and returns the PDF. Then use your existing `savePdfFile` (or download) to save the bytes. One conversion path, same quality everywhere.
  - **Option B (no server)**: On web use `window.print()` or jsPDF; on mobile use the system "Print → Save as PDF" from the WebView. Fewer dependencies and no server, but layout and behaviour may differ slightly by platform.

So yes: **displaying data in HTML in a format similar to the PDF and converting to PDF when required can work efficiently on all platforms**, especially if you use a small Edge Function for the actual HTML→PDF step. The HTML view is then your single template for both viewing and exporting.

---

## 4. PDF Template Structure (Conceptual)

A “PDF template” here means:

- **Layout**: Where the title, table, summary, and footer go.
- **Placeholders**: Logical spots that get filled with Supabase data (e.g. “report title”, “rows”, “totals”).
- **Styling**: Fonts, colors, spacing, borders.

You don’t edit a literal PDF file; you **describe** the document in code (or HTML for server-side), and the library generates the PDF.

### 4.1 Typical sections

- **Header**: Report name, date range, filters (e.g. week for staff summary).
- **Body**: Tables or blocks of data (e.g. staff rows, totals).
- **Footer**: Page numbers, “Generated from Supabase” or app name.

### 4.2 Data mapping

- One Supabase **row** → one **table row** (or one block).
- Extra fields (totals, date range) → header/summary area.
- Keep column names and order consistent so your template code knows which field goes where.

---

## 5. Formatting a PDF Template in Flutter (Dart)

### 5.1 Add dependencies

In `pubspec.yaml`:

```yaml
dependencies:
  pdf: ^3.10.0
  printing: ^5.11.0
```

- **`pdf`**: Build the PDF document (pages, text, tables, styling).
- **`printing`**: Preview, print, and share (e.g. save to file on IO, open in browser on web).

### 5.2 Build the document from Supabase data

1. **Fetch data** with `SupabaseService.client` (same as your screens):

   ```dart
   final response = await SupabaseService.client
       .from('your_table')
       .select()
       .gte('created_at', startDate)
       .lte('created_at', endDate);
   List<Map<String, dynamic>> rows = List.from(response);
   ```

2. **Create a `pdf.Document`** and add pages:

   ```dart
   final pdfDoc = pdf.Document();
   pdfDoc.addPage(
     pdf.MultiPage(
       build: (context) => [
         pdf.Header(level: 0, child: pdf.Text('Report Title', style: pdf.TextStyle(fontSize: 18))),
         pdf.Table.fromTextArray(
           headerStyle: pdf.TextStyle(fontWeight: pdf.FontWeight.bold),
           data: [
             ['Column A', 'Column B', 'Column C'],
             ...rows.map((r) => [
               r['column_a']?.toString() ?? '',
               r['column_b']?.toString() ?? '',
               r['column_c']?.toString() ?? '',
             ]),
           ],
         ),
       ],
     ),
   );
   ```

3. **Styling**: Use `pdf.ThemeData`, `pdf.TextStyle`, `pdf.TableCell` padding, etc., to match your desired “template” look (fonts, spacing, borders).

### 5.3 View and export

- **Preview**: `Printing.layoutPdf(onLayout: (format) async => pdfDoc.save())`.
- **Save file**: Get bytes with `pdfDoc.save()`, then use your existing export helper (e.g. a new `savePdfFile(bytes, filename)` that writes to the same place as `saveTextFile` on IO, or triggers download on web).

So “formatting the template” in Flutter = **how you compose `pdf.Header`, `pdf.Table`, `pdf.Text`, and styles** in `build` of `pdf.MultiPage`.

---

## 6. Formatting a PDF Template in a Supabase Edge Function

If you prefer PDF generation on the server:

1. **Create an Edge Function** that:
   - Optionally takes parameters (e.g. date range, user id).
   - Uses the Supabase client to fetch the same data (with RLS applied if you pass a user JWT).
   - Builds PDF with a JS/TS library (e.g. **`pdf-lib`** for low-level, or **`@react-pdf/renderer`** if you want React-style components).
2. **Return** the PDF:
   - As **bytes** (e.g. `Response(body, { headers: { 'Content-Type': 'application/pdf' } })`), or
   - Upload to **Supabase Storage** and return the **public URL** for viewing/download.

Template “format” here is how you define the layout in that library (e.g. `pdf-lib` coordinates and text/table drawing, or React-PDF components).

---

## 7. Reusing Your Existing Export Pattern

Your app already:

- Fetches data from Supabase in screens.
- Uses `saveTextFile()` from `lib/utils/export_file.dart` (and platform-specific implementations) for CSV.

For PDF:

- **Same data source**: Use the same Supabase queries (e.g. staff summary, time periods, deliveries) that you’d use for a CSV or screen.
- **New helper**: Add something like `savePdfFile({ required String filename, required List<int> bytes })` next to `saveTextFile` (in `export_file_io.dart` and `export_file_web.dart`), then call it after `pdfDoc.save()`.
- **Same UX**: Trigger PDF export from a button (e.g. “Export PDF” next to “Export CSV” on the same screen); optionally show a preview with `Printing.layoutPdf` before saving.

---

## 8. Quick Checklist for Your PDF Template

- [ ] **Data**: Decide which Supabase table(s) and filters (e.g. date range) feed the report.
- [ ] **Layout**: Sketch header (title + filters), body (table or cards), footer (page number, app name).
- [ ] **Mapping**: Align Supabase columns to PDF table columns or text blocks; handle nulls and formatting (dates, numbers).
- [ ] **Styling**: Choose font sizes, table borders, and spacing so the PDF is readable and consistent.
- [ ] **View**: Use `Printing.layoutPdf` (or Storage URL) so users can preview before exporting.
- [ ] **Export**: Use your file-saving helper so the PDF is saved in the same way as your CSV exports.

---

## 9. Summary

- **“PDF template”** = layout + placeholders + styling; you implement it in code (Flutter `pdf` package or JS/TS in Edge Functions), or as **HTML + CSS** if you use the HTML-first approach.
- **HTML-first**: Display Supabase data in HTML (styled like the PDF); convert to PDF only on export. Works on all platforms; for consistent PDF output everywhere, use an Edge Function (e.g. Puppeteer) for the conversion.
- **Data** always comes from Supabase; you fetch it the same way as in your app, then pass it into the PDF builder or into the HTML template.
- **View** = preview in-app (or via Storage URL); **export** = save file using your existing export utilities and patterns.

If you add a concrete report (e.g. “Staff summary PDF” or “Time periods PDF”), you can implement it by reusing the same Supabase queries and export flow, and defining one `pdf.MultiPage` (or equivalent) per report type.
