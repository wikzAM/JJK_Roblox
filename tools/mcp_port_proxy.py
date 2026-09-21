"""Raw TCP proxy so the Studio MCP plugin (hardcoded http://localhost:58741)
reaches this session's robloxstudio-mcp server, which fell back to 58742 when a
stale server from a previous session held 58741. Restarting Studio is not an
option: the map is unsaved.

Listens on IPv4 AND IPv6 -- Windows resolves "localhost" to ::1 first, so an
IPv4-only proxy is invisible to the plugin even though curl finds it.
"""
import socket, threading, sys, time

LISTEN = int(sys.argv[1]) if len(sys.argv) > 1 else 58741
TARGET = int(sys.argv[2]) if len(sys.argv) > 2 else 58742


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def pipe(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            s.close()


def serve(family, host):
    srv = socket.socket(family, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if family == socket.AF_INET6:
        srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    srv.bind((host, LISTEN))
    srv.listen(128)
    log(f"listening {host}:{LISTEN} -> 127.0.0.1:{TARGET}")
    n = 0
    while True:
        client, peer = srv.accept()
        n += 1
        if n <= 5 or n % 50 == 0:
            log(f"{host} accept #{n} from {peer}")
        try:
            upstream = socket.create_connection(("127.0.0.1", TARGET))
        except OSError as exc:
            log("upstream refused:", exc)
            client.close()
            continue
        threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
        threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()


threading.Thread(target=serve, args=(socket.AF_INET, "0.0.0.0"), daemon=True).start()
try:
    serve(socket.AF_INET6, "::1")
except OSError as exc:
    log("no IPv6 listener:", exc)
    while True:
        time.sleep(3600)
