// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// Doc comments deliberately reference TwiML verbs like <Say>/<Dial> in prose;
// they are not HTML, so silence the doc-comment angle-bracket lint file-wide.
// ignore_for_file: unintended_html_in_doc_comment

import '../model/call_system_project.dart';
import '../model/call_flow.dart';
import '../model/call_node.dart';
import '../model/pbx_entities.dart';
import 'call_system_exporter.dart';

/// Exports the portable [CallSystemProject] to Twilio TwiML (the Twilio Markup
/// Language).
///
/// IMPEDANCE MISMATCH — and how we absorb it:
///   Our model is an imperative, cyclic *graph*: every node has named output
///   ports that point at the next node id, so flow can branch, merge and loop.
///   TwiML, by contrast, is a flat, mostly-linear *document* fetched per HTTP
///   request — control returns to your server after each verb (or after a
///   <Gather>/<Redirect>), and "branching" is expressed by the application
///   choosing which next document to serve. TwiML itself has no `if`, no labels,
///   no goto.
///
///   We bridge that by:
///     • Emitting ONE TwiML document per flow, walking from [CallFlow.entryNode]
///       and following the single "natural continuation" port (`next`,
///       `answered`, `done`, etc.) to inline a linear spine.
///     • Representing every *other* branch (menu digits, no-answer, timeout,
///       schedule open/closed, condition true/false, ...) as an XML comment that
///       names the target node's label, plus — for <Gather> menus — an `action`
///       URL the host application would point at the per-digit document. This
///       keeps the document well-formed and honest about what the runtime must
///       wire up, instead of pretending TwiML can self-branch.
///     • Surfacing every such caveat in [notes].
///
/// The result is realistic, deploy-able TwiML for the linear path of each flow,
/// annotated everywhere a real Twilio app must take over routing.
class TwimlExporter implements CallSystemExporter {
  const TwimlExporter();

  @override
  String get providerKey => 'twilio';

  @override
  String get displayName => 'Twilio (TwiML)';

  @override
  String get artifactExtension => 'xml';

  @override
  Map<String, String> export(CallSystemProject project) {
    final files = <String, String>{};
    final usedNames = <String>{};

    for (final flow in project.flows) {
      // One TwiML document per flow. De-dupe filenames defensively since flow
      // names are user-supplied and need not be unique.
      var base = _slug(flow.name.isEmpty ? flow.id : flow.name);
      var name = base;
      var i = 2;
      while (usedNames.contains(name)) {
        name = '$base-$i';
        i++;
      }
      usedNames.add(name);
      files['$name.twiml.xml'] = _renderFlow(project, flow);
    }

    // If the project has no flows there is nothing executable to emit; still
    // produce a stub so the export bundle is never empty and the user gets a
    // pointer to what's missing.
    if (files.isEmpty) {
      files['empty.twiml.xml'] =
          '$_xmlDecl<Response>\n'
          '  <!-- This project has no call flows to export. Add a flow with an '
          'entry node, then re-export. -->\n'
          '  <Say>This call system has not been configured yet.</Say>\n'
          '  <Hangup/>\n'
          '</Response>\n';
    }
    return files;
  }

  @override
  List<String> notes(CallSystemProject project) {
    final out = <String>[
      'TwiML is request/response and per-document: this export inlines each '
          'flow\'s primary (linear) path and represents every branch — menu '
          'digits, no-answer/busy/timeout, schedule and condition outcomes — as '
          'an XML comment naming the target. Your Twilio application must serve '
          'the matching next document for those branches (typically via the '
          '<Gather>/<Dial> "action" URL).',
      'Point each inbound number\'s Voice webhook at the document for its flow. '
          'Twilio fetches it on each call leg.',
    ];

    // Surface model features that have no clean TwiML primitive, but only when
    // the project actually uses them — keep the caveat list relevant.
    final usedTypes = <CallNodeType>{};
    for (final f in project.flows) {
      for (final n in f.nodes) {
        usedTypes.add(n.type);
      }
    }

    if (usedTypes.contains(CallNodeType.aiVoicebot)) {
      out.add(
        'aiVoicebot nodes require Twilio Media Streams: emit '
        '<Connect><ConversationRelay url="wss://.../omni"/></Connect> (or a '
        '<Stream>) to bridge the call audio to the Omni voicebot. The export '
        'stubs the <Connect> with a placeholder WebSocket URL you must fill '
        'in and host.',
      );
    }
    if (usedTypes.contains(CallNodeType.ringGroup) ||
        usedTypes.contains(CallNodeType.queue)) {
      out.add(
        'Ring groups and ACD queues are PBX concepts. Twilio has no '
        'native FreePBX-style ring group; this export approximates them by '
        'dialing the member extensions (ring groups) or using <Enqueue> '
        '(queues), which needs a TaskRouter / queue webhook to fully realize '
        'strategy and music-on-hold.',
      );
    }
    if (usedTypes.contains(CallNodeType.schedule)) {
      out.add(
        'schedule (business-hours) nodes are evaluated by your '
        'application before/while serving TwiML — TwiML cannot test the clock '
        'itself. The open/closed/holiday branches are emitted as comments.',
      );
    }
    if (usedTypes.contains(CallNodeType.condition) ||
        usedTypes.contains(CallNodeType.setVariable) ||
        usedTypes.contains(CallNodeType.httpRequest)) {
      out.add(
        'condition / setVariable / httpRequest are control-logic nodes '
        'with no TwiML verb; they are emitted as comments and must run in '
        'your application code (TwiML has no variables or branching).',
      );
    }
    if (usedTypes.contains(CallNodeType.playDirectory)) {
      out.add(
        'playDirectory (dial-by-name) has no TwiML verb; emitted as a '
        'comment for the application to implement.',
      );
    }
    if (usedTypes.contains(CallNodeType.subFlow)) {
      out.add(
        'subFlow nodes map to a <Redirect> at the sub-flow\'s document; '
        'TwiML has no call/return, so control does not come back unless the '
        'sub-flow redirects here.',
      );
    }
    return out;
  }

  // ── Flow rendering ──────────────────────────────────────────────────

  static const String _xmlDecl = '<?xml version="1.0" encoding="UTF-8"?>\n';

  /// Walk the flow from its entry node, following the "natural continuation"
  /// port to build a linear spine, and emit a comment for every other branch.
  String _renderFlow(CallSystemProject project, CallFlow flow) {
    final b = StringBuffer();
    b.write(_xmlDecl);
    b.writeln('<!-- Flow: ${_xmlEsc(flow.name)} (id ${_xmlEsc(flow.id)}) -->');
    if (flow.description != null && flow.description!.isNotEmpty) {
      b.writeln('<!-- ${_xmlEsc(flow.description!)} -->');
    }
    b.writeln('<Response>');

    final entry = flow.entryNode;
    if (entry == null) {
      b.writeln(
        '  <!-- No entry node found (entryNodeId='
        '${_xmlEsc(flow.entryNodeId)}). -->',
      );
      b.writeln('  <Say>This flow is not configured.</Say>');
      b.writeln('  <Hangup/>');
      b.writeln('</Response>');
      return b.toString();
    }

    // Guard against cycles: a flow graph may loop, but a TwiML document is
    // finite. Stop inlining when we revisit a node and leave a <Redirect>-style
    // comment instead.
    final visited = <String>{};
    CallNode? current = entry;
    while (current != null) {
      if (visited.contains(current.id)) {
        b.writeln(
          '  <!-- Loops back to ${_label(current)}; serve that '
          'document again (TwiML has no in-document goto). -->',
        );
        break;
      }
      visited.add(current.id);

      final next = _renderNode(project, flow, current, b);
      if (next == null) break; // terminal node (hangup / unconnected)
      current = flow.nodeById(next);
    }

    b.writeln('</Response>');
    return b.toString();
  }

  /// Emit the TwiML for a single node and return the id of the next node along
  /// the natural linear path (or null to stop). All non-linear ports are
  /// annotated as comments inside the node's output.
  String? _renderNode(
    CallSystemProject project,
    CallFlow flow,
    CallNode node,
    StringBuffer b,
  ) {
    switch (node.type) {
      case CallNodeType.entry:
        // Pure marker — no TwiML verb. Continue down `next`.
        b.writeln('  <!-- entry: ${_label(node)} -->');
        return node.outputs['next'];

      case CallNodeType.playPrompt:
        _writePrompt(project, node, b, indent: '  ');
        return node.outputs['next'];

      case CallNodeType.menu:
        return _renderMenu(project, flow, node, b);

      case CallNodeType.gatherDigits:
        return _renderGatherDigits(project, flow, node, b);

      case CallNodeType.gatherSpeech:
        return _renderGatherSpeech(project, flow, node, b);

      case CallNodeType.aiVoicebot:
        return _renderVoicebot(node, b);

      case CallNodeType.dial:
        return _renderDial(flow, node, b);

      case CallNodeType.transferToExtension:
        return _renderTransfer(project, flow, node, b);

      case CallNodeType.ringGroup:
        return _renderRingGroup(project, flow, node, b);

      case CallNodeType.queue:
        return _renderQueue(project, flow, node, b);

      case CallNodeType.voicemail:
        return _renderVoicemail(project, node, b);

      case CallNodeType.schedule:
        // TwiML can't read the clock; the app decides which branch's document
        // to serve. Comment all three outcomes and fall through `open`.
        b.writeln(
          '  <!-- schedule: ${_label(node)} — evaluate business hours '
          'in your application. -->',
        );
        _comment(b, node, 'open', flow, 'open hours');
        _comment(b, node, 'closed', flow, 'after hours');
        _comment(b, node, 'holiday', flow, 'holiday');
        return node.outputs['open'];

      case CallNodeType.condition:
        b.writeln(
          '  <!-- condition: ${_label(node)} — no TwiML primitive; '
          'evaluate in application code. -->',
        );
        _comment(b, node, 'true', flow, 'true');
        _comment(b, node, 'false', flow, 'false');
        return node.outputs['true'];

      case CallNodeType.setVariable:
        final v = node.config['variable'];
        b.writeln(
          '  <!-- setVariable: ${_label(node)}'
          '${v != null ? ' (${_xmlEsc('$v')})' : ''} — store in application '
          'state; TwiML has no variables. -->',
        );
        return node.outputs['next'];

      case CallNodeType.httpRequest:
        b.writeln(
          '  <!-- httpRequest: ${_label(node)} — perform in your '
          'application; TwiML cannot call arbitrary APIs inline. -->',
        );
        _comment(b, node, 'success', flow, 'success');
        _comment(b, node, 'failure', flow, 'failure');
        return node.outputs['success'];

      case CallNodeType.record:
        // A standalone recording leg. <Record> posts the recording to `action`
        // and continues there; we comment the continuation.
        final next = node.outputs['next'];
        b.writeln(
          '  <Record'
          '${next != null ? ' action="${_actionUrl(flow, next)}"' : ''}'
          ' playBeep="true" maxLength="3600"/>',
        );
        b.writeln(
          '  <!-- record: ${_label(node)} — continues at '
          '${_targetLabel(flow, next)} via the Record action URL. -->',
        );
        return null; // continuation handled by the action URL document

      case CallNodeType.playDirectory:
        b.writeln(
          '  <!-- playDirectory: ${_label(node)} — dial-by-name has no '
          'TwiML verb; implement in your application. -->',
        );
        _comment(b, node, 'matched', flow, 'matched');
        _comment(b, node, 'nomatch', flow, 'no match');
        return node.outputs['matched'];

      case CallNodeType.hangup:
        b.writeln('  <Hangup/>');
        return null;

      case CallNodeType.subFlow:
        final targetFlowId = node.config['flowId'] ?? node.config['target'];
        final target = targetFlowId is String
            ? project.flowById(targetFlowId)
            : null;
        final url = target != null
            ? '${_slug(target.name.isEmpty ? target.id : target.name)}.twiml.xml'
            : 'sub-flow.twiml.xml';
        b.writeln(
          '  <!-- subFlow: ${_label(node)} — jump to another flow\'s '
          'document. TwiML has no return. -->',
        );
        b.writeln('  <Redirect>${_xmlEsc(url)}</Redirect>');
        return null; // <Redirect> ends this document
    }
  }

  // ── Per-type renderers ──────────────────────────────────────────────

  /// playPrompt / greeting: <Play> a recorded asset when present, else <Say>
  /// the TTS text. (Twilio also TTS's plain <Say>.)
  void _writePrompt(
    CallSystemProject project,
    CallNode node,
    StringBuffer b, {
    required String indent,
  }) {
    final promptId = node.config['promptId'];
    final prompt = promptId is String ? project.promptById(promptId) : null;
    if (prompt == null) {
      b.writeln(
        '$indent<!-- ${_label(node)}: prompt '
        '${promptId == null ? 'unset' : _xmlEsc('$promptId')} not found. -->',
      );
      b.writeln('$indent<Say>(missing prompt)</Say>');
      return;
    }
    final asset = prompt.audioAssetPath;
    if (asset != null && asset.isNotEmpty) {
      // Recorded audio: <Play> the asset (host it and use an absolute URL in
      // production; the bundle-relative path is emitted as-is).
      b.writeln('$indent<Play>${_xmlEsc(asset)}</Play>');
    } else {
      // TTS prompt. We don't pin a Twilio <Say voice="..."> from our kokoro
      // voice id since they're different voice catalogs — leave Twilio's
      // default and note the source voice.
      if (prompt.voice != null && prompt.voice!.isNotEmpty) {
        b.writeln(
          '$indent<!-- authored with kokoro voice '
          '${_xmlEsc(prompt.voice!)}; map to a Twilio <Say> voice if desired '
          '-->',
        );
      }
      b.writeln('$indent<Say>${_xmlEsc(prompt.text)}</Say>');
    }
  }

  /// menu → <Gather input="dtmf" numDigits="1"> with the prompt nested inside,
  /// so a key press during playback barges in. Each configured digit port, plus
  /// `timeout`/`invalid`, becomes a comment naming the target — the application
  /// reads the pressed Digits and serves the matching document via `action`.
  String? _renderMenu(
    CallSystemProject project,
    CallFlow flow,
    CallNode node,
    StringBuffer b,
  ) {
    final numDigits = node.config['numDigits'] ?? node.config['digits'] ?? 1;
    final timeoutNode = node.outputs['timeout'];
    b.writeln(
      '  <!-- menu: ${_label(node)} — DTMF branch handled by your app '
      'reading the gathered Digits at the action URL. -->',
    );
    b.writeln(
      '  <Gather input="dtmf" numDigits="${_xmlEsc('$numDigits')}" '
      'timeout="5" action="${_actionUrl(flow, node.id)}">',
    );
    // Nested prompt = the menu greeting ("Press 1 for sales...").
    _writePrompt(project, node, b, indent: '    ');
    b.writeln('  </Gather>');

    // Digit branches: every output port that isn't a base port (timeout/invalid)
    // is a per-key destination.
    final base = {'timeout', 'invalid'};
    final digitKeys = node.outputs.keys.where((k) => !base.contains(k)).toList()
      ..sort();
    for (final key in digitKeys) {
      _comment(b, node, key, flow, 'digit "$key"');
    }
    _comment(b, node, 'invalid', flow, 'invalid entry');

    // No digit pressed → <Gather> falls through here in the document. Continue
    // the linear spine down the `timeout` port if set.
    if (timeoutNode != null) {
      b.writeln(
        '  <!-- No input: continues to ${_targetLabel(flow, timeoutNode)} '
        '(timeout). -->',
      );
    } else {
      b.writeln(
        '  <!-- No input and no timeout target: re-prompt or hang up in '
        'your app. -->',
      );
    }
    return timeoutNode;
  }

  /// gatherDigits → <Gather input="dtmf"> capturing into a variable (read by the
  /// app from the posted Digits). Linear spine follows `next`.
  String? _renderGatherDigits(
    CallSystemProject project,
    CallFlow flow,
    CallNode node,
    StringBuffer b,
  ) {
    final variable = node.config['variable'];
    final next = node.outputs['next'];
    final numDigits = node.config['numDigits'] ?? node.config['digits'];
    if (variable != null) {
      b.writeln(
        '  <!-- gatherDigits → variable '
        '${_xmlEsc('$variable')} (read posted Digits at the action URL). -->',
      );
    }
    final numAttr = numDigits != null
        ? ' numDigits="${_xmlEsc('$numDigits')}"'
        : '';
    b.writeln(
      '  <Gather input="dtmf"$numAttr finishOnKey="#" timeout="6" '
      'action="${_actionUrl(flow, next ?? node.id)}">',
    );
    // A gatherDigits node may reuse a prompt to ask for the input.
    if (node.config['promptId'] != null) {
      _writePrompt(project, node, b, indent: '    ');
    }
    b.writeln('  </Gather>');
    _comment(b, node, 'timeout', flow, 'timeout / no input');
    return next;
  }

  /// gatherSpeech → <Gather input="speech"> (Twilio ASR). Captured transcript is
  /// posted to the action URL; the app routes on it.
  String? _renderGatherSpeech(
    CallSystemProject project,
    CallFlow flow,
    CallNode node,
    StringBuffer b,
  ) {
    final variable = node.config['variable'];
    final next = node.outputs['next'];
    if (variable != null) {
      b.writeln(
        '  <!-- gatherSpeech → variable '
        '${_xmlEsc('$variable')} (read SpeechResult at the action URL). -->',
      );
    }
    b.writeln(
      '  <Gather input="speech" speechTimeout="auto" '
      'action="${_actionUrl(flow, next ?? node.id)}">',
    );
    if (node.config['promptId'] != null) {
      _writePrompt(project, node, b, indent: '    ');
    }
    b.writeln('  </Gather>');
    _comment(b, node, 'timeout', flow, 'timeout');
    _comment(b, node, 'nomatch', flow, 'no match');
    return next;
  }

  /// aiVoicebot → bridge the call to Omni over Twilio Media Streams via
  /// <Connect><ConversationRelay>. The WebSocket URL is a placeholder the user
  /// must host.
  String? _renderVoicebot(CallNode node, StringBuffer b) {
    final goal = node.config['goal'];
    b.writeln(
      '  <!-- aiVoicebot: ${_label(node)} — conversational AI over '
      'Twilio Media Streams.'
      '${goal != null ? ' Goal: ${_xmlEsc('$goal')}.' : ''} Bridges audio to '
      'the Omni voicebot; fill in your hosted WebSocket URL. -->',
    );
    b.writeln('  <Connect>');
    b.writeln(
      '    <ConversationRelay url="wss://example.invalid/omni" '
      'welcomeGreeting=""/>',
    );
    b.writeln('  </Connect>');
    // <Connect> takes over the call; the `transfer`/`hangup`/`next` ports are
    // driven by the voicebot session, not by this document.
    final transfer = node.outputs['transfer'];
    if (transfer != null) {
      b.writeln(
        '  <!-- On voicebot transfer: route to the document for the '
        'transfer target in your relay handler. -->',
      );
    }
    return null; // <Connect> is terminal for this document
  }

  /// dial → <Dial><Number> the external PSTN/SIP number. `action` posts the
  /// dial result so the app can branch answered/busy/no-answer/failed.
  String? _renderDial(CallFlow flow, CallNode node, StringBuffer b) {
    final number = node.config['number'];
    b.writeln('  <!-- dial: ${_label(node)} -->');
    b.writeln('  <Dial action="${_actionUrl(flow, node.id)}" timeout="30">');
    if (number != null) {
      b.writeln('    <Number>${_xmlEsc('$number')}</Number>');
    } else {
      b.writeln('    <!-- No number configured. -->');
    }
    b.writeln('  </Dial>');
    // Dial result branches: the app inspects DialCallStatus at the action URL.
    _comment(b, node, 'answered', flow, 'answered');
    _comment(b, node, 'noanswer', flow, 'no answer');
    _comment(b, node, 'busy', flow, 'busy');
    _comment(b, node, 'failed', flow, 'failed');
    return node.outputs['answered'];
  }

  /// transferToExtension → <Dial><Sip> when the extension has SIP creds,
  /// otherwise <Dial><Number> the internal number.
  String? _renderTransfer(
    CallSystemProject project,
    CallFlow flow,
    CallNode node,
    StringBuffer b,
  ) {
    final extId = node.config['extension'];
    Extension? ext;
    for (final e in project.extensions) {
      if (e.id == extId || e.number == '$extId') {
        ext = e;
        break;
      }
    }
    b.writeln(
      '  <!-- transferToExtension: ${_label(node)}'
      '${ext != null ? ' → ${_xmlEsc(ext.name)} (${_xmlEsc(ext.number)})' : ''}'
      ' -->',
    );
    b.writeln(
      '  <Dial action="${_actionUrl(flow, node.id)}" '
      'timeout="${ext?.ringSeconds ?? 20}">',
    );
    if (ext != null && ext.sipUsername != null && ext.sipUsername!.isNotEmpty) {
      // SIP endpoint registered for this extension.
      b.writeln(
        '    <Sip>${_xmlEsc(ext.sipUsername!)}@your-sip-domain.example</Sip>',
      );
    } else if (ext != null) {
      b.writeln('    <Number>${_xmlEsc(ext.number)}</Number>');
    } else {
      b.writeln(
        '    <!-- Extension ${extId == null ? 'unset' : _xmlEsc('$extId')} '
        'not found. -->',
      );
    }
    b.writeln('  </Dial>');
    _comment(b, node, 'answered', flow, 'answered');
    _comment(b, node, 'noanswer', flow, 'no answer');
    _comment(b, node, 'busy', flow, 'busy');
    return node.outputs['answered'];
  }

  /// ringGroup → approximate with a <Dial> of every member extension. Twilio has
  /// no native ring-group strategy; ringAll maps to parallel <Number>s, the
  /// sequential strategies need an action-URL loop in the app.
  String? _renderRingGroup(
    CallSystemProject project,
    CallFlow flow,
    CallNode node,
    StringBuffer b,
  ) {
    final groupId = node.config['ringGroupId'] ?? node.config['target'];
    RingGroup? group;
    for (final g in project.ringGroups) {
      if (g.id == groupId || g.number == '$groupId') {
        group = g;
        break;
      }
    }
    b.writeln(
      '  <!-- ringGroup: ${_label(node)}'
      '${group != null ? ' (${_xmlEsc(group.name)}, strategy '
                '${_xmlEsc(group.strategy.name)})' : ''} — '
      'Twilio has no native ring group; dialing members. -->',
    );
    b.writeln(
      '  <Dial action="${_actionUrl(flow, node.id)}" '
      'timeout="${group?.ringSeconds ?? 20}">',
    );
    if (group != null && group.extensionIds.isNotEmpty) {
      // ringAll: all <Number>s ring in parallel. hunt/roundRobin/etc. would
      // require the app to dial members in sequence across action callbacks.
      if (group.strategy != RingStrategy.ringAll) {
        b.writeln(
          '    <!-- strategy ${_xmlEsc(group.strategy.name)} is '
          'sequential; emit one member per leg from your app. Listing all '
          'for reference. -->',
        );
      }
      for (final eid in group.extensionIds) {
        final ext = _extById(project, eid);
        if (ext != null) {
          b.writeln('    <Number>${_xmlEsc(ext.number)}</Number>');
        }
      }
    } else {
      b.writeln('    <!-- Ring group has no members. -->');
    }
    b.writeln('  </Dial>');
    _comment(b, node, 'answered', flow, 'answered');
    _comment(b, node, 'noanswer', flow, 'no answer');
    return node.outputs['answered'];
  }

  /// queue → <Enqueue> the caller; agents are connected via a separate
  /// <Dial><Queue> document / TaskRouter. Music-on-hold maps to <Enqueue
  /// waitUrl>.
  String? _renderQueue(
    CallSystemProject project,
    CallFlow flow,
    CallNode node,
    StringBuffer b,
  ) {
    final queueId = node.config['queueId'] ?? node.config['target'];
    CallQueue? q;
    for (final cq in project.queues) {
      if (cq.id == queueId || cq.number == '$queueId') {
        q = cq;
        break;
      }
    }
    final queueName = q?.name ?? 'support';
    b.writeln(
      '  <!-- queue: ${_label(node)} — ACD queue. Agents are rung by a '
      'separate <Dial><Queue> document; strategy '
      '(${_xmlEsc(q?.strategy.name ?? 'fewestRecent')}) is realized in '
      'TaskRouter, not TwiML. -->',
    );
    // Music-on-hold prompt, if any, becomes the wait experience the app hosts.
    if (q?.musicOnHoldPromptId != null) {
      final moh = project.promptById(q!.musicOnHoldPromptId!);
      if (moh != null) {
        b.writeln(
          '  <!-- Music on hold: '
          '${_xmlEsc(moh.audioAssetPath ?? moh.text)} (serve via the Enqueue '
          'waitUrl). -->',
        );
      }
    }
    b.writeln('  <Enqueue>${_xmlEsc(queueName)}</Enqueue>');
    // <Enqueue> blocks until the caller is dequeued; the result ports are driven
    // by the queue/TaskRouter, so the document ends here.
    _comment(b, node, 'answered', flow, 'agent answered');
    _comment(b, node, 'timeout', flow, 'wait timeout');
    _comment(b, node, 'empty', flow, 'queue empty');
    return null;
  }

  /// voicemail → play the box greeting, then <Record> the caller's message and
  /// post it (optionally email it) at the box's configured destination.
  String? _renderVoicemail(
    CallSystemProject project,
    CallNode node,
    StringBuffer b,
  ) {
    final boxId = node.config['voicemailBoxId'] ?? node.config['target'];
    VoicemailBox? box;
    for (final vb in project.voicemailBoxes) {
      if (vb.id == boxId || vb.mailboxNumber == '$boxId') {
        box = vb;
        break;
      }
    }
    b.writeln(
      '  <!-- voicemail: ${_label(node)}'
      '${box != null ? ' → ${_xmlEsc(box.name)}' : ''} -->',
    );
    // Greeting first.
    final greetingId = box?.greetingPromptId;
    final greeting = greetingId != null ? project.promptById(greetingId) : null;
    if (greeting != null) {
      if (greeting.audioAssetPath != null &&
          greeting.audioAssetPath!.isNotEmpty) {
        b.writeln('  <Play>${_xmlEsc(greeting.audioAssetPath!)}</Play>');
      } else {
        b.writeln('  <Say>${_xmlEsc(greeting.text)}</Say>');
      }
    } else {
      b.writeln('  <Say>Please leave a message after the tone.</Say>');
    }
    if (box?.emailTo != null && box!.emailTo!.isNotEmpty) {
      b.writeln(
        '  <!-- Email the recording to ${_xmlEsc(box.emailTo!)} from '
        'your recording-status webhook. -->',
      );
    }
    b.writeln(
      '  <Record maxLength="180" playBeep="true" '
      'transcribe="false"/>',
    );
    b.writeln('  <Hangup/>');
    return null; // voicemail terminates the call leg
  }

  // ── Branch comment + helpers ────────────────────────────────────────

  /// Emit a comment describing a non-linear output port and the node it targets
  /// (by label), so the document stays honest about routing the app must do.
  void _comment(
    StringBuffer b,
    CallNode node,
    String port,
    CallFlow flow,
    String human,
  ) {
    if (!node.outputs.containsKey(port)) return;
    final target = node.outputs[port];
    if (target == null) {
      b.writeln('    <!-- on $human ($port): unconnected. -->');
    } else {
      b.writeln(
        '    <!-- on $human ($port): go to '
        '${_targetLabel(flow, target)} — serve ${_actionUrl(flow, target)}. -->',
      );
    }
  }

  Extension? _extById(CallSystemProject project, String id) {
    for (final e in project.extensions) {
      if (e.id == id) return e;
    }
    return null;
  }

  String _label(CallNode node) =>
      _xmlEsc(node.label.isEmpty ? node.id : node.label);

  String _targetLabel(CallFlow flow, String? nodeId) {
    if (nodeId == null) return '(unconnected)';
    final n = flow.nodeById(nodeId);
    return n == null
        ? _xmlEsc(nodeId)
        : _xmlEsc(n.label.isEmpty ? n.id : n.label);
  }

  /// The conventional next-document URL a Twilio app would serve for [nodeId].
  /// Relative + deterministic so the comments are actionable.
  String _actionUrl(CallFlow flow, String nodeId) =>
      '${_slug(flow.name.isEmpty ? flow.id : flow.name)}-node-${_slug(nodeId)}.twiml.xml';

  // ── Text utilities ──────────────────────────────────────────────────

  /// Escape the five XML predefined entities for safe element/attribute text.
  String _xmlEsc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Filesystem-safe lowercase slug for filenames/URLs.
  String _slug(String s) {
    final lower = s.toLowerCase().trim();
    final buf = StringBuffer();
    var lastDash = false;
    for (final cu in lower.codeUnits) {
      final c = String.fromCharCode(cu);
      final isWord =
          (cu >= 0x30 && cu <= 0x39) || (cu >= 0x61 && cu <= 0x7a); // 0-9 a-z
      if (isWord) {
        buf.write(c);
        lastDash = false;
      } else if (!lastDash) {
        buf.write('-');
        lastDash = true;
      }
    }
    var out = buf.toString();
    while (out.startsWith('-')) {
      out = out.substring(1);
    }
    while (out.endsWith('-')) {
      out = out.substring(0, out.length - 1);
    }
    return out.isEmpty ? 'flow' : out;
  }
}
