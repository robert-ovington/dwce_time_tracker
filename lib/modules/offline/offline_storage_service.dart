/// Offline Storage Service
/// 
/// Handles local storage of time entries when device is offline.
/// Uses SQLite to queue entries for sync when connection is restored.
/// Note: SQLite is not available on web, so offline storage is disabled on web platforms.

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class OfflineStorageService {
  static Database? _database;
  static const String _tableName = 'offline_time_entries';
  static const int _databaseVersion = 1;

  // Check if platform supports SQLite (not available on web)
  static bool get isSupported => !kIsWeb;

  // Initialize database
  static Future<Database?> get database async {
    if (!isSupported) return null;
    if (_database != null) return _database;
    try {
      _database = await _initDatabase();
      return _database;
    } catch (e) {
      print('❌ Error initializing offline storage: $e');
      return null;
    }
  }

  static Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web platforms');
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'offline_time_entries.db');

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_data TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        sync_attempts INTEGER DEFAULT 0
      )
    ''');
  }

  /// Add a time entry to the offline queue
  static Future<int> addToQueue(Map<String, dynamic> entryData) async {
    final db = await database;
    if (db == null) {
      print('⚠️ Offline storage not available (web platform)');
      return 0;
    }
    final entryJson = jsonEncode(entryData);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return await db.insert(
      _tableName,
      {
        'entry_data': entryJson,
        'created_at': timestamp,
        'synced': 0,
        'sync_attempts': 0,
      },
    );
  }

  /// Get all pending (unsynced) entries
  static Future<List<Map<String, dynamic>>> getPendingEntries() async {
    final db = await database;
    if (db == null) return [];
    final results = await db.query(
      _tableName,
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );

    return results.map((row) {
      final entryData = jsonDecode(row['entry_data'] as String) as Map<String, dynamic>;
      return {
        'id': row['id'] as int,
        'entry_data': entryData,
        'created_at': row['created_at'] as int,
        'sync_attempts': row['sync_attempts'] as int,
      };
    }).toList();
  }

  /// Mark an entry as synced
  static Future<void> markAsSynced(int id) async {
    final db = await database;
    if (db == null) return;
    await db.update(
      _tableName,
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Increment sync attempts for an entry
  static Future<void> incrementSyncAttempts(int id) async {
    final db = await database;
    if (db == null) return;
    final entry = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (entry.isNotEmpty) {
      final currentAttempts = entry.first['sync_attempts'] as int;
      await db.update(
        _tableName,
        {'sync_attempts': currentAttempts + 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Get count of pending entries
  static Future<int> getPendingCount() async {
    final db = await database;
    if (db == null) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete a synced entry (cleanup)
  static Future<void> deleteSyncedEntry(int id) async {
    final db = await database;
    if (db == null) return;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all synced entries (cleanup)
  static Future<void> deleteAllSyncedEntries() async {
    final db = await database;
    if (db == null) return;
    await db.delete(
      _tableName,
      where: 'synced = ?',
      whereArgs: [1],
    );
  }

  /// Clear all entries (use with caution)
  static Future<void> clearAll() async {
    final db = await database;
    if (db == null) return;
    await db.delete(_tableName);
  }
}

