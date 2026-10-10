import '../../data/app_database.dart';

/// Business-independent tables; old tables remain migration archives.
Future<void> createHostSchema(AppDatabase db) async {
  for (final sql in hostSchema) {
    await db.customStatement(sql);
  }
}

const hostSchema = [
  '''CREATE TABLE IF NOT EXISTS host_collections (
    module_id TEXT NOT NULL, space TEXT NOT NULL, name TEXT NOT NULL,
    definition TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(module_id, space, name))''',
  '''CREATE TABLE IF NOT EXISTS host_records (
    module_id TEXT NOT NULL, space TEXT NOT NULL, collection TEXT NOT NULL,
    id TEXT NOT NULL, value TEXT, revision INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(module_id, space, collection, id))''',
  '''CREATE TABLE IF NOT EXISTS host_indexes (
    module_id TEXT NOT NULL, space TEXT NOT NULL, collection TEXT NOT NULL,
    index_name TEXT NOT NULL, record_id TEXT NOT NULL, value TEXT NOT NULL,
    PRIMARY KEY(module_id, space, collection, index_name, record_id))''',
  '''CREATE INDEX IF NOT EXISTS host_index_values ON host_indexes
    (module_id, space, collection, index_name, value)''',
  '''CREATE TABLE IF NOT EXISTS host_packages (
    module_id TEXT NOT NULL, version TEXT NOT NULL, digest TEXT NOT NULL,
    origin TEXT NOT NULL, release TEXT NOT NULL, definition TEXT NOT NULL,
    installed_at TEXT NOT NULL, PRIMARY KEY(module_id, version))''',
  '''CREATE TABLE IF NOT EXISTS host_installations (
    module_id TEXT PRIMARY KEY, version TEXT NOT NULL, space TEXT NOT NULL,
    data_version INTEGER NOT NULL, installed INTEGER NOT NULL,
    enabled INTEGER NOT NULL, generation INTEGER NOT NULL, error TEXT)''',
  '''CREATE TABLE IF NOT EXISTS host_operations (
    id TEXT PRIMARY KEY, plan_id TEXT NOT NULL, caller TEXT NOT NULL,
    module_id TEXT NOT NULL, collection TEXT NOT NULL, entity_id TEXT NOT NULL,
    before_value TEXT, after_value TEXT, created_at TEXT NOT NULL,
    device_id TEXT NOT NULL, counter INTEGER NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS host_commits (
    plan_id TEXT PRIMARY KEY, caller TEXT NOT NULL, request_id TEXT NOT NULL,
    fingerprint TEXT NOT NULL, result TEXT NOT NULL,
    UNIQUE(caller, request_id))''',
  '''CREATE TABLE IF NOT EXISTS host_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id TEXT NOT NULL,
    module_id TEXT NOT NULL, event TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0)''',
  '''CREATE TABLE IF NOT EXISTS host_snapshots (id TEXT PRIMARY KEY,module_id TEXT NOT NULL,space TEXT NOT NULL,version TEXT NOT NULL,data_version INTEGER NOT NULL,created_at TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS host_automation (id TEXT PRIMARY KEY,module_id TEXT NOT NULL,rule_id TEXT NOT NULL,event TEXT NOT NULL,status TEXT NOT NULL,message TEXT,source_execution_id TEXT,depth INTEGER NOT NULL,created_at TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS host_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
];
