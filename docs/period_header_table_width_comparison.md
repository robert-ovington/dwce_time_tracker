# Period Section: Header vs Table Column Width Comparison

All widths in pixels. Header has 10 columns; Table has 17 columns. Header columns 6 and 7 are merged (Plant 1–6, Mob 1–4).

## Source of widths

- **Table:** `_tableColWidths()` — 17 columns, total 850 px.
- **Header:** Same values: column 0 = "Day" = `_periodDayColumnWidth` (30); columns 1–5 and 8–9 = table cols 0–4 and 15–16; column 6 = sum of table cols 5–10; column 7 = sum of table cols 11–14.
- **Layout:** Period section width = `_periodWidth` = **880 px**. So `tableWidth` = 880 − 30 = 850 px. Header section width = 850 + 30 = **880 px** (must equal sum of header column widths so there is no slack). Body = Day column 30 px + data table 850 px = **880 px**.
- **Cause of large misalignment (fixed):** If `_periodWidth` was 900, then header width was 900 px but header columns summed to 880 px (20 px slack), and body table section was 870 px but table columns summed to 850 px (20 px slack). With slack, the tables can be centered in their containers, giving a ~10 px (or more) shift. **Fix:** `_periodWidth` is set to 880 so header and body widths match their content exactly (no slack).
- **Remaining 2 px:** Header table has a **2 px left border** (`_periodLeftBorderW`), so the "Day" header cell starts at 2 px; the body Day column starts at 0. So the Day column can still look 2 px out of step.

---

## Column-by-column comparison

| Header col | Header label              | Header width (px) | Table col(s) | Table width (px) | Match? |
|------------|---------------------------|-------------------|--------------|------------------|--------|
| 0          | Day                       | 30                | — (Day col is separate 30 px) | 30 (body Day column) | ✓ same width; ✗ offset by 2 px (header has left border) |
| 1          | Project                   | 190               | 0            | 190              | ✓ |
| 2          | Job No.                   | 60                | 1            | 60               | ✓ |
| 3          | Start                     | 40                | 2            | 40               | ✓ |
| 4          | Break                     | 40                | 3            | 40               | ✓ |
| 5          | Finish                    | 40                | 4            | 40               | ✓ |
| 6          | Plant Number / Hired Plant | 240               | 5+6+7+8+9+10 | 40×6 = 240       | ✓ |
| 7          | Mobilised Plant           | 160               | 11+12+13+14  | 40×4 = 160       | ✓ |
| 8          | Travel                    | 40                | 15           | 40               | ✓ |
| 9          | Check                     | 40                | 16           | 40               | ✓ |

**Header total (column widths only):** 30 + 190 + 60 + 40×3 + 240 + 160 + 40 + 40 = **880 px**  
**Table total:** 190 + 60 + 40×15 = **850 px**  
**Body layout:** Day column 30 px + Table 850 px = **880 px**

---

## Width lists (for copy/reference)

### Header (10 columns)

| Index | Label                        | Width |
|-------|------------------------------|-------|
| 0     | Day                          | 30    |
| 1     | Project                      | 190   |
| 2     | Job No.                      | 60    |
| 3     | Start                        | 40    |
| 4     | Break                        | 40    |
| 5     | Finish                       | 40    |
| 6     | Plant Number / Hired Plant   | 240   |
| 7     | Mobilised Plant              | 160   |
| 8     | Travel                       | 40    |
| 9     | Check                        | 40    |

**Total: 880 px** (plus 2 px left border drawn on the table edge, so "Day" cell starts at 2 px)

### Table (17 columns)

| Index | Content  | Width |
|-------|----------|-------|
| 0     | Project  | 190   |
| 1     | Job No.  | 60    |
| 2     | Start    | 40    |
| 3     | Break    | 40    |
| 4     | Finish   | 40    |
| 5     | Plant 1  | 40    |
| 6     | Plant 2  | 40    |
| 7     | Plant 3  | 40    |
| 8     | Plant 4  | 40    |
| 9     | Plant 5  | 40    |
| 10    | Plant 6  | 40    |
| 11    | Mob 1    | 40    |
| 12    | Mob 2    | 40    |
| 13    | Mob 3    | 40    |
| 14    | Mob 4    | 40    |
| 15    | Travel   | 40    |
| 16    | Check    | 40    |

**Total: 850 px**

---

## Summary

- **Cell widths:** Header cells 1–9 match the corresponding table column(s); header cell 0 (Day) is 30 px, same as the body Day column.
- **Period width:** `_periodWidth` = 880 so that header (880 px) and body (30 + 850 = 880 px) have no extra space; header and table columns align.
- **Optional 2 px Day alignment:** The header has a 2 px left border, so "Day" starts at 2 px and the body Day column at 0. To align exactly: remove the header left border, or make the header’s first column 28 px (2 + 28 = 30), or add 2 px leading space before the body Day column and reduce table width by 2 px.
