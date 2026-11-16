#!/usr/bin/env python3
"""Fake UE5 endpoint for testing WoZControl without Unreal.

TCP server, one JSON object per line. Replies like the real UE5 blueprint should:
  play    -> {"event":"started"} now, {"event":"done"} after "duration" seconds
  ping    -> {"event":"pong"}
  gesture -> {"event":"gesture_done"} after 1 s
  stop    -> cancels pending "done" replies
Usage: python3 ue5_simulator.py [port]   (default 7000)
"""
import json, socket, sys, threading, time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 7000
lock = threading.Lock()


def send(conn, obj):
    with lock:
        conn.sendall((json.dumps(obj) + "\n").encode())


def handle(conn, addr):
    print(f"[UE5 sim] client {addr}", flush=True)
    timers = []
    buf = b""
    try:
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                m = json.loads(line)
                print("[UE5 sim] <-", line.decode(), flush=True)
                ev, seq = m.get("event"), m.get("seq")
                if ev == "ping":
                    send(conn, {"event": "pong", "seq": seq})
                elif ev == "play":
                    send(conn, {"event": "started", "clip": m["clip"], "seq": seq})
                    t = threading.Timer(float(m.get("duration", 1.0)), send,
                                        (conn, {"event": "done", "clip": m["clip"], "seq": seq}))
                    t.start(); timers.append(t)
                elif ev == "gesture":
                    t = threading.Timer(1.0, send, (conn, {"event": "gesture_done", "clip": m["name"], "seq": seq}))
                    t.start(); timers.append(t)
                elif ev == "stop":
                    for t in timers:
                        t.cancel()
                    timers.clear()
    except (ConnectionError, OSError):
        pass
    finally:
        for t in timers:
            t.cancel()
        conn.close()
        print(f"[UE5 sim] client {addr} closed", flush=True)


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen()
    print(f"[UE5 sim] listening on 127.0.0.1:{PORT}", flush=True)
    while True:
        conn, addr = srv.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()
