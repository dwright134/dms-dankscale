#!/usr/bin/env python3
"""Exercise the service's real operator-grant QML with Quickshell and a fake pkexec.

Run: python3 tests/test_operator_grant.py
Requires Python 3, Quickshell, and /bin/sh. No real authorization, Tailscale
commands, or desktop UI are used. Only the grant function and its two Process
objects are loaded; startup polling and other service operations are excluded.
"""

from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
quickshell = shutil.which("qs") or shutil.which("quickshell")
if not quickshell:
    raise SystemExit("Quickshell is required to run these tests")
source = (repo / "services/TailscaleService.qml").read_text()
fn = source[
    source.index("    function grantOperator()") : source.index(
        "    function setOperatorMissing"
    )
]
start = source.rfind("    Process {", 0, source.index("        id: grantLookupProc"))
end = source.rfind("    Process {", 0, source.index("        id: loginProc"))
processes = source[start:end].replace("ToastService.", "toast.")
temporary = tempfile.TemporaryDirectory(prefix="dankscale-operator-tests-")
base = Path(temporary.name)


def test(name, layout="normal", exitcode=0, user="test-user", rounds=1):
    p = Path(tempfile.mkdtemp(prefix=name + "-", dir=base))
    bindir = p / "helpers"
    bindir.mkdir()
    (bindir / "sh").symlink_to("/bin/sh")
    mock = bindir / "pkexec"
    mock.write_text(
        "#!"
        + sys.executable
        + """
import sys,os,json,time
with open(os.environ['TEST_RECORD'],'a') as f: f.write(json.dumps(sys.argv[1:])+"\\n")
if os.environ.get('TEST_REMOVE'): os.unlink(os.environ['TEST_REMOVE'])
time.sleep(0.08)
sys.exit(int(os.environ['TEST_EXIT']))
"""
    )
    mock.chmod(0o755)
    directory = p / ("custom tools;$(echo injected)" if layout == "spaces" else "cli")
    directory.mkdir()
    target = directory / "tailscale"
    if layout not in ["missing", "directory"]:
        target.write_text("#!/bin/sh\nexit 0\n")
        target.chmod(0o644 if layout == "nonexec" else 0o755)
    if layout == "directory":
        target.mkdir()
    if layout == "symlink":
        profile = p / "profile"
        profile.mkdir()
        (profile / "tailscale").symlink_to(target)
        target = profile / "tailscale"
        directory = profile
    pathdir = directory.name if layout == "relative" else str(directory)
    record = p / "calls.jsonl"
    qml = (
        """import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id: root
    property string currentUser: Quickshell.env("TEST_USER")
    property int refreshCount: 0
    property var events: []
    property int completed: 0
    property int wanted: Number(Quickshell.env("TEST_ROUNDS"))
    function refresh() { refreshCount++; }
    QtObject {
        id: toast
        function showInfo(text) { root.events.push(["info",text]); }
        function showError(title,text) { root.events.push(["error",text]); }
    }
"""
        + fn
        + processes
        + """
    Component.onCompleted: { root.grantOperator(); root.grantOperator(); }
    Timer {
        interval: 25; running: true; repeat: true
        onTriggered: {
            if (grantLookupProc.running || grantProc.running) return;
            root.completed++;
            if (root.completed < root.wanted) {
                root.grantOperator(); root.grantOperator(); return;
            }
            console.warn("TEST_RESULT:"+JSON.stringify({events:root.events,refreshes:root.refreshCount}));
            Qt.quit();
        }
    }
}
"""
    )
    (p / "shell.qml").write_text(qml)
    env = dict(
        os.environ,
        QT_QPA_PLATFORM="offscreen",
        QT_QUICK_BACKEND="software",
        PATH=pathdir + ":" + str(bindir),
        TEST_RECORD=str(record),
        TEST_EXIT=str(exitcode),
        TEST_USER=user,
        TEST_ROUNDS=str(rounds),
        TEST_REMOVE=str(target) if layout == "disappearing" else "",
    )
    r = subprocess.run(
        [quickshell, "-p", str(p / "shell.qml"), "--no-color"],
        env=env,
        cwd=p,
        capture_output=True,
        text=True,
        timeout=8,
    )
    output = r.stdout + r.stderr
    if r.returncode or "TEST_RESULT:" not in output:
        print(output)
        raise AssertionError(name + " runtime failed")
    result = json.loads(output.split("TEST_RESULT:", 1)[1].splitlines()[0])
    calls = (
        [json.loads(x) for x in record.read_text().splitlines()]
        if record.exists()
        else []
    )
    if user in ["", "root"]:
        assert calls == [] and result["events"] == [], result
    elif layout == "disappearing":
        assert len(calls) == 1, calls
        assert result["refreshes"] == 1, result
        assert result["events"] == [
            ["info", "Operator access granted"],
            ["error", "Cannot find an executable tailscale CLI in the widget's PATH"],
        ], result
    elif layout in ["missing", "nonexec", "directory"]:
        assert calls == [] and result["events"] == [
            ["error", "Cannot find an executable tailscale CLI in the widget's PATH"]
        ], result
    else:
        assert (
            calls
            == [
                [
                    "/usr/bin/env",
                    "TS_BE_CLI=1",
                    str(target),
                    "set",
                    "--operator=" + user,
                ]
            ]
            * rounds
        ), calls
        assert result["refreshes"] == rounds, result
        if exitcode == 126:
            assert result["events"] == [], result
        elif exitcode:
            assert (
                result["events"]
                == [["error", "Operator setup failed (exit " + str(exitcode) + ")"]]
                * rounds
            ), result
        else:
            assert result["events"] == [["info", "Operator access granted"]] * rounds, (
                result
            )
    print("PASS", name)


for name, layout in [
    ("ordinary_path", "normal"),
    ("spaces_and_shell_metacharacters", "spaces"),
    ("relative_PATH", "relative"),
    ("profile_symlink_preserved", "symlink"),
    ("missing_binary", "missing"),
    ("nonexecutable_file", "nonexec"),
    ("directory_is_not_executable_file", "directory"),
]:
    test(name, layout)
test("cancel_and_retry", exitcode=126, rounds=2)
test("failure_without_stderr", exitcode=127)
test("success_and_retry", rounds=2)
test("root_is_skipped", user="root")
test("unknown_user_is_skipped", user="")

test("fresh_lookup_after_removal", layout="disappearing", rounds=2)

print("All 13 operator-grant scenarios passed.")
