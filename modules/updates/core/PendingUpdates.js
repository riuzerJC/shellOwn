.pragma library

// Pure parsing of pending system updates. No QML types and no state, so the self-test harness can
// exercise every rule directly.
//
// pacman, checkupdates and yay all print one upgrade per line as:
//     <name> <from> -> <to>[ <marker>]
// The marker is localized for pacman (`[ignorado]` under a Spanish locale, `[ignored]` under
// `LC_ALL=C`) and carries the time since the AUR release for yay (`[6h26m]`), so it is matched as a
// generic trailing bracket and never by its text.

var UPGRADE = /^(\S+) (\S+) -> (\S+)(?: \[([^\]]*)\])?$/

function text(value) {
    return value === undefined || value === null ? "" : String(value)
}

function parseLines(output, markerMeansIgnored) {
    const entries = []
    const lines = text(output).split("\n")
    for (let i = 0; i < lines.length; ++i) {
        const match = UPGRADE.exec(lines[i].trim())
        if (!match)
            continue
        entries.push({
            name: match[1],
            from: match[2],
            to: match[3],
            ignored: markerMeansIgnored && match[4] !== undefined
        })
    }
    return entries
}

// `pacman -Qu`, instant and offline, but only as fresh as the last database sync, and marked with
// the localized ignored marker for everything in IgnorePkg.
function parsePacmanQu(output) {
    return parseLines(output, true)
}

// `checkupdates` from pacman-contrib. It syncs a copy of the databases into a temporary directory, so
// it needs no root, is accurate, and never prints the ignored marker.
function parseCheckupdates(output) {
    return parseLines(output, false)
}

// `yay -Qua` for the AUR. The bracket holds the age of the AUR release, so it says nothing about the
// package being ignored.
function parseYayQua(output) {
    return parseLines(output, false)
}

// The revision a flake input is locked to, or an empty string when the lock is unreadable or the
// input is absent.
function flakeLockedRev(lockText, inputName) {
    let lock
    try {
        lock = JSON.parse(text(lockText))
    } catch (e) {
        return ""
    }
    const node = lock && lock.nodes ? lock.nodes[inputName] : undefined
    const locked = node ? node.locked : undefined
    return locked && typeof locked.rev === "string" ? locked.rev : ""
}

// A flake input is stale only when both revisions are known and differ: an unknown revision is not
// evidence of an update.
function flakeIsStale(lockedRev, remoteRev) {
    if (typeof lockedRev !== "string" || typeof remoteRev !== "string")
        return false
    if (lockedRev === "" || remoteRev === "")
        return false
    return lockedRev !== remoteRev
}

// The remote a flake input tracks, derived from the `original` block of `flake.lock`. Only a github
// input with an owner, a repo and a ref can be compared: an input pinned by `rev` alone has nothing
// to follow, and a `git` input carries a url instead of an owner/repo pair. The returned `ref` is
// fully qualified, because that is what `git ls-remote` wants: a bare name is a branch, while a ref
// the input already qualified (`refs/tags/...`) is kept, which is the only signal a lock file gives
// for a tag.
function flakeRemoteRef(lockText, inputName) {
    let lock
    try {
        lock = JSON.parse(text(lockText))
    } catch (e) {
        return null
    }
    const node = lock && lock.nodes ? lock.nodes[inputName] : undefined
    const original = node ? node.original : undefined
    if (!original || original.type !== "github")
        return null
    const owner = original.owner
    const repo = original.repo
    const ref = original.ref
    if (typeof owner !== "string" || owner === "" || typeof repo !== "string" || repo === "" || typeof ref !== "string" || ref === "")
        return null
    return {
        url: "https://github.com/" + owner + "/" + repo,
        ref: ref.indexOf("refs/") === 0 ? ref : "refs/heads/" + ref
    }
}

// The revision `git ls-remote <url> <ref>` reported for one ref, or an empty string when the remote
// did not advertise it. An annotated tag is advertised twice: `<ref>` is the tag object and
// `<ref>^{}` is the commit it points at, and the lock stores the commit, so the peeled line wins
// when it is present.
function parseLsRemote(output, ref) {
    const lines = text(output).split("\n")
    let peeled = ""
    let direct = ""
    for (let i = 0; i < lines.length; ++i) {
        const match = /^([0-9a-fA-F]{40,64})[ \t]+(\S+)$/.exec(lines[i].trim())
        if (!match)
            continue
        if (match[2] === ref + "^{}")
            peeled = match[1]
        else if (match[2] === ref)
            direct = match[1]
    }
    return peeled !== "" ? peeled : direct
}
