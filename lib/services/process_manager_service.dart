import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ProcessStatus { stopped, running, failed }

class ManagedProcess {
  final String id;
  Process? process;
  ProcessStatus status = ProcessStatus.stopped;
  final StreamController<String> _outputController = StreamController<String>.broadcast();
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  int? exitCode;

  ManagedProcess(this.id);

  Stream<String> get output => _outputController.stream;
  bool get isRunning => status == ProcessStatus.running;

  void addOutput(String line) {
    if (!_outputController.isClosed) {
      _outputController.add(line);
    }
  }

  void close() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    if (!_outputController.isClosed) {
      _outputController.close();
    }
  }
}

class ProcessManagerService {
  static final ProcessManagerService instance = ProcessManagerService._();
  final Map<String, ManagedProcess> _processes = {};

  ProcessManagerService._();

  ManagedProcess? getProcess(String id) => _processes[id];

  ProcessStatus getStatus(String id) => _processes[id]?.status ?? ProcessStatus.stopped;

  bool isRunning(String id) => getStatus(id) == ProcessStatus.running;

  Stream<String> subscribe(String id) {
    final p = _processes.putIfAbsent(id, () => ManagedProcess(id));
    return p.output;
  }

  Future<void> start(String id, {
    required String executable,
    List<String> args = const [],
    String? workingDirectory,
    void Function(String line)? onOutput,
  }) async {
    await stop(id);
    final mp = ManagedProcess(id);
    _processes[id] = mp;
    mp.status = ProcessStatus.running;

    final exeDisplay = executable.split(Platform.pathSeparator).last;
    mp.addOutput('> $exeDisplay ${args.join(' ')}\n');

    try {
      // On Windows, use cmd.exe explicitly to avoid runInShell quoting issues
      // with -D properties and paths containing spaces
      final wd = workingDirectory?.replaceAll('/', '\\');

      // Build argument string — quote args containing spaces or special chars
      final argParts = <String>[];
      for (final a in args) {
        if (a.contains(' ') || a.contains('&') || a.contains('|')) {
          argParts.add('"$a"');
        } else {
          argParts.add(a);
        }
      }
      final argStr = argParts.join(' ');

      // Construct: cd /d "wd" && "java.exe" args
      final exeQuoted = '"${executable.replaceAll('/', '\\')}"';
      final cmdBody = wd != null && wd.isNotEmpty
          ? 'cd /d "$wd" && $exeQuoted $argStr'
          : '$exeQuoted $argStr';

      final process = await Process.start(
        'cmd.exe',
        ['/c', cmdBody],
      );

      mp.process = process;
      mp._stdoutSub = process.stdout.transform(utf8.decoder).listen(
        (data) {
          mp.addOutput(data);
          onOutput?.call(data);
        },
        onError: (e) => mp.addOutput('[stdout error] $e\n'),
        cancelOnError: false,
      );
      mp._stderrSub = process.stderr.transform(utf8.decoder).listen(
        (data) {
          mp.addOutput(data);
          onOutput?.call(data);
        },
        onError: (e) => mp.addOutput('[stderr error] $e\n'),
        cancelOnError: false,
      );
      process.exitCode.then((code) {
        mp.exitCode = code;
        mp.status = code == 0 ? ProcessStatus.stopped : ProcessStatus.failed;
        mp.addOutput('--- 进程退出 (exit code: $code) ---\n');
      });
    } catch (e) {
      mp.status = ProcessStatus.failed;
      mp.addOutput('--- 启动失败: $e ---\n');
    }
  }

  Future<void> stop(String id) async {
    final mp = _processes[id];
    if (mp == null) return;
    final pid = mp.process?.pid;
    if (pid != null) {
      try {
        // Kill entire process tree (cmd.exe + child java.exe)
        await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
        mp.addOutput('--- 进程已停止 ---\n');
      } catch (_) {
        try { mp.process?.kill(); } catch (_) {}
      }
    }
    mp.status = ProcessStatus.stopped;
    mp.close();
    _processes.remove(id);
  }

  void killAll() {
    for (final entry in _processes.entries.toList()) {
      final pid = entry.value.process?.pid;
      if (pid != null) {
        try {
          Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
        } catch (_) {
          try { entry.value.process?.kill(); } catch (_) {}
        }
      }
      entry.value.close();
    }
    _processes.clear();
  }

  List<String> getRunningIds() {
    return _processes.entries
      .where((e) => e.value.status == ProcessStatus.running)
      .map((e) => e.key)
      .toList();
  }
}
