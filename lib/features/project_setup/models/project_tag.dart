// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'tag_category.dart';

/// Confirm state for a tag. Consumers read everything EXCEPT [rejected].
enum TagStatus { proposed, accepted, rejected }

/// Who introduced a tag.
/// Where a tag came from:
/// - [user]: the user typed it (free text / their own description).
/// - [chosen]: the user SELECTED it from AI-suggested options in an ask_question
///   (AI offered, user picked — their explicit choice, not the AI's invention).
/// - [ai]: the AI derived/inferred it itself (the stack, or unmistakable
///   implications) without the user picking it from a list.
/// - [workspace]: discovered from existing workspace files.
enum TagSource { user, chosen, ai, workspace }

extension TagStatusX on TagStatus {
  String get wire => name;
  static TagStatus fromWire(String? s) => switch (s) {
    'accepted' => TagStatus.accepted,
    'rejected' => TagStatus.rejected,
    _ => TagStatus.proposed,
  };
}

extension TagSourceX on TagSource {
  String get wire => name;
  static TagSource fromWire(String? s) => switch (s) {
    'user' => TagSource.user,
    'chosen' => TagSource.chosen,
    'workspace' => TagSource.workspace,
    _ => TagSource.ai,
  };
}

/// UI-facing view of a ProjectTags row. Decouples widgets/resolver from the
/// Drift-generated row so the closed-vocab + status logic is testable.
class ProjectTag {
  final int? tagPk;

  /// The tag's section key — a setup-flow stage key (e.g. 'industries',
  /// 'callPurpose'). Stored raw so non-software flows (IVR) work; software
  /// consumers use [knownCategory] for enum semantics.
  final String category;
  final String value;
  final TagSource source;
  final String origin; // setup|plan|agent|workspace
  final TagStatus status;
  final String?
  layerKey; // client|server|db|worker|module ; null = project-wide
  final String?
  forLanguage; // libraries only: the language this lib is used with
  final String? rationale;
  final String? sourceUrl;
  final String? verdict; // fresh|aging|stale|dead (library/framework only)
  final DateTime? verifiedAt;

  const ProjectTag({
    required this.category,
    required this.value,
    this.tagPk,
    this.source = TagSource.ai,
    this.origin = 'setup',
    this.status = TagStatus.proposed,
    this.layerKey,
    this.forLanguage,
    this.rationale,
    this.sourceUrl,
    this.verdict,
    this.verifiedAt,
  });

  /// The known software [TagCategory] for this tag, or null for a non-software
  /// (flow-defined) category. Software-only consumers (stack resolver, plan
  /// generator) use this; the board groups by the raw [category] string.
  TagCategory? get knownCategory => TagCategoryX.fromWire(category);

  /// True when the user has neither confirmed nor rejected — shown as a ghost
  /// chip that survives untouched per the agreed semantics.
  bool get isProposed => status == TagStatus.proposed;
  bool get isAccepted => status == TagStatus.accepted;
  bool get isRejected => status == TagStatus.rejected;

  ProjectTag copyWith({
    int? tagPk,
    String? category,
    String? value,
    TagSource? source,
    String? origin,
    TagStatus? status,
    String? layerKey,
    String? forLanguage,
    String? rationale,
    String? sourceUrl,
    String? verdict,
    DateTime? verifiedAt,
  }) {
    return ProjectTag(
      tagPk: tagPk ?? this.tagPk,
      category: category ?? this.category,
      value: value ?? this.value,
      source: source ?? this.source,
      origin: origin ?? this.origin,
      status: status ?? this.status,
      layerKey: layerKey ?? this.layerKey,
      forLanguage: forLanguage ?? this.forLanguage,
      rationale: rationale ?? this.rationale,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      verdict: verdict ?? this.verdict,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}
