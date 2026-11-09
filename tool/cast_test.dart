// Bobine — test du cast DLNA, à lancer sur l'ordinateur à côté de la télé.
//
// Cherche les télés DLNA du réseau, puis essaie plusieurs façons de leur
// présenter une vidéo (type, description, drapeaux DLNA, relais ou adresse
// directe) : lesquelles la télé accepte, laquelle elle lit vraiment. Écrit
// un rapport sans mot de passe à côté du programme.
//
// Compilé par la CI (artefact « Bobine-test-cast ») :
//   dart compile exe tool/cast_test.dart -o bobine-test-cast.exe
// Utilisation : bobine-test-cast.exe [adresse ou fichier vidéo] [--tv nom] [--ua User-Agent] [--tout]

import 'dart:convert';
import 'dart:io';

import 'package:bobine/cast/cast_device.dart';
import 'package:bobine/cast/cast_log.dart';
import 'package:bobine/cast/cast_test_run.dart';
import 'package:bobine/cast/dlna.dart';
import 'package:bobine/cast/relay.dart';
import 'package:bobine/cast/ssdp.dart';
import 'package:bobine/core/text.dart';
import 'package:bobine/core/version.dart';

Future<void> main(List<String> args) async {
  final log = <String>[];
  castLog = log.add;
  var code = 0;
  try {
    code = await _run(args, log);
  } catch (e, st) {
    stdout.writeln('\nErreur inattendue : ${redactCredentials('$e')}');
    log.add('Erreur : $e\n$st');
    code = 1;
  }
  if (stdin.hasTerminal) {
    stdout.write('\nAppuie sur Entrée pour fermer.');
    stdin.readLineSync();
  }
  exit(code);
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

String _ask(String question) {
  stdout.write(question);
  return (stdin.readLineSync(encoding: utf8) ?? '').trim();
}

Future<int> _run(List<String> args, List<String> log) async {
  stdout.writeln('Bobine $kAppVersion — test du cast sur une télé DLNA\n');
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--tv' || args[i] == '--ua') {
      i++;
    } else if (!args[i].startsWith('--')) {
      positional.add(args[i]);
    }
  }

  // 1. The TVs of the network.
  stdout.writeln('Recherche des télés DLNA sur le réseau (5 s)…');
  final devices = <CastDevice>[];
  await DlnaBrowser().browse(timeout: const Duration(seconds: 5), onDevice: devices.add);
  if (devices.isEmpty) {
    stdout.writeln(
      'Aucune télé trouvée. Vérifie qu’elle est allumée, sur le même réseau que cet ordinateur, '
      'et que le pare-feu de Windows laisse passer ce programme.',
    );
    return 2;
  }
  devices.sort((a, b) => a.name.compareTo(b.name));
  for (final (i, d) in devices.indexed) {
    stdout.writeln('  ${i + 1}) ${d.name} — ${d.kindLabel} ${d.model ?? ''} (${d.host})');
  }
  CastDevice device;
  final wanted = _option(args, '--tv')?.toLowerCase();
  if (wanted != null && devices.any((d) => d.name.toLowerCase().contains(wanted))) {
    device = devices.firstWhere((d) => d.name.toLowerCase().contains(wanted));
  } else if (devices.length == 1) {
    device = devices.single;
  } else {
    final n = int.tryParse(_ask('Numéro de la télé à tester [1] : ')) ?? 1;
    device = devices[(n - 1).clamp(0, devices.length - 1)];
  }
  stdout.writeln('Télé testée : ${device.name}\n');

  // 2. The video.
  var target = positional.isNotEmpty ? positional.first : '';
  while (target.isEmpty) {
    stdout.writeln('Adresse de la vidéo à tester, par exemple pour une série Xtream :');
    stdout.writeln('  https://serveur/series/IDENTIFIANT/MOT_DE_PASSE/12345.mkv');
    stdout.writeln('(ou le chemin d’un fichier vidéo de cet ordinateur)');
    target = _ask('> ').replaceAll('"', '');
  }
  final live = target.contains('/live/');
  stdout.writeln('Vidéo : ${redactCredentials(target)}${live ? ' (direct)' : ''}\n');

  // 3. Connection and formats of the TV.
  final session = DlnaSession(device);
  await session.connect();
  stdout.writeln('Cet ordinateur vu de la télé : ${session.localAddress?.address ?? 'introuvable'}');
  stdout.writeln('Formats annoncés par la télé : ${session.sink.length}\n');
  if (session.localAddress == null) return 3;

  // 4. The variants.
  final requests = <RelayRequest>[];
  final relay = CastRelay(onRequest: requests.add);
  final results = await CastTester(
    session,
    relay,
    say: stdout.writeln,
  ).run(target, live: live, userAgent: _option(args, '--ua'), all: args.contains('--tout'));

  // 5. Summary and report.
  final played = results.where((r) => r.played).toList();
  stdout.writeln();
  if (played.isNotEmpty) {
    stdout.writeln('RÉSULTAT : la télé lit la vidéo avec « ${played.first.variant.label} ».');
  } else if (results.any((r) => r.accepted)) {
    stdout.writeln('RÉSULTAT : la télé accepte la vidéo mais ne la lit pas (format ou codec non pris en charge ?).');
  } else {
    stdout.writeln('RÉSULTAT : la télé refuse toutes les façons de présenter la vidéo.');
  }
  final report = castTestReport(session: session, target: target, results: results, requests: requests, log: log);
  final file = File('${Directory.current.path}${Platform.pathSeparator}bobine-test-cast.txt');
  await file.writeAsString(report);
  stdout.writeln('Rapport (sans mot de passe) : ${file.path}');
  stdout.writeln('Envoie-le pour que Bobine utilise la bonne façon.');
  await relay.close();
  await session.close();
  return played.isNotEmpty ? 0 : 4;
}
