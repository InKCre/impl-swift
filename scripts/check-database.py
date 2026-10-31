"""Run Swift's database/native checks against an explicitly disposable, migrated database.

Consume a restricted JSON descriptor, or own a temporary PostgreSQL cluster initialized by
impl-py's authoritative lifecycle. No schema is defined or copied by this script.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import signal
import shutil
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def test_environment(descriptor):
    if descriptor.get("disposable") is not True:
        raise ValueError("database descriptor must explicitly declare disposable: true")
    if descriptor.get("host") not in {"localhost", "127.0.0.1"}:
        raise ValueError("database access must use a loopback endpoint")
    if descriptor.get("username") != "inkcre_core":
        raise ValueError("tests require the admitted inkcre_core role, never an administrator")
    port = descriptor.get("port")
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError("descriptor port is invalid")
    if not all(isinstance(descriptor.get(key), str) and descriptor[key]
               for key in ("database", "password")):
        raise ValueError("descriptor database and password are required")
    env = os.environ.copy()
    env["NSUnbufferedIO"] = "YES"
    for prefix in ("INKCRE_CAPTURE_TEST", "INKCRE_FILES_TEST"):
        env.update({f"{prefix}_DATABASE": descriptor["database"],
                    f"{prefix}_PORT": str(port), f"{prefix}_PASSWORD": descriptor["password"]})
    return env


def run_tests(command, env, timeout=600):
    process = subprocess.Popen(command, cwd=ROOT, env=env, start_new_session=True)
    try:
        status = process.wait(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        print("Database/native checks did not finish; stopping the test process group.", flush=True)
        # SwiftPM's testing helper creates its own process group. Snapshot only descendants
        # of our child before stopping the parent, so orphaned helpers remain identifiable.
        table = [tuple(map(int, row.split())) for row in subprocess.check_output(
            ["ps", "-axo", "pid=,ppid=,pgid="], text=True).splitlines()]
        owned = {process.pid}
        while True:
            children = {pid for pid, parent, _ in table if parent in owned}
            if children <= owned:
                break
            owned.update(children)
        groups = {process.pid} | {group for pid, _, group in table
                                  if pid in owned and group in owned}
        for sig in (signal.SIGTERM, signal.SIGKILL):
            for group in groups:
                try:
                    os.killpg(group, sig)
                except ProcessLookupError:
                    pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
        deadline = time.monotonic() + 5
        while groups:
            for group in tuple(groups):
                try:
                    os.killpg(group, 0)
                except ProcessLookupError:
                    groups.remove(group)
            if groups and time.monotonic() >= deadline:
                raise RuntimeError("test process groups did not terminate after SIGKILL")
            if groups:
                time.sleep(0.05)
        raise
    if status:
        raise subprocess.CalledProcessError(status, command)


def check(descriptor):
    env = test_environment(descriptor)
    print("Running Capture and Local Files database/native checks in the disposable database.", flush=True)
    run_tests(["swift", "test", "--disable-automatic-resolution", "--no-parallel", "--jobs",
               env.get("SWIFT_JOBS", "2")], env)


def with_cluster(impl_py, postgres_bin):
    impl_py = impl_py.resolve()
    lifecycle = impl_py / "scripts/database.py"
    if not lifecycle.is_file():
        raise ValueError("--impl-py must point to the authoritative impl-py checkout")
    def pg(command):
        executable = postgres_bin / command if postgres_bin else shutil.which(command)
        if not executable or not Path(executable).is_file():
            raise ValueError(f"PostgreSQL 17 tools unavailable: {command}; see README database checks")
        return str(executable)
    tools = {name: pg(name) for name in ("initdb", "pg_ctl", "createdb")}
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=impl_py, text=True).strip()
    print(f"Initializing disposable database with impl-py {revision}", flush=True)
    with tempfile.TemporaryDirectory(prefix="inkcre-swift-db-", dir="/tmp") as temporary:
        root = Path(temporary)
        data = root / "data"
        password = secrets.token_urlsafe(36)
        password_file = root / "password"
        password_file.write_text(password)
        password_file.chmod(0o600)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        env = os.environ.copy()
        env.update(PGPASSWORD=password, INKCRE_ENV_FILE="")
        subprocess.run([tools["initdb"], "-D", str(data), "-U", "postgres",
                        "--auth-local=trust", "--auth-host=scram-sha-256",
                        "--pwfile", str(password_file)], env=env, check=True)
        started = False
        try:
            subprocess.run([tools["pg_ctl"], "-D", str(data), "-l", str(root / "postgres.log"),
                            "-o", f"-h 127.0.0.1 -p {port} -k {root}", "-w", "start"],
                           env=env, check=True)
            started = True
            subprocess.run([tools["createdb"], "-h", "127.0.0.1", "-p", str(port),
                            "-U", "postgres", "swift_acceptance"], env=env, check=True)
            env.update(MIGRATION_DATABASE_URL=
                       f"postgresql+psycopg://postgres:{password}@127.0.0.1:{port}/swift_acceptance",
                       CORE_DATABASE_PASSWORD=password,
                       POSTGREST_DATABASE_PASSWORD=secrets.token_urlsafe(36))
            subprocess.run(["pdm", "run", "python", str(lifecycle), "init", "--profile", "development"],
                           cwd=impl_py, env=env, check=True)
            subprocess.run(["pdm", "run", "python", str(lifecycle), "ready", "--profile", "development"],
                           cwd=impl_py, env=env, check=True)
            check(dict(disposable=True, host="127.0.0.1", port=port,
                       database="swift_acceptance", username="inkcre_core", password=password))
        finally:
            if started:
                subprocess.run([tools["pg_ctl"], "-D", str(data), "-m", "fast", "-w", "stop"],
                               check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--descriptor", type=Path, help="0600 JSON describing an exclusively owned disposable database")
    source.add_argument("--impl-py", type=Path, help="initialized PDM checkout owning migrations; creates a new temporary cluster")
    parser.add_argument("--postgres-bin", type=Path, help="PostgreSQL 17 bin directory (pgvector must be installed)")
    args = parser.parse_args()
    if args.descriptor:
        if args.descriptor.stat().st_mode & 0o077:
            parser.error("database descriptor must be private (chmod 600)")
        check(json.loads(args.descriptor.read_text()))
    else:
        with_cluster(args.impl_py, args.postgres_bin)


if __name__ == "__main__":
    main()
