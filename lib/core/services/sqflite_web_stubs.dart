/// Stub for Database on web
class Database {
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm,}) async {
    return 0;
  }

  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset,}) async {
    return [];
  }

  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments,]) async {
    return [];
  }

  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs,}) async {
    return 0;
  }

  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    return 0;
  }

  Future<void> close() async {}
}

enum ConflictAlgorithm {
  rollback,
  abort,
  fail,
  ignore,
  replace,
}

Future<String> getDatabasesPath() async {
  return '';
}

Future<Database> openDatabase(
  String path, {
  int? version,
  dynamic onConfigure,
  dynamic onCreate,
  dynamic onUpgrade,
  dynamic onDowngrade,
  dynamic onOpen,
  bool readOnly = false,
  bool singleInstance = true,
}) async {
  return Database();
}

class Sqflite {
  static int? firstIntValue(List<Map<String, Object?>> list) {
    if (list.isEmpty) return null;
    return 0; // dummy
  }
}
