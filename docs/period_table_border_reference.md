# Period Table – border reference (for alignment review)

Use this table to see which rows have a 1 px or 2 px border, whether it is **top** or **bottom**, and whether the row is **visible** or hidden. No code changes – for review only.

**Logic (from paper_timesheet_screen.dart):**
- **Top border:** First row (display 1) = 0 px. 2 px above start of each new day: rows that display as **16, 31, 46, 61, 76, 91** (spec key 15, 30, 45, 60, 75, 90). All other rows = 1 px.
- **Bottom border:** No bottom between row 1 and row 104. Only the last row (e.g. 105) = 1 px; all other rows = 0 px.
- **Visible:** From `paper_timesheet_rows.visible` at runtime. Below uses the app **fallback** (Mon–Fri: first 7 of 15 visible; Sat: first 3; Sun: first 1). If you use the DB, your visibility may differ.

| Row | Top (px) | Bottom (px) | Visible |
|-----|----------|-------------|---------|
| 1   | 0        | 0           | Y       |
| 2   | 1        | 0           | Y       |
| 3   | 1        | 0           | Y       |
| 4   | 1        | 0           | Y       |
| 5   | 1        | 0           | Y       |
| 6   | 1        | 0           | Y       |
| 7   | 1        | 0           | Y       |
| 8   | 1        | 0           | N       |
| 9   | 1        | 0           | N       |
| 10  | 1        | 0           | N       |
| 11  | 1        | 0           | N       |
| 12  | 1        | 0           | N       |
| 13  | 1        | 0           | N       |
| 14  | 1        | 0           | N       |
| 15  | 1        | 0           | N       |
| 16  | 2        | 0           | Y       |
| 17  | 1        | 0           | Y       |
| 18  | 1        | 0           | Y       |
| 19  | 1        | 0           | Y       |
| 20  | 1        | 0           | Y       |
| 21  | 1        | 0           | Y       |
| 22  | 1        | 0           | Y       |
| 23  | 1        | 0           | N       |
| 24  | 1        | 0           | N       |
| 25  | 1        | 0           | N       |
| 26  | 1        | 0           | N       |
| 27  | 1        | 0           | N       |
| 28  | 1        | 0           | N       |
| 29  | 1        | 0           | N       |
| 30  | 1        | 0           | N       |
| 31  | 2        | 0           | Y       |
| 32  | 1        | 0           | Y       |
| 33  | 1        | 0           | Y       |
| 34  | 1        | 0           | Y       |
| 35  | 1        | 0           | Y       |
| 36  | 1        | 0           | Y       |
| 37  | 1        | 0           | Y       |
| 38  | 1        | 0           | N       |
| 39  | 1        | 0           | N       |
| 40  | 1        | 0           | N       |
| 41  | 1        | 0           | N       |
| 42  | 1        | 0           | N       |
| 43  | 1        | 0           | N       |
| 44  | 1        | 0           | N       |
| 45  | 1        | 0           | N       |
| 46  | 2        | 0           | Y       |
| 47  | 1        | 0           | Y       |
| 48  | 1        | 0           | Y       |
| 49  | 1        | 0           | Y       |
| 50  | 1        | 0           | Y       |
| 51  | 1        | 0           | Y       |
| 52  | 1        | 0           | Y       |
| 53  | 1        | 0           | N       |
| 54  | 1        | 0           | N       |
| 55  | 1        | 0           | N       |
| 56  | 1        | 0           | N       |
| 57  | 1        | 0           | N       |
| 58  | 1        | 0           | N       |
| 59  | 1        | 0           | N       |
| 60  | 1        | 0           | N       |
| 61  | 2        | 0           | Y       |
| 62  | 1        | 0           | Y       |
| 63  | 1        | 0           | Y       |
| 64  | 1        | 0           | Y       |
| 65  | 1        | 0           | Y       |
| 66  | 1        | 0           | Y       |
| 67  | 1        | 0           | Y       |
| 68  | 1        | 0           | N       |
| 69  | 1        | 0           | N       |
| 70  | 1        | 0           | N       |
| 71  | 1        | 0           | N       |
| 72  | 1        | 0           | N       |
| 73  | 1        | 0           | N       |
| 74  | 1        | 0           | N       |
| 75  | 1        | 0           | N       |
| 76  | 2        | 0           | Y       |
| 77  | 1        | 0           | Y       |
| 78  | 1        | 0           | Y       |
| 79  | 1        | 0           | N       |
| 80  | 1        | 0           | N       |
| 81  | 1        | 0           | N       |
| 82  | 1        | 0           | N       |
| 83  | 1        | 0           | N       |
| 84  | 1        | 0           | N       |
| 85  | 1        | 0           | N       |
| 86  | 1        | 0           | N       |
| 87  | 1        | 0           | N       |
| 88  | 1        | 0           | N       |
| 89  | 1        | 0           | N       |
| 90  | 1        | 0           | N       |
| 91  | 2        | 0           | Y       |
| 92  | 1        | 0           | N       |
| 93  | 1        | 0           | N       |
| 94  | 1        | 0           | N       |
| 95  | 1        | 0           | N       |
| 96  | 1        | 0           | N       |
| 97  | 1        | 0           | N       |
| 98  | 1        | 0           | N       |
| 99  | 1        | 0           | N       |
| 100 | 1        | 0           | N       |
| 101 | 1        | 0           | N       |
| 102 | 1        | 0           | N       |
| 103 | 1        | 0           | N       |
| 104 | 1        | 0           | N       |
| 105 | 1        | 1           | N       |

**Pattern:** No bottom borders between row 1 and row 104. Only the **last row** (105) has bottom 1 px. **2 px top** on rows that display as **16, 31, 46, 61, 76, 91** (start of Tue, Wed, Thu, Fri, Sat, Sun). Row 1 has top 0 px. **Visible (fallback):** Within each block of 15: Mon–Fri rows 1–7 Y, 8–15 N; Sat 1–3 Y, 4–15 N; Sun 1 Y, 2–15 N.
