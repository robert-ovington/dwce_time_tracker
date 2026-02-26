/// Helpers for PPE size display order (uses sort_order from DB when present).

/// Build sorted list of size_code from rows that have size_code and optional sort_order.
/// Orders by sort_order first, then by size_code for tie-break.
List<String> sortedSizesFromRows(List<dynamic> rows) {
  final withOrder = rows.map((e) {
    final m = e as Map;
    final code = m['size_code']?.toString() ?? '';
    final order = m['sort_order'] is int
        ? m['sort_order'] as int
        : (int.tryParse(m['sort_order']?.toString() ?? '') ?? 0);
    return MapEntry(order, code);
  }).where((e) => e.value.isNotEmpty).toList();
  withOrder.sort((a, b) => a.key.compareTo(b.key));
  return withOrder.map((e) => e.value).toList();
}
