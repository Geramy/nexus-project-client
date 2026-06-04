// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Export the project's user-story TREE (epics → stories → sub-stories, with
/// narratives, acceptance criteria, and notes) to a PDF the user can save/share.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../infrastructure/database/nexus_database.dart';

/// Reads the stories + notes for [projectId], builds the PDF, and opens the
/// OS save/share/print sheet. Returns the number of stories exported.
Future<int> exportStoryTreePdf(NexusDatabase db, int projectId) async {
  final project = await db.getProjectById(projectId);
  final projectName = project?.name ?? 'Project';
  final stories = await db.getUserStoriesForProject(projectId);

  final notesByStory = <int, List<StoryNote>>{};
  for (final s in stories) {
    final notes = await db.getNotesForStory(s.story_pk);
    if (notes.isNotEmpty) notesByStory[s.story_pk] = notes;
  }

  final bytes = await _buildStoryTreePdf(
    projectName: projectName,
    stories: stories,
    notesByStory: notesByStory,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: '${_slug(projectName)}-user-stories.pdf',
  );
  return stories.length;
}

String _slug(String s) {
  final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final trimmed = t.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'project' : trimmed;
}

Future<Uint8List> _buildStoryTreePdf({
  required String projectName,
  required List<UserStory> stories,
  required Map<int, List<StoryNote>> notesByStory,
}) async {
  final doc = pw.Document();

  // Group children by parent and order siblings stably.
  final childrenOf = <int?, List<UserStory>>{};
  for (final s in stories) {
    (childrenOf[s.parent_story_fk] ??= <UserStory>[]).add(s);
  }
  for (final list in childrenOf.values) {
    list.sort((a, b) {
      final o = a.orderIndex.compareTo(b.orderIndex);
      return o != 0 ? o : a.story_pk.compareTo(b.story_pk);
    });
  }

  PdfColor statusColor(String status) => switch (status) {
    'confirmed' => PdfColors.blue700,
    'done' => PdfColors.green700,
    _ => PdfColors.grey600,
  };

  List<pw.Widget> renderStory(UserStory s, int depth) {
    final out = <pw.Widget>[];
    final ac = (s.acceptanceCriteria ?? '').trim();
    final notes = notesByStory[s.story_pk] ?? const [];

    out.add(
      pw.Container(
        margin: pw.EdgeInsets.only(left: depth * 18.0, top: 8, bottom: 2),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: statusColor(s.status), width: 3),
          ),
          color: PdfColors.grey100,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    s.title,
                    style: pw.TextStyle(
                      fontSize: depth == 0 ? 13 : 11.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Text(
                  '${s.kind} · ${s.status}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: statusColor(s.status),
                  ),
                ),
              ],
            ),
            if (s.narrative.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  s.narrative.trim(),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            if (ac.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(
                  'Acceptance criteria:\n$ac',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                ),
              ),
            if (notes.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Notes:',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                    for (final n in notes)
                      pw.Bullet(
                        text: n.body.trim(),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    for (final child in childrenOf[s.story_pk] ?? const []) {
      out.addAll(renderStory(child, depth + 1));
    }
    return out;
  }

  final body = <pw.Widget>[];
  final roots = childrenOf[null] ?? const [];
  if (roots.isEmpty) {
    body.add(pw.Text('No user stories yet.'));
  }
  for (final root in roots) {
    body.addAll(renderStory(root, 0));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                '$projectName — User Stories',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
        ),
      ),
      build: (ctx) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            '$projectName — User Stories',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Text(
          '${stories.length} stories',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 8),
        ...body,
      ],
    ),
  );

  return doc.save();
}
