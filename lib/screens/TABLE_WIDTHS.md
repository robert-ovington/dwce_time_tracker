# Table column widths and total widths

## Load quantities table

Uses Flutter `Table` with `columnWidths` and `TableBorder.all(color: Colors.grey)`.

| Column index | Header      | Width (px) |
|-------------|-------------|------------|
| 0           | Trip        | 108        |
| 1           | Quantity    | 108        |
| 2           | Travel Time | 108        |
| 3           | Distance    | 108        |
| 4           | Map         | 108        |

- **Sum of column widths:** 5 × 108 = **540**
- **Spacing:** `Table` has no `columnSpacing` / `horizontalMargin` in this code — total content width is the sum of column widths.
- **Total width (content):** **540 px**  
- **Total width (with border):** 540 + border (e.g. 1 px each side) ≈ **542 px** depending on theme.

---

## Bookings table

Uses Flutter `DataTable` with `columnSpacing: 4`, `horizontalMargin: 4`, and `FixedColumnWidth` per column.

| Column index | Header     | Width (px) |
|-------------|------------|------------|
| 0           | Seq        | 35         |
| 1           | Time       | 36         |
| 2           | Scheduled  | 36         |
| 3           | Job No.    | 36         |
| 4           | County     | 36         |
| 5           | Qty        | 34         |
| 6           | Type       | 38         |
| 7           | Ordered by | 36         |
| 8           | Comment    | 171        |
| 9           | (actions)  | 38         |

- **Sum of column widths:** 35 + 36 + 36 + 36 + 36 + 34 + 38 + 36 + 171 + 38 = **496**
- **Column spacing:** 4 px × (10 − 1) = **36 px**
- **Horizontal margin:** 4 px × 2 = **8 px**
- **Total width (content):** 496 + 36 + 8 = **540 px**

---

## Summary

| Table              | Sum of columns | Spacing / margin | Total width |
|--------------------|----------------|------------------|-------------|
| Load quantities    | 540            | 0                | **540 px**  |
| Bookings           | 496            | 44               | **540 px**  |

Both tables are intended to have the same total content width (**540 px**).  
If the Bookings table is still compressed or overflowing, the cause is likely the **parent layout** (e.g. the horizontal `SingleChildScrollView` or the left panel width) rather than these column widths.
