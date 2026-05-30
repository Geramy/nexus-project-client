// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Mode;
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dockerfile.dart';

import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';

/// Shared syntax-highlighting plumbing for the workspace editors and the
/// commit diff view. Maps file extensions to `highlight` language ids/modes
/// and exposes light/dark themes. Languages are registered lazily once.

const Map<String, String> _extToLang = {
  'dart': 'dart',
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'md': 'markdown',
  'markdown': 'markdown',
  'py': 'python',
  'js': 'javascript',
  'mjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'html': 'xml',
  'htm': 'xml',
  'xml': 'xml',
  'svg': 'xml',
  'sql': 'sql',
  'css': 'css',
  'scss': 'css',
  'dockerfile': 'dockerfile',
};

final Map<String, Mode> _langModes = {
  'dart': dart,
  'json': json,
  'yaml': yaml,
  'markdown': markdown,
  'python': python,
  'javascript': javascript,
  'typescript': typescript,
  'bash': bash,
  'xml': xml,
  'sql': sql,
  'css': css,
  'dockerfile': dockerfile,
};

bool _registered = false;

/// Register the languages we support with the global `highlight` instance so
/// `HighlightView` (which uses that instance) can parse them.
void ensureHighlightLanguages() {
  if (_registered) return;
  _registered = true;
  _langModes.forEach(highlight.registerLanguage);
}

/// `highlight` language id for a path (e.g. `dart`, `json`), or null when we
/// have no highlighter for it (render as plain text).
String? languageIdForPath(String path) {
  final base = path.split('/').last.toLowerCase();
  if (base == 'dockerfile') return 'dockerfile';
  final dot = base.lastIndexOf('.');
  if (dot < 0) return null;
  return _extToLang[base.substring(dot + 1)];
}

/// The `highlight` [Mode] for a path, for `flutter_code_editor`'s controller.
Mode? languageModeForPath(String path) {
  final id = languageIdForPath(path);
  return id == null ? null : _langModes[id];
}

/// Theme map matched to the app brightness.
Map<String, TextStyle> highlightThemeFor(Brightness brightness) =>
    brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme;

/// Background behind highlighted code, matched to the chosen theme.
Color highlightBackground(Brightness brightness) =>
    brightness == Brightness.dark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
