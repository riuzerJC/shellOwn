.pragma library

// Pure command building for the apply actions.
//
// Nothing here is ever executed by an agent: the self test asserts the exact argv, and the user
// validates the terminal path by hand.
//
// The commands are the ones the user named: `pacman` needs root, `yay` refuses to build as root and
// raises its own password prompt, and the Nix actions keep the literal `nix flake update` and
// `--flake .` forms, running inside the configured flake directory instead of taking a rewritten
// path. Detection and `nix flake update` stay in the shell; everything privileged or interactive
// goes through a terminal so the log stays visible.

const ACTIONS = {
    pacman: {
        argv: ["sudo", "pacman", "-Syu"],
        needsTerminal: true,
        needsFlakeDir: false
    },
    yay: {
        argv: ["yay", "-Syu"],
        needsTerminal: true,
        needsFlakeDir: false
    },
    nixFlakeUpdate: {
        argv: ["nix", "flake", "update"],
        needsTerminal: false,
        needsFlakeDir: true
    },
    nixosRebuild: {
        argv: ["sudo", "nixos-rebuild", "switch", "--flake", "."],
        needsTerminal: true,
        needsFlakeDir: true
    },
    homeManager: {
        argv: ["home-manager", "switch", "--flake", "."],
        needsTerminal: true,
        needsFlakeDir: true
    }
}

const SHELL_SAFE = /^[A-Za-z0-9_@%+=:,./-]+$/

function flakeDir(context) {
    const configured = context ? context.flakePath : undefined
    return typeof configured === "string" && configured !== "" ? configured : "."
}

// The exact argv for one action, with an empty working directory when the action does not care, or
// null for an unknown action. The prototype chain is excluded so that `constructor` and friends
// cannot reach an inherited value and spawn something unintended.
function buildCommand(action, context) {
    if (typeof action !== "string" || !Object.prototype.hasOwnProperty.call(ACTIONS, action))
        return null
    const spec = ACTIONS[action]
    return {
        argv: spec.argv.slice(),
        cwd: spec.needsFlakeDir ? flakeDir(context) : "",
        needsTerminal: spec.needsTerminal
    }
}

function shellQuote(value) {
    const text = String(value)
    return SHELL_SAFE.test(text) ? text : "'" + text.replace(/'/g, "'\\''") + "'"
}

// The argv that opens a terminal on one command, entering the working directory first when there is
// one, and holding the window open after it finishes so the log can be read (S7).
function terminalCommand(terminal, argv, cwd, hold) {
    const steps = []
    if (cwd)
        steps.push("cd " + shellQuote(cwd))
    const quoted = []
    for (let i = 0; i < argv.length; ++i)
        quoted.push(shellQuote(argv[i]))
    let script = (steps.length > 0 ? steps.join(" && ") + " && " : "") + quoted.join(" ")
    if (hold)
        script += "; printf '\\n[exit %s]\\n' $?; read _"
    return [terminal, "-e", "sh", "-c", script]
}
