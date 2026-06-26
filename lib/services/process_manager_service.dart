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
  }) async {
    await stop(id);
    final mp = ManagedProcess(id);
    _processes[id] = mp;
    mp.status = ProcessStatus.running;
    mp.addOutput('> $executable ${args.join(' ')}\n');
    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
      );
      mp.process = process;
      mp._stdoutSub = process.stdout.transform(utf8.decoder).listen(
        (data) => mp.addOutput(data),
        onError: (e) => mp.addOutput('[stdout error] $e\n'),
        cancelOnError: false,
      );
      mp._stderrSub = process.stderr.transform(utf8.decoder).listen(
        (data) => mp.addOutput(data),
        onError: (e) => mp.addOutput('[stderr error] $e\n'),
        cancelOnError: false,
      );
      mp.exitCode = await process.exitCode;
      mp.status = mp.exitCode == 0 ? ProcessStatus.stopped : ProcessStatus.failed;
      mp.addOutput('--- 进程退出 (exit code: ${mp.exitCode}) ---\n');
    } catch (e) {
      mp.status = ProcessStatus.failed;
      mp.addOutput('--- 启动失败: $e ---\n');
    }
  }

  Future<void> stop(String id) async {
    final mp = _processes[id];
    if (mp == null || mp.process == null) return;
    try {
      mp.process!.kill();
      mp.addOutput('--- 进程已停止 ---\n');
    } catch (_) {}
    mp.status = ProcessStatus.stopped;
    mp.close();
    _processes.remove(id);
  }

  void killAll() {
    for (final entry in _processes.entries.toList()) {
      try {
        entry.value.process?.kill();
        entry.value.close();
      } catch (_) {}
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
