import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/call_record.dart';

/// DatabaseHelper Singleton
/// Manages SQLite database lifecycle for Call Log Keeper (call_log_keeper.db).
class DatabaseHelper {
  static const String _databaseName = 'call_log_keeper.db';
  static const int _databaseVersion = 1;

  static const String tableCallRecords = 'call_records';
  static const String colId = 'id';
  static const String colNumber = 'number';
  static const String colName = 'name';
  static const String colType = 'type';
  static const String colDate = 'date';
  static const String colDuration = 'duration';
  static const String colAudioPath = 'audio_path';

  // Singleton instance
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onOpen: (db) async {
        try {
          await db.execute('ALTER TABLE $tableCallRecords ADD COLUMN $colAudioPath TEXT');
        } catch (_) {}
      },
    );
  }

  /// Create table matching Native Kotlin SQLite schema with unique constraint
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCallRecords (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colNumber TEXT NOT NULL,
        $colName TEXT,
        $colType INTEGER NOT NULL,
        $colDate INTEGER NOT NULL,
        $colDuration INTEGER NOT NULL,
        $colAudioPath TEXT,
        UNIQUE($colNumber, $colDate) ON CONFLICT REPLACE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_call_records_date ON $tableCallRecords ($colDate DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_call_records_number ON $tableCallRecords ($colNumber)',
    );
  }

  /// Inserts a single call record. Returns ID or -1 if ignored.
  Future<int> insert(CallRecord record) async {
    final db = await database;
    return await db.insert(
      tableCallRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Batch inserts call records in a single database transaction.
  Future<int> insertBatch(List<CallRecord> records) async {
    if (records.isEmpty) return 0;
    final db = await database;
    final batch = db.batch();

    for (final record in records) {
      batch.insert(
        tableCallRecords,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final results = await batch.commit(noResult: false);
    return results.where((res) => res is int && res > 0).length;
  }

  /// Retrieves records matching search, call type, and date range filters.
  Future<List<CallRecord>> getAll({
    String? searchQuery,
    String? callTypeFilter, // 'all', 'incoming', 'outgoing', 'missed', 'rejected'
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    // Search query filter (matches contact name or number)
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('($colNumber LIKE ? OR $colName LIKE ?)');
      whereArgs.add(query);
      whereArgs.add(query);
    }

    // Call type filter
    if (callTypeFilter != null && callTypeFilter != 'all') {
      switch (callTypeFilter.toLowerCase()) {
        case 'incoming':
          whereClauses.add('$colType = ?');
          whereArgs.add(1);
          break;
        case 'outgoing':
          whereClauses.add('$colType = ?');
          whereArgs.add(2);
          break;
        case 'missed':
          whereClauses.add('$colType = ?');
          whereArgs.add(3);
          break;
        case 'rejected':
          whereClauses.add('($colType = 5 OR $colType = 6)');
          break;
      }
    }

    // Date range filter
    if (startDate != null) {
      whereClauses.add('$colDate >= ?');
      whereArgs.add(startDate.millisecondsSinceEpoch);
    }
    if (endDate != null) {
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
      whereClauses.add('$colDate <= ?');
      whereArgs.add(endOfDay.millisecondsSinceEpoch);
    }

    final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final List<Map<String, dynamic>> maps = await db.query(
      tableCallRecords,
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: '$colDate DESC',
    );

    return maps.map((map) => CallRecord.fromMap(map)).toList();
  }

  /// Returns total count of backed up calls
  Future<int> getRecordCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) FROM $tableCallRecords');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  /// Deletes a specific call record by ID
  Future<int> delete(int id) async {
    final db = await database;
    return await db.delete(
      tableCallRecords,
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  /// Clears all call records from database
  Future<int> clearAll() async {
    final db = await database;
    return await db.delete(tableCallRecords);
  }

  /// Updates the audio recording file path for a specific call record ID
  Future<int> updateAudioPath(int id, String path) async {
    final db = await database;
    return await db.update(
      tableCallRecords,
      {colAudioPath: path},
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  // Compatibility helper
  Future<int> purgeUnknownPlaceholders() async {
    return 0; // Not needed in Call Log Keeper
  }
}
