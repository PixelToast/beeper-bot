import 'package:postgres/postgres.dart';
import 'package:meta/meta.dart';

import 'package:beeper/modules.dart';

@Metadata(name: 'database')
class DatabaseModule extends Module {
  PostgreSQLConnection connection;

  final Uri uri;

  DatabaseModule({
    @required String uri,
  }) : uri = Uri.parse(uri);

  @override
  Future<void> load() async {
    final userInfo = uri.userInfo.split(':');
    connection = PostgreSQLConnection(
      uri.host,
      uri.port,
      uri.pathSegments.single,
      username: userInfo[0],
      password: userInfo[1],
    );
    await connection.open();
    return super.load();
  }
}