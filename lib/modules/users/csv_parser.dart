/// CSV Parser for Bulk User Import
///
/// Parses CSV files containing user data for bulk import.
/// Supports all fields available on the Create User form (including menu permissions and security_limit).
/// Column order does not matter; headers are matched by name (case-insensitive).
///
/// Required columns: email, forename, surname, initials, role, security
/// Optional: phone, password, employer_name, eircode, security_limit, User Flags (show_project, etc.), and all menu_* (use 1/0, true/false, or yes/no)

class CsvParser {
  /// All supported CSV column headers (required first, then optional).
  /// Use this exact header row when creating your CSV file.
  static const List<String> csvHeaders = [
    'email',
    'phone',
    'forename',
    'surname',
    'initials',
    'role',
    'security',
    'password',
    'employer_name',
    'eircode',
    'security_limit',
    'show_project',
    'show_fleet',
    'show_allowances',
    'show_comments',
    'concrete_mix_lorry',
    'reinstatement_crew',
    'cable_pulling',
    'is_mechanic',
    'is_public',
    'is_active',
    'menu_clock_in',
    'menu_time_periods',
    'menu_plant_checks',
    'menu_deliveries',
    'menu_paperwork',
    'menu_time_off',
    'menu_sites',
    'menu_reports',
    'menu_managers',
    'ppe_manager',
    'menu_exports',
    'menu_administration',
    'menu_messages',
    'menu_messenger',
    'menu_training',
    'menu_cube_test',
    'menu_office',
    'menu_office_admin',
    'menu_office_project',
    'menu_concrete_mix',
    'menu_workshop',
  ];

  static const List<String> _requiredHeaders = [
    'email',
    'forename',
    'surname',
    'initials',
    'role',
    'security',
  ];

  /// User Flags (users_data booleans) - same as User Edit screen "User Flags" section
  static const List<String> _dataBooleanKeys = [
    'show_project',
    'show_fleet',
    'show_allowances',
    'show_comments',
    'concrete_mix_lorry',
    'reinstatement_crew',
    'cable_pulling',
    'is_mechanic',
    'is_public',
    'is_active',
  ];

  static const List<String> _setupBooleanKeys = [
    'menu_clock_in',
    'menu_time_periods',
    'menu_plant_checks',
    'menu_deliveries',
    'menu_paperwork',
    'menu_time_off',
    'menu_sites',
    'menu_reports',
    'menu_managers',
    'ppe_manager',
    'menu_exports',
    'menu_administration',
    'menu_messages',
    'menu_messenger',
    'menu_training',
    'menu_cube_test',
    'menu_office',
    'menu_office_admin',
    'menu_office_project',
    'menu_concrete_mix',
    'menu_workshop',
  ];

  // Parse CSV string into list of user maps (header-based; column order ignored)
  static List<Map<String, dynamic>> parseUsersCsv(String csvContent) {
    print('🔍 Parsing CSV content, length: ${csvContent.length}');
    final lines = csvContent.split('\n');
    print('🔍 CSV lines count: ${lines.length}');

    if (lines.isEmpty) {
      print('⚠️ CSV is empty');
      return [];
    }

    final headerLine = lines[0];
    final headerCells = _parseCsvLine(headerLine);
    final headers = headerCells.map((s) => s.trim().toLowerCase()).toList();
    print('🔍 CSV headers: $headers');

    if (!headers.contains('email') || !headers.contains('forename')) {
      print('⚠️ CSV header must include at least: email, forename, surname, initials, role, security');
    }

    final dataLines = lines.skip(1).where((line) => line.trim().isNotEmpty).toList();
    print('🔍 Data lines (excluding header): ${dataLines.length}');

    final users = <Map<String, dynamic>>[];

    for (var i = 0; i < dataLines.length; i++) {
      final line = dataLines[i];
      print('🔍 Processing line ${i + 1}: $line');

      final values = _parseCsvLine(line);
      if (values.length < 6) {
        print('⚠️ Skipping line ${i + 1}: Not enough columns');
        continue;
      }

      final row = <String, String>{};
      for (var j = 0; j < headers.length && j < values.length; j++) {
        final key = headers[j];
        if (key.isEmpty) continue;
        row[key] = values[j].trim();
      }

      try {
        final user = _rowToUser(row);
        if (user == null) {
          print('⚠️ Skipping line ${i + 1}: Missing required fields');
          continue;
        }
        users.add(user);
        print('✅ Added user ${users.length}: ${user['email']}');
      } catch (e) {
        print('⚠️ Skipping invalid CSV row ${i + 1}: $line - Error: $e');
        continue;
      }
    }

    print('✅ Total users parsed: ${users.length}');
    return users;
  }

  static Map<String, dynamic>? _rowToUser(Map<String, String> row) {
    String? get(String key) {
      final v = row[key.toLowerCase()];
      return (v != null && v.isNotEmpty) ? v : null;
    }

    final email = get('email');
    final forename = get('forename');
    final surname = get('surname');
    final initials = get('initials');
    final role = get('role');
    final securityStr = get('security');

    if (email == null ||
        email.isEmpty ||
        forename == null ||
        forename.isEmpty ||
        surname == null ||
        surname.isEmpty ||
        initials == null ||
        initials.isEmpty ||
        role == null ||
        role.isEmpty ||
        securityStr == null ||
        securityStr.isEmpty) {
      return null;
    }

    final security = int.tryParse(securityStr);
    if (security == null || security < 1 || security > 9) {
      throw FormatException('security must be 1-9, got: $securityStr');
    }

    final user = <String, dynamic>{
      'email': email,
      'phone': get('phone'),
      'forename': forename,
      'surname': surname,
      'initials': initials,
      'role': role,
      'security': security,
      'password': get('password'),
      'employer_name': get('employer_name'),
      'eircode': get('eircode'),
    };

    final securityLimitStr = get('security_limit');
    if (securityLimitStr != null) {
      final sl = int.tryParse(securityLimitStr);
      if (sl != null && sl >= 1 && sl <= 9) {
        user['security_limit'] = sl;
      }
    }

    for (final key in _dataBooleanKeys) {
      final v = get(key);
      if (v != null) {
        final b = _parseBool(v);
        if (b != null) user[key] = b;
      }
    }

    for (final key in _setupBooleanKeys) {
      final v = get(key);
      if (v != null) {
        final b = _parseBool(v);
        if (b != null) user[key] = b;
      }
    }

    return user;
  }

  static bool? _parseBool(String v) {
    final lower = v.toLowerCase();
    if (lower == '1' || lower == 'true' || lower == 'yes') return true;
    if (lower == '0' || lower == 'false' || lower == 'no') return false;
    return null;
  }

  // Parse a single CSV line, handling quoted values
  static List<String> _parseCsvLine(String line) {
    final values = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        values.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }

    values.add(current.toString());
    return values;
  }

  // Generate CSV template with all supported headers
  static String generateCsvTemplate() {
    final header = csvHeaders.join(',');
    // security_limit + 10 User Flags + 19 menu_* (1=true, 0=false). Flags default: is_active=1, others=0
    const opt = '1,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0';
    return '''$header
user1@example.com,1234567890,John,Doe,JD,Skilled Operative,5,,Employer1,D02AF30,$opt
user2@example.com,0987654321,Jane,Smith,JS,Manager,2,initialpassword123,Employer2,D01AB12,$opt''';
  }
}
