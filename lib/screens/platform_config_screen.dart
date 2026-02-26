/// Platform Config Screen
///
/// Displays data from Supabase public.screen_platforms (same table as DB).
/// Refreshes on load and via refresh button or pull-to-refresh.
/// If fetch fails, falls back to local lib/config/platform_screens.dart. See PLATFORM_CONFIG.md.

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:flutter/services.dart';
import '../config/supabase_config.dart';
import '../config/platform_screens.dart';

class PlatformConfigScreen extends StatefulWidget {
  const PlatformConfigScreen({super.key});

  @override
  State<PlatformConfigScreen> createState() => _PlatformConfigScreenState();
}

class _PlatformConfigScreenState extends State<PlatformConfigScreen> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;
  String? _error;
  bool _fromSupabase = false;

  @override
  void initState() {
    super.initState();
    _loadFromSupabase();
  }

  Future<void> _loadFromSupabase() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await SupabaseService.client
          .from('screen_platforms')
          .select('screen_id, display_name, android, ios, web, windows, lite')
          .order('screen_id');
      final list = (response as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _rows = list;
          _loading = false;
          _fromSupabase = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fromSupabase = false;
          _error = e.toString();
          _rows = _localRows();
        });
      }
    }
  }

  List<Map<String, dynamic>> _localRows() {
    return kScreenPlatforms.map((s) => {
      'screen_id': s.screenId,
      'display_name': s.displayName,
      'android': s.android,
      'ios': s.ios,
      'web': s.web,
      'windows': s.windows,
      'lite': s.lite,
    }).toList();
  }

  static bool _bool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  Future<void> _onRefresh() async {
    await _loadFromSupabase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_fromSupabase ? 'Refreshed from Supabase' : 'Using local config (Supabase failed)'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Config', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'platform_config_screen.dart'),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh from Supabase',
            onPressed: _loading ? null : () => _onRefresh(),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy config path',
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: 'lib/config/platform_screens.dart'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied: lib/config/platform_screens.dart')),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fromSupabase
                          ? 'Data from Supabase: public.screen_platforms'
                          : 'Local fallback: lib/config/platform_screens.dart',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text('Supabase error: $_error', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Table columns: screen_id, display_name, android, ios, web, windows, lite. '
                      'Keep lib/config/platform_screens.dart in sync. See PLATFORM_CONFIG.md.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: 200,
                            child: Center(
                              child: Text(
                                'No rows in screen_platforms',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            scrollDirection: Axis.vertical,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade300),
                              columns: const [
                                DataColumn(label: Text('Screen ID', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Display Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Android', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('iOS', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Web', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Windows', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Lite', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: rows.map((r) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(r['screen_id']?.toString() ?? '—', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(r['display_name']?.toString() ?? '—', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(_bool(r['android']) ? '✓' : '—', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(_bool(r['ios']) ? '✓' : '—', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(_bool(r['web']) ? '✓' : '—', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(_bool(r['windows']) ? '✓' : '—', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(_bool(r['lite']) ? '✓' : '—', style: const TextStyle(fontSize: 12))),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
