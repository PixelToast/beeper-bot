import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:hotreloader/hotreloader.dart';

import 'package:beeper/discord/discord.dart';
import 'package:beeper/modules.dart';

extension ModuleBotExtension on Module {
  Bot get bot => system as Bot;
}

class Bot extends ModuleSystem {
  Discord discord;
  String version;

  void start() async {
    final configFile = File('config/bot.yaml');
    final configStat = configFile.statSync();

    if (configStat.type != FileSystemEntityType.file) {
      throw Exception('Configuration file config/bot.yaml not found or of wrong type');
    } else if (!Platform.isWindows && configStat.mode & 7 != 0) {
      throw Exception('Configuration file is accessible to outside users, mode 660 is recommended');
    }

    final dynamic botConfig = loadYaml(await configFile.readAsString());

    if (botConfig['version'] != null) {
      version = botConfig['version'] as String;
    } else {
      try {
        final result = await Process.run('git', ['rev-parse', '--short', 'HEAD']);
        version = result.stdout.toString().trim();
        if (version.isEmpty) {
          version = 'unknown';
        }
      } catch (e) {
        version = 'unknown';
      }
    }

    if (botConfig['development'] == true) {
      stderr.writeln('Hot reload started');
      await HotReloader.create(
        onAfterReload: (ctx) {
          stderr.writeln('Hot reload finished with ${ctx.result}');
        }
      );
    }

    scope = ModuleScope(system: this, parent: null);
    initializing = true;
    for (final config in botConfig['modules']) {
      final candidates = moduleMetadata.entries.where((e) => e.value.name == config['type']);
      if (candidates.isEmpty) {
        throw StateError('Could not find module with name "${config['type']}"');
      }
      final metadata = candidates.single;
      final module = metadata.value.factory(config);
      print('Loading module ${metadata.value.name}');
      await scope.injectWith(metadata.key, module, id: config['id']);
    }
    print('Done initializing');
    initializing = false;
  }
}