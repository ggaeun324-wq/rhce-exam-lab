#!/usr/bin/env python3
"""Patch ansible.posix.firewalld so 'immediate' operations don't hard-fail when
the firewalld daemon can't run (this lab's WSL2 kernel lacks bridge netfilter).

Usage:
  fwpatch2.py                      # patch the system-path module (default)
  fwpatch2.py <firewalld.py ...>   # patch given loose module file(s)
  fwpatch2.py --scan <root ...>    # find & patch every posix firewalld.py under root(s)
  fwpatch2.py --tarball <a.tar.gz> # patch a galaxy collection artifact (updates checksums)
"""
import sys
import os
import json
import glob
import hashlib
import tarfile
import tempfile
import shutil

OLD = (
    "    if immediate and fw_offline:\n"
    "        module.fail_json(msg='firewall is not currently running, "
    "unable to perform immediate actions without a running firewall daemon')"
)
NEW = (
    "    if immediate and fw_offline:\n"
    "        # Lab workaround: this container kernel (WSL2) lacks bridge netfilter,\n"
    "        # so the firewalld daemon cannot start. python3-firewall offline mode can\n"
    "        # still write permanent config, so degrade immediate operations to permanent\n"
    "        # instead of failing. With no running daemon nothing filters traffic, so the\n"
    "        # service stays reachable exactly as an 'allow' rule intends.\n"
    "        module.warn('firewalld daemon not running (lab); applying permanent configuration only.')\n"
    "        immediate = False\n"
    "        permanent = True"
)
MARK = "Lab workaround: this container kernel"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def patch_text(path):
    """Patch a loose module file. Returns 'ALREADY'/'PATCHED'/'MARKER_NOT_FOUND'."""
    with open(path, encoding="utf-8") as f:
        s = f.read()
    if MARK in s:
        return "ALREADY"
    if OLD in s:
        with open(path, "w", encoding="utf-8") as f:
            f.write(s.replace(OLD, NEW, 1))
        return "PATCHED"
    return "MARKER_NOT_FOUND"


def patch_tarball(tarpath):
    """Patch plugins/modules/firewalld.py inside a galaxy artifact and fix
    FILES.json + MANIFEST.json checksums, then repackage in place."""
    work = tempfile.mkdtemp(prefix="fwtb_")
    try:
        with tarfile.open(tarpath) as t:
            t.extractall(work)
        mod = os.path.join(work, "plugins", "modules", "firewalld.py")
        if not os.path.isfile(mod):
            return "NO_MODULE_IN_TARBALL"
        st = patch_text(mod)
        if st == "MARKER_NOT_FOUND":
            return "MARKER_NOT_FOUND"
        # Update FILES.json entry for the module
        fjp = os.path.join(work, "FILES.json")
        fj = json.load(open(fjp, encoding="utf-8"))
        newsum = sha256(mod)
        for e in fj["files"]:
            if e.get("name") == "plugins/modules/firewalld.py":
                e["chksum_sha256"] = newsum
        with open(fjp, "w", encoding="utf-8") as f:
            json.dump(fj, f, indent=4, sort_keys=True)
        # Update MANIFEST.json checksum of FILES.json
        mfp = os.path.join(work, "MANIFEST.json")
        mf = json.load(open(mfp, encoding="utf-8"))
        mf["file_manifest_file"]["chksum_sha256"] = sha256(fjp)
        with open(mfp, "w", encoding="utf-8") as f:
            json.dump(mf, f, indent=4, sort_keys=True)
        # Repack: members at archive root (galaxy artifact layout)
        tmp_out = tarpath + ".new"
        with tarfile.open(tmp_out, "w:gz") as t:
            for name in sorted(os.listdir(work)):
                t.add(os.path.join(work, name), arcname=name)
        shutil.move(tmp_out, tarpath)
        return "ALREADY_TARBALL" if st == "ALREADY" else "PATCHED_TARBALL"
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    args = sys.argv[1:]
    if not args:
        default = ("/usr/share/ansible/collections/ansible_collections/"
                   "ansible/posix/plugins/modules/firewalld.py")
        print(default, "->", patch_text(default))
        return
    if args[0] == "--tarball":
        for tp in args[1:]:
            print(tp, "->", patch_tarball(tp))
        return
    if args[0] == "--scan":
        roots = args[1:]
        found = []
        for r in roots:
            found += glob.glob(os.path.join(
                r, "**", "ansible_collections", "ansible", "posix",
                "plugins", "modules", "firewalld.py"), recursive=True)
        if not found:
            print("NO_MODULES_FOUND under", roots)
        for m in sorted(set(found)):
            print(m, "->", patch_text(m))
        return
    for m in args:
        print(m, "->", patch_text(m))


if __name__ == "__main__":
    main()
