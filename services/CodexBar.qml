pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    property list<var> providers: []
    property bool fetching: false
    property bool available: true
    property date lastUpdated: new Date(0)

    // Providers whose credentials are renewed via their own CLI (empty = API-key based).
    readonly property var authCommands: ({
            "codex": "codex login",
            "opencode": "opencode auth login",
            "gemini": "gemini",
            "copilot": "gh auth login"
        })

    readonly property var providerNames: ({
            "codex": "Codex",
            "openai": "OpenAI",
            "opencode": "OpenCode",
            "gemini": "Gemini",
            "copilot": "Copilot",
            "deepseek": "DeepSeek"
        })

    // Providers that accept keys via `codexbar config set-api-key` (verified against the installed
    // binary 0.56.6; deepseek reads DEEPSEEK_API_KEY from env, codex/opencode/gemini use their CLI/OAuth).
    readonly property var apiKeyProviders: ["openai", "copilot"]

    function supportsApiKey(providerId: string): bool {
        return root.apiKeyProviders.includes(providerId);
    }

    // ponytail: auth detection is message-heuristic because codexbar errors carry no auth kind;
    // upgrade when CodexBar adds a dedicated error kind.
    function isAuthError(message: string): bool {
        return /401|unauthor|sign in|sign-in|auth|token|login/i.test(message);
    }

    function reload(): void {
        if (usageProc.running)
            return;
        root.fetching = true;
        usageProc.running = true;
    }

    function renew(providerId: string): void {
        const cmd = root.authCommands[providerId];
        if (!cmd)
            return;
        Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "fish", "-C", cmd]);
    }

    function setApiKey(providerId: string, key: string, callback: var): void {
        if (apiKeyProc.running || !key.length)
            return;
        apiKeyProc.providerId = providerId;
        apiKeyProc.cb = callback;
        apiKeyProc.pendingKey = key;
        apiKeyProc.running = true;
    }

    function providerName(providerId: string): string {
        return root.providerNames[providerId] ?? providerId;
    }

    function normalize(raw: var): list<var> {
        return raw.map(r => {
            const err = r.error ?? null;
            const message = err?.message ?? "";
            const usage = r.usage ?? {};
            return {
                "id": r.provider,
                "name": root.providerName(r.provider),
                "state": err ? (isAuthError(message) ? "authError" : "error") : "ok",
                "errorText": err ? message.split("\n")[0] : "",
                "primary": usage.primary ? {
                    "usedPercent": usage.primary.usedPercent,
                    "resetsAt": usage.primary.resetsAt ?? ""
                } : null,
                "secondary": usage.secondary ? {
                    "usedPercent": usage.secondary.usedPercent,
                    "resetsAt": usage.secondary.resetsAt ?? ""
                } : null,
                "credits": r.credits?.remaining ?? null,
                "accountEmail": usage.identity?.accountEmail ?? usage.accountEmail ?? "",
                "plan": usage.identity?.loginMethod ?? "",
                "pace": r.pace?.primary?.summary ?? "",
                "authCommand": root.authCommands[r.provider] ?? ""
            };
        });
    }

    Process {
        id: usageProc

        // sh wrapper so a missing binary still exits (127) instead of failing to spawn
        command: ["sh", "-c", "codexbar usage --format json"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.fetching = false;
                try {
                    const raw = JSON.parse(text);
                    root.providers = root.normalize(Array.isArray(raw) ? raw : [raw]);
                    root.available = true;
                    root.lastUpdated = new Date();
                } catch (e) {
                    root.available = false;
                }
            }
        }

        onExited: code => {
            if (code === 127 || code === 2) // codexbar not on PATH / provider missing
                root.available = false;
            root.fetching = false;
        }
    }

    Process {
        id: apiKeyProc

        property string providerId
        property string pendingKey
        property var cb

        stdinEnabled: true
        command: ["codexbar", "config", "set-api-key", "--provider", providerId, "--stdin"]

        // Process start is async: write only once the process reports started, then close stdin (EOF).
        onStarted: {
            write(pendingKey);
            pendingKey = "";
            stdinEnabled = false;
        }

        stdout: StdioCollector {
        }

        stderr: StdioCollector {
        }

        onExited: code => {
            const cb = apiKeyProc.cb;
            apiKeyProc.cb = null;
            if (cb)
                cb(code === 0);
        }
    }

    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.reload()
    }
}
