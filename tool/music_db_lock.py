#!/usr/bin/env python3
"""A mutex + a change guard for db.json.

WHY. db.json is a 65 MB JSON file that several agents edit concurrently with
ad-hoc scripts, and the only safety net is `.bak-<timestamp>` copies. That is
thin, and it already bit: mid-session the row count moved 46,357 -> 46,354
between two of my own commands, and a `content-held.json` appeared carrying rows
a parallel agent had pulled. It reconciled only because my script happened to
merge prior rows through instead of overwriting them. A different script would
have discarded another agent's work silently — no error, no diff, nothing in the
log.

Two guarantees, both cheap:

  * `db_lock()` — an exclusive lock, so two writers cannot interleave. Uses
    `flock`, which the kernel releases if the holder dies, so a killed script
    cannot wedge the corpus (a plain lockfile can, and then someone deletes it
    while a writer is live, which is worse than no lock).

  * `guarded_write()` — refuses to write a db.json whose on-disk state changed
    since you read it. This is the important half: the lock only helps processes
    that TAKE it, while the guard catches a stale in-memory copy however it
    happened.

Usage:

    from music_db_lock import db_lock, read_db, guarded_write

    with db_lock():
        db, token = read_db()
        db.append(row)
        guarded_write(db, token)      # raises if db.json moved underneath
"""
import contextlib
import fcntl
import hashlib
import json
import os
import time

ROOT = "/mnt/volume1/music-db"
DB = f"{ROOT}/db.json"
LOCK = f"{ROOT}/.db.lock"


class DbChanged(RuntimeError):
    """db.json changed between read and write — someone else wrote it."""


@contextlib.contextmanager
def db_lock(timeout=600):
    """Exclusive lock around a db.json read-modify-write."""
    os.makedirs(ROOT, exist_ok=True)
    fh = open(LOCK, "w")
    deadline = time.time() + timeout
    while True:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if time.time() > deadline:
                fh.close()
                raise TimeoutError(
                    f"db.json is locked by another process (waited {timeout}s). "
                    "Check for a running ingest before forcing anything.")
            time.sleep(1.0)
    try:
        fh.write(f"{os.getpid()}\n")
        fh.flush()
        yield
    finally:
        fcntl.flock(fh, fcntl.LOCK_UN)
        fh.close()


def _token(path=DB):
    """Cheap identity for the file as it is right now.

    Size + mtime + row count rather than a hash of 65 MB: hashing on every
    read/write would add seconds to every operation for no extra safety at this
    granularity — any real concurrent write changes at least one of these.
    """
    st = os.stat(path)
    return (st.st_size, st.st_mtime_ns)


def read_db(path=DB):
    """(rows, token). Pass the token back to `guarded_write`."""
    tok = _token(path)
    with open(path) as fh:
        return json.load(fh), tok


def guarded_write(rows, token, path=DB, backup=True):
    """Write `rows`, refusing if the file changed since `token` was taken.

    Writes to a temp file and renames, so a crash mid-write cannot leave a
    truncated db.json — the failure mode that makes the `.bak` files load-bearing
    in the first place.
    """
    if _token(path) != token:
        raise DbChanged(
            "db.json changed since you read it — another agent wrote it. "
            "Re-read and re-apply your change; do NOT overwrite.")
    if backup:
        with open(path, "rb") as src, \
                open(f"{path}.bak-{int(time.time())}", "wb") as dst:
            dst.write(src.read())
    tmp = f"{path}.tmp-{os.getpid()}"
    with open(tmp, "w") as fh:
        json.dump(rows, fh, indent=1)
    os.replace(tmp, path)          # atomic within a filesystem
    return len(rows)


def sha_of(path):
    """Full hash, for the rare caller that wants certainty over speed."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
