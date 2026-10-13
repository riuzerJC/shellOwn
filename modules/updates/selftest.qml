// Self-test entry for the update detection logic. It creates no window.
//
// Run through the runner, which owns the exit code:
//     python3 scripts/updates-selftest.py
//
// quickshell sandboxes relative imports to the directory of the entry file, so this entry and its
// cases live inside the module tree they test and import `core/PendingUpdates.js` downward. The
// cases sit in their own file so that a module under test which does not exist yet is reported as a
// failing case instead of aborting the run.

import QtQuick
import Quickshell

ShellRoot {
    id: harness

    property int passed: 0
    property int failed: 0

    function report(index, ok, name, detail) {
        const suffix = ok || detail === "" ? "" : " (" + detail + ")"
        console.log((ok ? "ok " : "not ok ") + index + " - " + name + suffix)
        if (ok)
            ++harness.passed
        else
            ++harness.failed
    }

    function runAll(suite) {
        const list = suite.entries
        for (let i = 0; i < list.length; ++i) {
            let detail = ""
            let ok = true
            try {
                list[i].run()
            } catch (e) {
                ok = false
                detail = e && e.message ? e.message : String(e)
            }
            harness.report(i + 1, ok, list[i].name, detail)
        }
    }

    function finish(total) {
        console.log("1.." + total)
        console.log(harness.failed === 0 ? "# all " + harness.passed + " cases passed" : "# " + harness.failed + " of " + total + " cases failed")
        // Quickshell exposes no way to exit with a status: Qt.exit only emits a signal that nothing
        // handles, and `quickshell kill` would also kill unrelated instances. The process therefore
        // terminates itself by pid and the runner turns the TAP output above into the real exit code.
        Quickshell.execDetached(["sh", "-c", "kill -TERM " + Quickshell.processId])
    }

    Component.onCompleted: {
        const suite = Qt.createComponent("selftest-cases.qml")
        if (suite.status === Component.Error) {
            harness.report(1, false, "selftest-cases.qml loads", suite.errorString().replace(/\s+/g, " ") + " -- a module under test is probably missing or invalid")
            harness.finish(1)
            return
        }
        const cases = suite.createObject(harness)
        harness.runAll(cases)
        harness.finish(cases.entries.length)
    }
}
