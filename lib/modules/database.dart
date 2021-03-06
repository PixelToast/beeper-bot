import 'dart:async';
import 'dart:convert';

import 'package:beeper/modules/status.dart';
import 'package:beeper/secrets.dart';
import 'package:postgres/postgres.dart';
import 'package:meta/meta.dart';

import 'package:beeper/modules.dart';

@Metadata(name: 'database', loadable: true)
class DatabaseModule extends Module with StatusLoader {
  PostgreSQLConnection con;

  final String host;
  final int port;
  final String user;
  final String password;
  final String database;

  DatabaseModule({
    @required this.host,
    @required this.port,
    @required this.user,
    @required this.password,
    @required this.database,
  });

  Future<T> getConf<T>(String key) async {
    final result = await con.query(
      '''select (Value) from Config where Key = @Key''',
      substitutionValues: <String, dynamic>{
        'Key': key,
      },
    );

    if (result.isEmpty) {
      return null;
    } else {
      return jsonDecode(result.single.single as String) as T;
    }
  }

  Future<void> setConf(String key, dynamic value) {
    return con.execute(
      '''insert into Config (Key, Value) values (@Key, @Value) on conflict (Key) do update set Value = @Value''',
      substitutionValues: <String, dynamic>{
        'Key': key,
        'Value': jsonEncode(value),
      },
    );
  }

  Map<String, dynamic> _versions;

  Future<void> _flushVersions() => setConf('_versions', _versions);

  @override
  Future<void> load() async {
    await super.load();
    con = PostgreSQLConnection(
      host,
      port,
      database,
      username: user,
      password: decryptSecret('postgre-password', password),
    );
    await con.open();
    log('Opened database');

    await con.execute('''
      create table if not exists Config (
        Key text primary key,
        Value text
      );
    ''');

    _versions = await getConf<Map<String, dynamic>>('_versions') ?? <String, dynamic>{};

    log('Initialized');
  }

  @override
  void dispose() {
    super.dispose();
    con.close();
  }
}

mixin DatabaseLoader on Module {
  DatabaseModule database;

  @override
  Future<void> load() async {
    await super.load();
    database = await scope.require();
    dbStorage = await database.getConf<dynamic>(canonicalName);

    final setup = dbSetup.toList();
    final version = (database._versions[canonicalName] as int) ?? 0;
    for (var i = version; i < setup.length; i++) {
      database.log('Upgrading $canonicalName schema to version ${i + 1}');

      final dynamic query = setup[i];
      if (query is String) {
        await database.con.execute(query);
      } else if (query is FutureOr<void> Function()) {
        await query();
      } else {
        throw ArgumentError('dbSetup contained ${query.runtimeType} at index $i, String or FutureOr<void> Function() expected');
      }

      database._versions[canonicalName] = i + 1;
      await database._flushVersions();
    }
  }

  Timer _timer;
  var _repeat = false;

  void saveDbStorage() {
    if (_timer != null) {
      _repeat = !_timer.isActive;
    } else {
      _repeat = false;
      _timer = Timer(const Duration(seconds: 1), () async {
        try {
          await database.setConf(canonicalName, dbStorage);
        } finally {
          _timer = null;
          if (_repeat) {
            saveDbStorage();
          }
        }
      });
    }
  }

  Iterable<dynamic> get dbSetup => const <dynamic>[];

  dynamic dbStorage;
}
