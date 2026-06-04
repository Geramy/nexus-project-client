// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Multi-select state for the Agents › Personas list. Lifted out of the tab so
/// the MainShell right outer panel can host the bulk editor while select mode
/// is active (mirrors how Setup mode drives the right panel).
class PersonaBulkSelection {
  const PersonaBulkSelection({this.active = false, this.ids = const {}});

  final bool active;
  final Set<int> ids;

  bool get isEmpty => ids.isEmpty;
  int get count => ids.length;

  PersonaBulkSelection copyWith({bool? active, Set<int>? ids}) =>
      PersonaBulkSelection(active: active ?? this.active, ids: ids ?? this.ids);
}

class PersonaBulkSelectionNotifier extends StateNotifier<PersonaBulkSelection> {
  PersonaBulkSelectionNotifier() : super(const PersonaBulkSelection());

  void enter() => state = const PersonaBulkSelection(active: true, ids: {});

  void exit() => state = const PersonaBulkSelection();

  void toggle(int id) {
    final next = {...state.ids};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(ids: next);
  }

  /// Select [all] if not everything is already selected, otherwise clear.
  void toggleAll(Set<int> all) {
    state = state.copyWith(
      ids: state.ids.length == all.length ? <int>{} : {...all},
    );
  }
}

final personaBulkSelectionProvider =
    StateNotifierProvider<PersonaBulkSelectionNotifier, PersonaBulkSelection>(
      (ref) => PersonaBulkSelectionNotifier(),
    );
