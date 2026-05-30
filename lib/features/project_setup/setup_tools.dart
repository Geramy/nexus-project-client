// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import '../../infrastructure/database/nexus_database.dart' hide ProjectTag;
import '../../infrastructure/registry/registry_models.dart';
import '../../infrastructure/registry/verification_service.dart';
import '../project_plans/plan_store.dart';
import 'models/project_tag.dart';
import 'models/tag_category.dart';
import 'plan_generator.dart';
import 'providers/tag_providers.dart';

/// The bounded toolset the setup-interview AI may call. The AI hosts the
/// conversation, but it can only: ask the user a multiple-choice question,
/// verify a package/repo against the registries, propose tags (always
/// `proposed`), or finalize (resolve stack + generate plans). It can never
/// invent a freshness verdict or silently mutate the confirmed stack.
class SetupTools {
  static List<Map<String, dynamic>> buildToolSchemas() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'ask_question',
          'description':
              'Ask the user ONE bounded question. The user answers by picking '
                  'from the options you provide — never free text. Use this to '
                  'learn industries, platforms, and objectives.',
          'parameters': {
            'type': 'object',
            'properties': {
              'question': {'type': 'string'},
              'options': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'The selectable choices (2-8).',
              },
              'multi': {
                'type': 'boolean',
                'description': 'True if the user may pick more than one option.',
              },
            },
            'required': ['question', 'options'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'lookup_package',
          'description':
              'Verify a library/framework against pub.dev or GitHub and get a '
                  'deterministic freshness verdict (fresh|aging|stale|dead). '
                  'Use before proposing any library tag.',
          'parameters': {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': 'Package name (pub.dev) or owner/repo (GitHub).',
              },
              'ecosystem': {
                'type': 'string',
                'enum': ['pubdev', 'github'],
              },
            },
            'required': ['name', 'ecosystem'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'propose_tags',
          'description':
              'Propose one or more tags for the project profile. They are saved '
                  'as `proposed` for the user to accept/reject — never auto-'
                  'accepted. Languages and platforms must use the allowed vocab.',
          'parameters': {
            'type': 'object',
            'properties': {
              'tags': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'category': {
                      'type': 'string',
                      'enum': [
                        'industries',
                        'platforms',
                        'objectives',
                        'features',
                        'languages',
                        'frameworks',
                        'libraries',
                      ],
                    },
                    'value': {'type': 'string'},
                    'layerKey': {
                      'type': 'string',
                      'enum': ['client', 'server', 'db', 'worker', 'module'],
                    },
                    'forLanguage': {
                      'type': 'string',
                      'description':
                          'Libraries ONLY: the language this package is used '
                              'with (e.g. "Dart", "C#"). Must be an allowed '
                              'Languages value. Omit for non-library tags.',
                    },
                    'rationale': {'type': 'string'},
                    'sourceUrl': {'type': 'string'},
                  },
                  'required': ['category', 'value'],
                },
              },
            },
            'required': ['tags'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'finalize_setup',
          'description':
              'Resolve the architecture from the confirmed tags and generate the '
                  '/PLANS layer files. Call when the user is satisfied with the '
                  'profile.',
          'parameters': {'type': 'object', 'properties': {}},
        },
      },
    ];
  }
}

/// Executes the bounded setup tools against the live DB + registries.
class SetupToolExecutor {
  SetupToolExecutor({
    required this.db,
    required this.projectPk,
    required this.verification,
    required this.planStore,
    this.askQuestion,
  });

  final NexusDatabase db;
  final int projectPk;
  final VerificationService verification;

  /// Resolved plan store for the project workspace; null disables finalize's
  /// file generation (the resolver still runs and the status is set).
  final PlanStore? planStore;

  /// UI hook: presents [question] with [options] and returns the user's
  /// selection(s). When null, ask_question reports that input isn't available.
  final Future<List<String>> Function(
          String question, List<String> options, bool multi)?
      askQuestion;

  Future<String> execute(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'ask_question':
        return _ask(args);
      case 'lookup_package':
        return _lookup(args);
      case 'propose_tags':
        return _propose(args);
      case 'finalize_setup':
        return _finalize();
      default:
        return 'Unknown setup tool "$name".';
    }
  }

  Future<String> _ask(Map<String, dynamic> args) async {
    final question = (args['question'] ?? '').toString();
    final options = ((args['options'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final multi = args['multi'] == true;
    if (askQuestion == null) {
      return 'Cannot ask the user here (no input channel). Proceed with sensible defaults.';
    }
    final picked = await askQuestion!(question, options, multi);
    if (picked.isEmpty) return 'User skipped the question.';
    return 'User selected: ${picked.join(', ')}.';
  }

  Future<String> _lookup(Map<String, dynamic> args) async {
    final name = (args['name'] ?? '').toString().trim();
    final ecosystem = (args['ecosystem'] ?? 'pubdev').toString();
    if (name.isEmpty) return 'lookup_package needs a name.';
    try {
      final r = await verification.verify(name: name, ecosystem: ecosystem);
      final parts = <String>[
        'verdict=${r.verdict.wire}',
        if (r.lastCommit != null) 'lastCommit=${_d(r.lastCommit!)}',
        if (r.lastRelease != null) 'lastRelease=${_d(r.lastRelease!)}',
        if (r.archived) 'ARCHIVED',
        if (r.popularity != null) 'popularity=${r.popularity}',
        if (r.owner != null) 'owner=${r.owner}',
        if (r.isTrusted) 'trusted-org',
      ];
      return '$name ($ecosystem): ${parts.join(', ')}.'
          '${r.repoUrl != null ? ' repo=${r.repoUrl}' : ''}';
    } catch (e) {
      return 'Could not verify $name: $e';
    }
  }

  Future<String> _propose(Map<String, dynamic> args) async {
    final raw = (args['tags'] as List?) ?? const [];
    final controller = TagController(db, projectPk);
    final accepted = <String>[];
    final skipped = <String>[];

    for (final entry in raw) {
      if (entry is! Map) continue;
      final category = TagCategoryX.fromWire(entry['category']?.toString());
      final value = (entry['value'] ?? '').toString().trim();
      if (category == null || value.isEmpty) continue;

      // Enforce closed vocab for languages/platforms (anti-hallucination).
      if (category.vocab == VocabKind.closed &&
          !category.vocabulary
              .map((v) => v.toLowerCase())
              .contains(value.toLowerCase())) {
        skipped.add('$value (not an allowed ${category.label} value)');
        continue;
      }

      // Libraries can attach to the language they're used with (closed vocab).
      String? forLanguage;
      if (category == TagCategory.libraries) {
        final raw = entry['forLanguage']?.toString().trim();
        if (raw != null && raw.isNotEmpty) {
          for (final lang in kLanguages) {
            if (lang.toLowerCase() == raw.toLowerCase()) {
              forLanguage = lang;
              break;
            }
          }
        }
      }

      // Library tags must carry a verified verdict.
      String? verdict;
      DateTime? verifiedAt;
      final sourceUrl = entry['sourceUrl']?.toString();
      if (category == TagCategory.libraries) {
        try {
          final eco = (sourceUrl != null && sourceUrl.contains('github.com'))
              ? 'github'
              : 'pubdev';
          final r = await verification.verify(name: value, ecosystem: eco);
          verdict = r.verdict.wire;
          verifiedAt = r.checkedAt;
        } catch (_) {}
      }

      await controller.upsert(ProjectTag(
        category: category,
        value: value,
        source: TagSource.ai,
        origin: 'setup',
        status: TagStatus.proposed,
        layerKey: entry['layerKey']?.toString(),
        forLanguage: forLanguage,
        rationale: entry['rationale']?.toString(),
        sourceUrl: sourceUrl,
        verdict: verdict,
        verifiedAt: verifiedAt,
      ));
      accepted.add(value);
    }

    final b = StringBuffer();
    if (accepted.isNotEmpty) b.write('Proposed: ${accepted.join(', ')}.');
    if (skipped.isNotEmpty) b.write(' Skipped: ${skipped.join('; ')}.');
    return b.isEmpty ? 'No valid tags to propose.' : b.toString();
  }

  Future<String> _finalize() async {
    final tags = await db.getTagsForProject(projectPk);
    final uiTags = tags
        .map((row) => ProjectTag(
              tagPk: row.tag_pk,
              category: TagCategoryX.fromWire(row.category) ??
                  TagCategory.objectives,
              value: row.value,
              source: TagSourceX.fromWire(row.source),
              origin: row.origin,
              status: TagStatusX.fromWire(row.status),
              layerKey: row.layerKey,
              forLanguage: row.forLanguage,
              rationale: row.rationale,
              sourceUrl: row.sourceUrl,
              verdict: row.verdict,
            ))
        .where((t) => !t.isRejected)
        .toList();

    var generated = <String>[];
    if (planStore != null) {
      generated = await PlanGenerator(planStore!).generate(uiTags);
    }
    await db.setProjectSetupStatus(projectPk, 'complete');

    return generated.isEmpty
        ? 'Setup finalized. (No workspace available to write plan files.)'
        : 'Setup finalized. Generated: ${generated.join(', ')}.';
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
