// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/infrastructure/update/update_downloader.dart';
import 'package:nexus_projects_client/infrastructure/update/update_models.dart';

void main() {
  group('SemVer', () {
    test('parses with/without v prefix and +build', () {
      expect(SemVer.tryParse('1.7.1').toString(), '1.7.1');
      expect(SemVer.tryParse('v1.8.0').toString(), '1.8.0');
      expect(SemVer.tryParse('v1.8.0+24').toString(), '1.8.0');
      expect(SemVer.tryParse('v2.0.0-beta.1').toString(), '2.0.0-beta.1');
      expect(SemVer.tryParse('not-a-version'), isNull);
    });

    test('orders by major.minor.patch', () {
      expect(
        SemVer.tryParse('1.8.0')!.isNewerThan(SemVer.tryParse('1.7.9')!),
        isTrue,
      );
      expect(
        SemVer.tryParse('2.0.0')!.isNewerThan(SemVer.tryParse('1.9.9')!),
        isTrue,
      );
      expect(
        SemVer.tryParse('1.7.1')!.isNewerThan(SemVer.tryParse('1.7.1')!),
        isFalse,
      );
    });

    test('a pre-release is older than the same final version', () {
      final pre = SemVer.tryParse('1.8.0-beta.1')!;
      final fin = SemVer.tryParse('1.8.0')!;
      expect(fin.isNewerThan(pre), isTrue);
      expect(pre.isNewerThan(fin), isFalse);
    });
  });

  group('parseChecksums', () {
    test('parses standard and binary-mode lines, ignoring junk', () {
      const body = '''
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  nexus_projects_client-1.8.0-macos.pkg
deadbeef *nexus_projects_client-1.8.0-windows-setup.exe

3b8c...too-short  ignored.deb
''';
      final map = UpdateDownloader.parseChecksums(body);
      expect(
        map['nexus_projects_client-1.8.0-macos.pkg'],
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      // 'deadbeef' isn't 64 hex chars, so the windows line is dropped.
      expect(
        map.containsKey('nexus_projects_client-1.8.0-windows-setup.exe'),
        isFalse,
      );
      expect(map.containsKey('ignored.deb'), isFalse);
    });
  });

  group('verify', () {
    test(
      'matches the known SHA-256 of "abc" and rejects a wrong digest',
      () async {
        final dir = await Directory.systemTemp.createTemp('nx-update-test');
        final f = File('${dir.path}/abc.bin');
        await f.writeAsString('abc');
        // Well-known: sha256("abc").
        const known =
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
        expect(await UpdateDownloader.verify(f, known), isTrue);
        expect(
          await UpdateDownloader.verify(f, 'BA7816BF8F01CFEA'.toUpperCase()),
          isFalse,
        );
        await dir.delete(recursive: true);
      },
    );
  });

  group('AppRelease asset matching', () {
    test('finds this platform installer + checksums asset', () {
      final release = AppRelease(
        tag: 'v1.8.0',
        version: SemVer.tryParse('1.8.0')!,
        notesUrl: 'https://example/releases/v1.8.0',
        publishedAt: null,
        assets: const [
          UpdateAsset(
            name: 'nexus_projects_client-1.8.0-macos.pkg',
            url: 'u',
            sizeBytes: 1,
          ),
          UpdateAsset(
            name: 'nexus_projects_client-1.8.0-windows-setup.exe',
            url: 'u',
            sizeBytes: 1,
          ),
          UpdateAsset(
            name: 'nexus_projects_client-1.8.0-linux-amd64.deb',
            url: 'u',
            sizeBytes: 1,
          ),
          UpdateAsset(name: 'SHA256SUMS.txt', url: 'u', sizeBytes: 1),
        ],
      );
      expect(release.checksumsAsset(), isNotNull);
      // On a supported desktop host, the per-platform asset resolves; on an
      // unsupported host (mobile/web) it's null — both are acceptable.
      final target = PlatformTarget.current;
      if (target != null) {
        final asset = release.assetForThisPlatform();
        expect(asset, isNotNull);
        expect(asset!.name.toLowerCase().endsWith(target.assetSuffix), isTrue);
      }
    });
  });
}
