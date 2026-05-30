#!/usr/bin/env python3
"""TCP -> Docker unix-socket bridge.

The macOS App Sandbox lets the app make outbound TCP connections
(`com.apple.security.network.client`) but blocks connecting to a unix domain
socket (that's a `network-outbound (literal <path>)` check with no public
entitlement). OrbStack / Docker Desktop only expose the daemon over a socket,
so this script — run OUTSIDE the sandbox — bridges a localhost TCP port to that
socket. Point the app's Docker endpoint at http://localhost:2375.

  python3 dockerbridge.py [tcp_port] [unix_socket_path]

Defaults: 2375  /var/run/docker.sock
Uses only the Python standard library that ships with macOS — no install.
"""
import socket
import sys
import threading

TCP_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2375
SOCK = sys.argv[2] if len(sys.argv) > 2 else "/var/run/docker.sock"


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(client):
    upstream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        upstream.connect(SOCK)
    except OSError as e:
        print(f"upstream connect failed ({SOCK}): {e}")
        client.close()
        return
    threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
    pump(upstream, client)


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", TCP_PORT))
    srv.listen(64)
    print(f"docker bridge: http://127.0.0.1:{TCP_PORT}  ->  {SOCK}")
    try:
        while True:
            client, _ = srv.accept()
            threading.Thread(target=handle, args=(client,), daemon=True).start()
    except KeyboardInterrupt:
        print("\nbridge stopped")


if __name__ == "__main__":
    main()
