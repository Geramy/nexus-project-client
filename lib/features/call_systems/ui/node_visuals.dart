// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../model/call_node.dart';

/// Fixed node-card geometry so the canvas and the edge painter agree on anchors.
const double kNodeWidth = 176;
const double kNodeHeight = 68;

IconData iconForNodeType(CallNodeType t) => switch (t) {
      CallNodeType.entry => Icons.play_circle_outline,
      CallNodeType.playPrompt => Icons.campaign_outlined,
      CallNodeType.menu => Icons.dialpad,
      CallNodeType.gatherDigits => Icons.pin_outlined,
      CallNodeType.gatherSpeech => Icons.mic_none,
      CallNodeType.aiVoicebot => Icons.smart_toy_outlined,
      CallNodeType.dial => Icons.call_outlined,
      CallNodeType.transferToExtension => Icons.phone_forwarded_outlined,
      CallNodeType.ringGroup => Icons.groups_outlined,
      CallNodeType.queue => Icons.people_alt_outlined,
      CallNodeType.voicemail => Icons.voicemail_outlined,
      CallNodeType.schedule => Icons.schedule_outlined,
      CallNodeType.condition => Icons.call_split,
      CallNodeType.setVariable => Icons.data_object,
      CallNodeType.httpRequest => Icons.http,
      CallNodeType.record => Icons.fiber_manual_record_outlined,
      CallNodeType.playDirectory => Icons.contacts_outlined,
      CallNodeType.hangup => Icons.call_end_outlined,
      CallNodeType.subFlow => Icons.account_tree_outlined,
    };

/// Group color for a node type (greens = start, blue = speak, teal = input,
/// purple = routing, amber = logic, red = terminal, brand = AI).
Color colorForNodeType(CallNodeType t, ColorScheme scheme) => switch (t) {
      CallNodeType.entry => const Color(0xFF2E9E5B),
      CallNodeType.playPrompt ||
      CallNodeType.playDirectory =>
        const Color(0xFF2F6FED),
      CallNodeType.menu ||
      CallNodeType.gatherDigits ||
      CallNodeType.gatherSpeech ||
      CallNodeType.record =>
        const Color(0xFF1AA0A0),
      CallNodeType.aiVoicebot => scheme.primary,
      CallNodeType.dial ||
      CallNodeType.transferToExtension ||
      CallNodeType.ringGroup ||
      CallNodeType.queue ||
      CallNodeType.voicemail ||
      CallNodeType.subFlow =>
        const Color(0xFF7A5AF8),
      CallNodeType.schedule ||
      CallNodeType.condition ||
      CallNodeType.setVariable ||
      CallNodeType.httpRequest =>
        const Color(0xFFD9920B),
      CallNodeType.hangup => const Color(0xFFD64545),
    };

/// Human label for a node type (used in the palette + inspector).
String titleForNodeType(CallNodeType t) => switch (t) {
      CallNodeType.entry => 'Call starts',
      CallNodeType.playPrompt => 'Play message',
      CallNodeType.menu => 'Menu (press a key)',
      CallNodeType.gatherDigits => 'Get digits',
      CallNodeType.gatherSpeech => 'Get speech',
      CallNodeType.aiVoicebot => 'AI voicebot',
      CallNodeType.dial => 'Dial a number',
      CallNodeType.transferToExtension => 'Transfer to extension',
      CallNodeType.ringGroup => 'Ring group',
      CallNodeType.queue => 'Queue',
      CallNodeType.voicemail => 'Voicemail',
      CallNodeType.schedule => 'Business hours',
      CallNodeType.condition => 'Condition',
      CallNodeType.setVariable => 'Set variable',
      CallNodeType.httpRequest => 'API request',
      CallNodeType.record => 'Record',
      CallNodeType.playDirectory => 'Dial by name',
      CallNodeType.hangup => 'End call',
      CallNodeType.subFlow => 'Go to sub-flow',
    };

/// The node types offered in the palette, grouped for Regular vs Advanced.
const List<CallNodeType> kRegularPaletteNodes = [
  CallNodeType.playPrompt,
  CallNodeType.menu,
  CallNodeType.gatherDigits,
  CallNodeType.gatherSpeech,
  CallNodeType.aiVoicebot,
  CallNodeType.transferToExtension,
  CallNodeType.dial,
  CallNodeType.ringGroup,
  CallNodeType.queue,
  CallNodeType.voicemail,
  CallNodeType.schedule,
  CallNodeType.hangup,
];

const List<CallNodeType> kAdvancedPaletteNodes = [
  CallNodeType.condition,
  CallNodeType.setVariable,
  CallNodeType.httpRequest,
  CallNodeType.record,
  CallNodeType.playDirectory,
  CallNodeType.subFlow,
];
