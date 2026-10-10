"""Exercise the bundled helper's private protocol using its in-memory test backend."""
import json
import subprocess
import sys
import time

helper = sys.argv[1]
subprocess.run([helper, "--self-test"], check=True)
process = subprocess.Popen(
    [helper, "--test-transport"], stdin=subprocess.PIPE,
    stdout=subprocess.PIPE, text=True,
)


def command(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()
    return json.loads(process.stdout.readline())


try:
    assert json.loads(process.stdout.readline())["ready"]
    response = command({"command": "enable", "port": 12334})
    assert response["ok"]
    time.sleep(35)
    assert command({"command": "restore", "port": 12334,
                    "backups": response["backups"]})["ok"]
    for offset in range(20):
        port = 12334 + offset
        response = command({"command": "enable", "port": port})
        assert response["ok"]
        assert command({"command": "restore", "port": port,
                        "backups": response["backups"]})["ok"]
    assert not command({"command": "enable", "port": 0})["ok"]
    assert not command({"command": "execute", "path": "/bin/sh"})["ok"]
    process.stdin.close()
    assert process.wait(timeout=5) == 0
    print("PASS: protocol after 35 seconds, 20 reconnects, invalid commands, EOF exit")
finally:
    if process.poll() is None:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
