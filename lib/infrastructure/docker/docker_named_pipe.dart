// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Windows named-pipe transport for the Docker Engine API.
///
/// `dart:io` cannot open a Windows named pipe (`\\.\pipe\docker_engine`), so we
/// bridge it in-process: a loopback TCP listener accepts the [HttpClient]'s
/// connections and pumps each one byte-for-byte to/from the pipe via Win32
/// `CreateFileW`/`ReadFile`/`WriteFile` (FFI). `HttpClient` still performs all
/// HTTP framing (chunked responses, keep-alive) over the loopback socket — this
/// layer only moves raw bytes, so streaming endpoints (`/build`, logs) work too.
///
/// One pipe instance is full-duplex but `ReadFile`/`WriteFile` are blocking, so
/// each connection uses two short-lived isolates (reader + writer) that share
/// the pipe HANDLE; the main isolate never blocks.
///
/// NOTE: This file is Windows-only and is compiled but UNTESTED on non-Windows
/// development machines. It needs a Windows smoke test (`version()` /
/// `listImages()` and a `/build`) before being relied on.
class WindowsDockerPipe {
  WindowsDockerPipe._(this.pipePath);

  /// The pipe path in Win32 form, e.g. `\\.\pipe\docker_engine`.
  final String pipePath;

  static final Map<String, WindowsDockerPipe> _instances = {};

  /// One pump per distinct pipe path (HttpClient opens many connections).
  factory WindowsDockerPipe.forPath(String pipePath) =>
      _instances.putIfAbsent(pipePath, () => WindowsDockerPipe._(pipePath));

  Future<int>? _portFuture;

  /// The loopback TCP port the pump is listening on, started lazily on first use.
  Future<int> get port => _portFuture ??= _startPump();

  Future<int> _startPump() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handleConnection, onError: (_) {});
    return server.port;
  }

  Future<void> _handleConnection(Socket socket) async {
    final handle = _openPipe(pipePath);
    if (handle == _invalidHandle) {
      socket.destroy();
      return;
    }

    // Reader isolate: blocking ReadFile(pipe) -> bytes back to us -> socket.
    final fromPipe = ReceivePort();
    final reader = await Isolate.spawn(
      _readerEntry,
      _PipeArg(handle, fromPipe.sendPort),
      errorsAreFatal: true,
    );

    // Writer isolate: socket bytes -> us -> blocking WriteFile(pipe).
    final writerReady = ReceivePort();
    final writer = await Isolate.spawn(
      _writerEntry,
      _PipeArg(handle, writerReady.sendPort),
      errorsAreFatal: true,
    );

    var closed = false;
    // The reader hands back a control port so we can ask it to STOP gracefully
    // (free its native buffers + exit its poll loop). kill() is the fallback.
    SendPort? readerStop;
    void cleanup() {
      if (closed) return;
      closed = true;
      readerStop?.send(null); // graceful stop (frees native buffers)
      fromPipe.close();
      writerReady.close();
      reader.kill(priority: Isolate.immediate);
      writer.kill(priority: Isolate.immediate);
      _closeHandle(handle);
      socket.destroy();
    }

    // The writer isolate hands back its inbound SendPort; buffer socket data
    // until it's ready, then forward.
    SendPort? toWriter;
    final pending = <Uint8List>[];
    writerReady.listen((msg) {
      if (msg is SendPort) {
        toWriter = msg;
        for (final chunk in pending) {
          toWriter!.send(chunk);
        }
        pending.clear();
      }
    });

    fromPipe.listen((msg) {
      // First message from the reader is its control SendPort.
      if (msg is SendPort) {
        readerStop = msg;
        return;
      }
      if (msg == null) {
        cleanup(); // pipe EOF/closed
        return;
      }
      try {
        socket.add(msg as Uint8List);
      } catch (_) {
        cleanup();
      }
    });

    socket.listen(
      (data) {
        final chunk = Uint8List.fromList(data);
        if (toWriter != null) {
          toWriter!.send(chunk);
        } else {
          pending.add(chunk);
        }
      },
      onDone: cleanup,
      onError: (_) => cleanup(),
      cancelOnError: true,
    );
  }
}

/// Argument bundle for the pump isolates: the pipe HANDLE (as an int) plus a
/// SendPort back to the main isolate.
class _PipeArg {
  const _PipeArg(this.handle, this.sendPort);
  final int handle;
  final SendPort sendPort;
}

const int _bufSize = 64 * 1024;

/// Reader isolate: poll the pipe for available bytes and forward them to the
/// main isolate. Deliberately POLLING (PeekNamedPipe + a periodic timer) rather
/// than a blocking ReadFile loop: a thread parked inside a blocking native
/// syscall can't be reclaimed by Isolate.kill() or by VM/app shutdown (the
/// "waiting for isolate _readerEntry to check in" hang on exit). Staying in the
/// Dart event loop keeps the isolate killable and lets shutdown complete.
void _readerEntry(_PipeArg arg) {
  final control = ReceivePort();
  // Hand the control port back so the main isolate can request a graceful stop.
  arg.sendPort.send(control.sendPort);

  final peek = _lookupPeekNamedPipe();
  final readFile = _lookupReadFile();
  final buf = calloc<Uint8>(_bufSize);
  final read = calloc<Uint32>();
  final avail = calloc<Uint32>();

  var stopped = false;
  Timer? timer;
  void stop({bool sendEof = true}) {
    if (stopped) return;
    stopped = true;
    timer?.cancel();
    if (sendEof) arg.sendPort.send(null); // signal EOF to main
    calloc.free(buf);
    calloc.free(read);
    calloc.free(avail);
    control.close();
  }

  // A message on the control port = "stop now" (the connection is closing); no
  // EOF needed since the main side already knows.
  control.listen((_) => stop(sendEof: false));

  timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    // How many bytes are buffered, WITHOUT blocking.
    final ok = peek(arg.handle, nullptr, 0, nullptr, avail, nullptr);
    if (ok == 0) {
      stop(); // pipe broken / handle closed
      return;
    }
    final n = avail.value;
    if (n == 0) return; // nothing yet — try again next tick
    final toRead = n > _bufSize ? _bufSize : n;
    // Data is already buffered, so this ReadFile returns immediately.
    final rok = readFile(arg.handle, buf, toRead, read, nullptr);
    final got = read.value;
    if (rok == 0 || got == 0) {
      stop();
      return;
    }
    arg.sendPort.send(Uint8List.fromList(buf.asTypedList(got)));
  });
}

void _writerEntry(_PipeArg arg) {
  final writeFile = _lookupWriteFile();
  final inbound = ReceivePort();
  arg.sendPort.send(inbound.sendPort);
  final written = calloc<Uint32>();
  inbound.listen((msg) {
    if (msg == null) {
      inbound.close();
      return;
    }
    final data = msg as Uint8List;
    final buf = calloc<Uint8>(data.length);
    buf.asTypedList(data.length).setAll(0, data);
    try {
      var off = 0;
      while (off < data.length) {
        final slice = Pointer<Uint8>.fromAddress(buf.address + off);
        final ok = writeFile(
          arg.handle,
          slice,
          data.length - off,
          written,
          nullptr,
        );
        if (ok == 0) break;
        final w = written.value;
        if (w == 0) break;
        off += w;
      }
    } finally {
      calloc.free(buf);
    }
  });
}

// ---- Win32 FFI ------------------------------------------------------------

const int _genericRead = 0x80000000;
const int _genericWrite = 0x40000000;
const int _openExisting = 3;
const int _invalidHandle = -1;

typedef _CreateFileWNative =
    IntPtr Function(
      Pointer<Utf16> lpFileName,
      Uint32 dwDesiredAccess,
      Uint32 dwShareMode,
      Pointer<Void> lpSecurityAttributes,
      Uint32 dwCreationDisposition,
      Uint32 dwFlagsAndAttributes,
      IntPtr hTemplateFile,
    );
typedef _CreateFileWDart =
    int Function(
      Pointer<Utf16> lpFileName,
      int dwDesiredAccess,
      int dwShareMode,
      Pointer<Void> lpSecurityAttributes,
      int dwCreationDisposition,
      int dwFlagsAndAttributes,
      int hTemplateFile,
    );

typedef _ReadWriteNative =
    Int32 Function(
      IntPtr hFile,
      Pointer<Uint8> lpBuffer,
      Uint32 nNumberOfBytes,
      Pointer<Uint32> lpNumberOfBytesXfer,
      Pointer<Void> lpOverlapped,
    );
typedef _ReadWriteDart =
    int Function(
      int hFile,
      Pointer<Uint8> lpBuffer,
      int nNumberOfBytes,
      Pointer<Uint32> lpNumberOfBytesXfer,
      Pointer<Void> lpOverlapped,
    );

typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

// BOOL PeekNamedPipe(HANDLE, LPVOID, DWORD, LPDWORD, LPDWORD, LPDWORD) — used to
// query how many bytes are buffered without blocking (we pass null for the
// buffer/read/left-in-message outputs and only read lpTotalBytesAvail).
typedef _PeekNamedPipeNative =
    Int32 Function(
      IntPtr hNamedPipe,
      Pointer<Void> lpBuffer,
      Uint32 nBufferSize,
      Pointer<Uint32> lpBytesRead,
      Pointer<Uint32> lpTotalBytesAvail,
      Pointer<Uint32> lpBytesLeftThisMessage,
    );
typedef _PeekNamedPipeDart =
    int Function(
      int hNamedPipe,
      Pointer<Void> lpBuffer,
      int nBufferSize,
      Pointer<Uint32> lpBytesRead,
      Pointer<Uint32> lpTotalBytesAvail,
      Pointer<Uint32> lpBytesLeftThisMessage,
    );

_PeekNamedPipeDart _lookupPeekNamedPipe() =>
    _kernel32().lookupFunction<_PeekNamedPipeNative, _PeekNamedPipeDart>(
      'PeekNamedPipe',
    );

DynamicLibrary _kernel32() => DynamicLibrary.open('kernel32.dll');

_ReadWriteDart _lookupReadFile() =>
    _kernel32().lookupFunction<_ReadWriteNative, _ReadWriteDart>('ReadFile');

_ReadWriteDart _lookupWriteFile() =>
    _kernel32().lookupFunction<_ReadWriteNative, _ReadWriteDart>('WriteFile');

/// Opens a blocking, full-duplex handle to [pipePath]. Returns [_invalidHandle]
/// on failure.
int _openPipe(String pipePath) {
  final k32 = _kernel32();
  final createFileW = k32.lookupFunction<_CreateFileWNative, _CreateFileWDart>(
    'CreateFileW',
  );
  final namePtr = pipePath.toNativeUtf16();
  try {
    return createFileW(
      namePtr,
      _genericRead | _genericWrite,
      0, // no sharing
      nullptr,
      _openExisting,
      0,
      0,
    );
  } finally {
    calloc.free(namePtr);
  }
}

void _closeHandle(int handle) {
  final closeHandle = _kernel32()
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  closeHandle(handle);
}
