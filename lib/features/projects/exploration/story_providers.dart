// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Providers for the post-setup Project Exploration phase: the live user-story
/// tree (rendered as a UML-style canvas) and the selected node.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../infrastructure/database/nexus_database.dart';

/// Live user-story tree for a project (rebuilds as the Coordinator adds stories
/// during discovery). Backed by `UserStories` so edits persist.
final projectStoriesProvider = StreamProvider.family<List<UserStory>, int>((
  ref,
  projectId,
) {
  return ref.watch(nexusDatabaseProvider).watchUserStoriesForProject(projectId);
});

/// The currently-selected story node (its `story_pk`), per project. Drives the
/// canvas inspector.
final selectedStoryProvider = StateProvider.family<int?, int>((ref, _) => null);

/// Live descriptive notes attached to a story (shown as pills in the inspector).
final storyNotesProvider = StreamProvider.family<List<StoryNote>, int>((
  ref,
  storyPk,
) {
  return ref.watch(nexusDatabaseProvider).watchNotesForStory(storyPk);
});
