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
    void cleanup() {
      if (closed) return;
      closed = true;
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

void _readerEntry(_PipeArg arg) {
  final readFile = _lookupReadFile();
  final buf = calloc<Uint8>(_bufSize);
  final read = calloc<Uint32>();
  try {
    while (true) {
      final ok = readFile(arg.handle, buf, _bufSize, read, nullptr);
      final n = read.value;
      if (ok == 0 || n == 0) break;
      arg.sendPort.send(Uint8List.fromList(buf.asTypedList(n)));
    }
  } finally {
    calloc.free(buf);
    calloc.free(read);
    arg.sendPort.send(null); // signal EOF
  }
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
