/// CSV Parser for Bulk Employer Import
/// 
/// Parses CSV files containing employer data for bulk import.
/// 
/// Expected CSV format:
/// employer_name,employer_type,is_active
/// 
/// is_active is optional - defaults to true if empty

class EmployerCsvParser {
  // Parse CSV string into list of employer maps
  static List<Map<String, dynamic>> parseEmployersCsv(String csvContent) {
    print('🔍 Parsing employer CSV content, length: ${csvContent.length}');
    final lines = csvContent.split('\n');
    print('🔍 CSV lines count: ${lines.length}');
    
    if (lines.isEmpty) {
      print('⚠️ CSV is empty');
      return [];
    }

    // Check header row
    if (lines.isNotEmpty) {
      final header = lines[0].trim().toLowerCase();
      print('🔍 CSV header: $header');
      if (!header.contains('employer_name') || !header.contains('employer_type')) {
        print('⚠️ CSV header might be incorrect. Expected: employer_name,employer_type,is_active');
      }
    }

    // Skip header row
    final dataLines = lines.skip(1).where((line) => line.trim().isNotEmpty).toList();
    print('🔍 Data lines (excluding header): ${dataLines.length}');

    final employers = <Map<String, dynamic>>[];

    for (var i = 0; i < dataLines.length; i++) {
      final line = dataLines[i];
      print('🔍 Processing line ${i + 1}: $line');
      
      final values = _parseCsvLine(line);
      print('🔍 Parsed values count: ${values.length}, values: $values');
      
      if (values.length < 2) {
        print('⚠️ Skipping line ${i + 1}: Not enough columns (expected 2+, got ${values.length})');
        continue;
      }

      try {
        // Parse is_active (optional, defaults to true)
        bool isActive = true;
        if (values.length > 2 && values[2].trim().isNotEmpty) {
          final isActiveStr = values[2].trim().toLowerCase();
          isActive = isActiveStr == 'true' || isActiveStr == '1' || isActiveStr == 'yes';
        }

        final employer = {
          'employer_name': values[0].trim(),
          'employer_type': values[1].trim(),
          'is_active': isActive,
        };

        print('🔍 Parsed employer: name=${employer['employer_name']}, type=${employer['employer_type']}, active=${employer['is_active']}');

        // Validate required fields
        if (employer['employer_name'] == null || 
            employer['employer_name'].toString().isEmpty ||
            employer['employer_type'] == null ||
            employer['employer_type'].toString().isEmpty) {
          print('⚠️ Skipping line ${i + 1}: Missing required fields');
          continue; // Skip invalid rows
        }

        employers.add(employer);
        print('✅ Added employer ${employers.length}: ${employer['employer_name']}');
      } catch (e) {
        // Skip rows with invalid data
        print('⚠️ Skipping invalid CSV row ${i + 1}: $line - Error: $e');
        continue;
      }
    }

    print('✅ Total employers parsed: ${employers.length}');
    return employers;
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

    // Add last value
    values.add(current.toString());

    return values;
  }

  // Generate CSV template
  static String generateCsvTemplate() {
    return '''employer_name,employer_type,is_active
Acme Corporation,Contractor,true
XYZ Industries,Subcontractor,true
ABC Services,Supplier,false''';
  }
}

