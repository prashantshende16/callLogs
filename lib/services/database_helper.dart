import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/call_record.dart';

/// DatabaseHelper Singleton
/// Manages SQLite database lifecycle, schema migrations, and CRUD operations.
class DatabaseHelper {
  static const String _databaseName = 'call_logger.db';
  static const int _databaseVersion = 2;

  static const String tableCallRecords = 'call_records';
  static const String colId = 'id';
  static const String colCallerNumber = 'caller_number';
  static const String colReceiverNumber = 'receiver_number';
  static const String colCallType = 'call_type';
  static const String colCallStatus = 'call_status';
  static const String colStartTime = 'start_time';
  static const String colEndTime = 'end_time';
  static const String colDurationSeconds = 'duration_seconds';
  static const String colSimSlot = 'sim_slot';
  static const String colAudioPath = 'audio_path';
  static const String colCreatedAt = 'created_at';

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
      onUpgrade: _onUpgrade,
    );
  }

  /// Create table with unique constraint on (caller_number, start_time)
  /// to prevent duplicate entries from multiple broadcast receivers or sync runs.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableCallRecords (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colCallerNumber TEXT NOT NULL,
        $colReceiverNumber TEXT NOT NULL,
        $colCallType TEXT NOT NULL,
        $colCallStatus TEXT NOT NULL,
        $colStartTime INTEGER NOT NULL,
        $colEndTime INTEGER NOT NULL,
        $colDurationSeconds INTEGER NOT NULL,
        $colSimSlot TEXT,
        $colAudioPath TEXT,
        $colCreatedAt INTEGER NOT NULL,
        UNIQUE($colCallerNumber, $colStartTime) ON CONFLICT IGNORE
      )
    ''');

    // Indexes for fast search and query filtering
    await db.execute(
      'CREATE INDEX idx_call_records_start_time ON $tableCallRecords ($colStartTime DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_call_records_caller ON $tableCallRecords ($colCallerNumber)',
    );
    await db.execute(
      'CREATE INDEX idx_call_records_type ON $tableCallRecords ($colCallType)',
    );
  }

  /// Versioned schema upgrade handler for future schema expansions
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableCallRecords ADD COLUMN $colAudioPath TEXT;');
    }
  }

  /// Inserts a single call record. Returns the generated ID or -1 if ignored (duplicate).
  Future<int> insert(CallRecord record) async {
    final db = await database;
    return await db.insert(
      tableCallRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Batch inserts a list of records efficiently in a single database transaction.
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

  /// Retrieves all records with optional search, type filtering, and date range.
  /// Always sorted newest first.
  Future<List<CallRecord>> getAll({
    String? searchQuery,
    String? callTypeFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;

    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    // Filter by search query (caller number or receiver number)
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('($colCallerNumber LIKE ? OR $colReceiverNumber LIKE ?)');
      whereArgs.add(query);
      whereArgs.add(query);
    }

    // Filter by call type (incoming, outgoing, missed, rejected)
    if (callTypeFilter != null &&
        callTypeFilter.isNotEmpty &&
        callTypeFilter.toLowerCase() != 'all') {
      whereClauses.add('$colCallType = ?');
      whereArgs.add(callTypeFilter.toLowerCase());
    }

    // Filter by date range (start of startDate to end of endDate)
    if (startDate != null) {
      final startMillis = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        0,
        0,
        0,
      ).millisecondsSinceEpoch;
      whereClauses.add('$colStartTime >= ?');
      whereArgs.add(startMillis);
    }

    if (endDate != null) {
      final endMillis = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;
      whereClauses.add('$colStartTime <= ?');
      whereArgs.add(endMillis);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final maps = await db.query(
      tableCallRecords,
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: '$colStartTime DESC',
    );

    return maps.map((map) => CallRecord.fromMap(map)).toList();
  }

  /// Get call records filtered by a specific phone number
  Future<List<CallRecord>> getByNumber(String number) async {
    final db = await database;
    final maps = await db.query(
      tableCallRecords,
      where: '$colCallerNumber LIKE ? OR $colReceiverNumber LIKE ?',
      whereArgs: ['%$number%', '%$number%'],
      orderBy: '$colStartTime DESC',
    );
    return maps.map((map) => CallRecord.fromMap(map)).toList();
  }

  /// Get call records within a specific date range
  Future<List<CallRecord>> getByDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final startMillis = start.millisecondsSinceEpoch;
    final endMillis = end.millisecondsSinceEpoch;

    final maps = await db.query(
      tableCallRecords,
      where: '$colStartTime >= ? AND $colStartTime <= ?',
      whereArgs: [startMillis, endMillis],
      orderBy: '$colStartTime DESC',
    );
    return maps.map((map) => CallRecord.fromMap(map)).toList();
  }

  /// Delete a single record by primary key ID
  Future<int> delete(int id) async {
    final db = await database;
    return await db.delete(
      tableCallRecords,
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  /// Clears all call records from the database
  Future<int> clearAll() async {
    final db = await database;
    return await db.delete(tableCallRecords);
  }

  /// Check if a record already exists with the given caller number and start time
  Future<bool> exists(String callerNumber, int startTime) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM $tableCallRecords WHERE $colCallerNumber = ? AND $colStartTime = ?',
      [callerNumber, startTime],
    ));
    return (count ?? 0) > 0;
  }
}

