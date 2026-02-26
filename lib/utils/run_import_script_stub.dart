/// Stub when dart:io is not available (e.g. web). Script cannot be run.

Future<RunScriptResult> runImportScript(List<String> args, String workingDirectory) async {
  return RunScriptResult(exitCode: -1, stdout: '', stderr: 'Not available on this platform.');
}

class RunScriptResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  RunScriptResult({required this.exitCode, required this.stdout, required this.stderr});
}
