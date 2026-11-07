import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<(DatabaseFactory, String)> productivityDatabaseLocation(
    String accountHash) async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory('${root.path}/productivity-v1');
  await directory.create(recursive: true);
  return (databaseFactoryIo, '${directory.path}/$accountHash.db');
}
