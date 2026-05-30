// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// The seven sections of the project profile. Every tag belongs to exactly one.
/// Categories split into two families:
///   - Intent (user-led): industries, platforms, objectives, features.
///   - Stack (AI/resolver-derived, user confirms): languages, frameworks, libraries.
enum TagCategory {
  industries,
  platforms,
  objectives,
  features,
  languages,
  frameworks,
  libraries,
}

/// How a section's "+ Add" picker behaves:
///   - closed:  fixed list, no invented values (languages, platforms).
///   - curated: suggested list but free entry allowed (industries, objectives,
///              frameworks).
///   - open:    free entry / registry search (libraries — verified, not vocab-bound).
enum VocabKind { closed, curated, open }

extension TagCategoryX on TagCategory {
  String get wire => name;

  static TagCategory? fromWire(String? s) {
    for (final c in TagCategory.values) {
      if (c.name == s) return c;
    }
    return null;
  }

  String get label => switch (this) {
        TagCategory.industries => 'Applicable Industries',
        TagCategory.platforms => 'Platforms',
        TagCategory.objectives => 'Objectives',
        TagCategory.features => 'Features',
        TagCategory.languages => 'Languages',
        TagCategory.frameworks => 'Frameworks',
        TagCategory.libraries => 'Libraries',
      };

  /// Whether this category is part of the resolver-derived stack family.
  bool get isStack => switch (this) {
        TagCategory.languages ||
        TagCategory.frameworks ||
        TagCategory.libraries =>
          true,
        _ => false,
      };

  VocabKind get vocab => switch (this) {
        TagCategory.languages => VocabKind.closed,
        TagCategory.platforms => VocabKind.closed,
        TagCategory.industries => VocabKind.curated,
        TagCategory.objectives => VocabKind.curated,
        TagCategory.features => VocabKind.curated,
        TagCategory.frameworks => VocabKind.curated,
        TagCategory.libraries => VocabKind.open,
      };

  /// Suggested/allowed values for the "+ Add" picker. For [VocabKind.closed]
  /// these are the only permitted values; for [VocabKind.curated] they seed the
  /// picker but free entry is allowed; [VocabKind.open] returns empty (search).
  List<String> get vocabulary => switch (this) {
        TagCategory.languages => kLanguages,
        TagCategory.platforms => kPlatforms,
        TagCategory.industries => kIndustries,
        TagCategory.objectives => kObjectives,
        TagCategory.features => kFeatures,
        TagCategory.frameworks => kFrameworks,
        TagCategory.libraries => const [],
      };
}

/// Closed vocab — the only languages the resolver/UI will stamp.
const List<String> kLanguages = [
  'Dart',
  'C',
  'C++',
  'C#',
  'Java',
  'Rust',
  'Go',
  'Python',
  'TypeScript',
  'SQL',
];

/// Closed vocab — target surfaces.
const List<String> kPlatforms = [
  'Web',
  'iOS',
  'Android',
  'macOS',
  'Windows',
  'Linux',
  'Embedded',
  'Cloud / Server',
];

/// Curated seeds — industries the app may serve.
const List<String> kIndustries = [
  'Healthcare',
  'Finance',
  'Education',
  'E-commerce',
  'Gaming',
  'Logistics',
  'Manufacturing',
  'Media',
  'Government',
  'Security',
  'Developer Tools',
  'IoT',
];

/// Curated seeds — what the system must do (drives the resolver).
const List<String> kObjectives = [
  'Customer-facing UI',
  'Admin dashboard',
  'Public API',
  'Realtime / streaming',
  'Heavy computation',
  'Highly distributed',
  'Memory-safety critical',
  'Data persistence',
  'Offline support',
  'Authentication',
  'Payments',
  'Machine learning',
];

/// Curated seeds — concrete product features (free entry encouraged; these are
/// project-specific capabilities the app must ship, distinct from the broader
/// [TagCategory.objectives] which describe system-level intent).
const List<String> kFeatures = [
  'User accounts',
  'Role-based access',
  'Client portal',
  'Billing & invoicing',
  'Expense tracking',
  'Time tracking',
  'Geofencing',
  'Inventory / asset checkout',
  'Scheduling / calendar',
  'Notifications',
  'Reporting & analytics',
  'File uploads',
  'Search',
  'Audit log',
];

/// Curated seeds — common frameworks (free entry still allowed).
const List<String> kFrameworks = [
  'Flutter',
  'ASP.NET Core',
  'Entity Framework Core',
  'Drogon',
  'Spring Boot',
  'Actix',
  'Axum',
  'gRPC',
  'Drift',
  'Riverpod',
];
