// Probe: can we exercise VhdWorkspace + NxtprjGitEngine (sqlite + libgit2 FFI)
// under `flutter test`? If this passes, the full git-isolation tests can run in CI.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/infrastructure/workspace/vhd_workspace.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/nxtprj_git_engine.dart';

void main() {
  test('VhdWorkspace + git engine open, commit, and read back', () async {
    final dir = await Directory.systemTemp.createTemp('nx-git-probe');
    final ws = await VhdWorkspace.open('${dir.path}/p.nxtprj');
    final git = await NxtprjGitEngine.open(ws);
    try {
      await ws.writeString('/hello.txt', 'world');
      final oid = await git.commitAll(message: 'init');
      expect(oid, isNotEmpty);
      final branches = await git.branches();
      expect(branches, contains('main'));
    } finally {
      git.dispose();
      ws.dispose();
      await dir.delete(recursive: true);
    }
  });
}
