import 'dart:io';

import 'run_import_script_stub.dart';

Future<RunScriptResult> runImportScript(List<String> args, String workingDirectory) async {
  final cwd = workingDirectory.isEmpty || workingDirectory == '.'
      ? Directory.current.path
      : workingDirectory;
  final result = await Process.run(
    'python',
    args,
    runInShell: true,
    workingDirectory: cwd,
  );
  return RunScriptResult(
    exitCode: result.exitCode,
    stdout: (result.stdout as String? ?? ''),
    stderr: (result.stderr as String? ?? ''),
  );
}
