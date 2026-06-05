#!/usr/bin/env python3
import os
import signal
import socket
import subprocess
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.system("fuser -k 39231/tcp 39233/tcp 2>/dev/null")
time.sleep(0.5)
env = os.environ.copy()
env.update({"BACKEND_PORT": "39231", "LI_HTTPD_PROXY_SNAP": "0", "LI_HTTPD_PROXY_C": "1"})
be = subprocess.Popen(
    ["node", os.path.join(ROOT, "li-tests/hosting-matrix/backends/node-server.mjs")],
    env=env,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
)
time.sleep(1)
fe = subprocess.Popen(
    [os.path.join(ROOT, "build/li-httpd"), "39233", os.path.join(ROOT, "li-tests/hosting-matrix/static"), "39231"],
    env=env,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
)
time.sleep(1)
req = (
    b"POST /api/echo HTTP/1.1\r\n"
    b"Host: 127.0.0.1:39233\r\n"
    b"Content-Type: application/json\r\n"
    b"Content-Length: 17\r\n"
    b"Connection: close\r\n\r\n"
    b'{"hello":"world"}'
)
s = socket.create_connection(("127.0.0.1", 39233), timeout=5)
s.sendall(req)
s.shutdown(socket.SHUT_WR)
data = s.recv(4096)
print("RESP", repr(data))
be.send_signal(signal.SIGTERM)
fe.send_signal(signal.SIGTERM)
