import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/local_database_service.dart';
import 'package:vocabmaster/services/offline_sync_service.dart';

void setupTestEnv() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Initialize FFI for SQLite
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Mock SharedPreferences
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  // Force test DB mode to avoid cross-test locks
  LocalDatabaseService.enableTestMode();
  OfflineSyncService.enableTestMode();
}

Future<void> clearDatabase() async {
  final dbService = LocalDatabaseService();
  await dbService.close();
  // Ensure the DB is initialized
  await dbService.database;
  // Clear all tables
  await dbService.clearAll();
}
