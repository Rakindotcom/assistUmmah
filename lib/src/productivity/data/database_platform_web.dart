import 'package:sembast_web/sembast_web.dart';

Future<(DatabaseFactory, String)> productivityDatabaseLocation(
        String accountHash) async =>
    (databaseFactoryWeb, 'productivity-v1-$accountHash');
