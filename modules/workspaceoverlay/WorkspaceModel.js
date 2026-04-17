function collectWorkspaces(workspaces, monitor, perMonitor) {
    const monitorName = monitor?.name ?? "";

    function partition(usePerMonitorFilter) {
        const normal = [];
        const special = [];

        for (const workspace of workspaces) {
            if (!workspace)
                continue;

            if (usePerMonitorFilter && monitorName) {
                const wsMonitorName = workspace?.monitor?.name ?? workspace?.lastIpcObject?.monitor ?? "";
                if (wsMonitorName && wsMonitorName !== monitorName)
                    continue;
            }

            if (workspace.name?.startsWith("special:"))
                special.push(workspace);
            else
                normal.push(workspace);
        }

        normal.sort((a, b) => a.id - b.id);
        special.sort((a, b) => a.name.localeCompare(b.name));

        return {
            normal,
            special
        };
    }

    const filtered = partition(perMonitor);
    if (!perMonitor || !monitorName)
        return filtered;

    // Runtime fallback: if monitor metadata mismatch filters everything out,
    // prefer showing all workspaces over rendering an empty overlay.
    if (filtered.normal.length === 0 && filtered.special.length === 0)
        return partition(false);

    return filtered;
}

function groupWindowsByWorkspace(toplevels, workspaces) {
    const byWorkspace = {};

    for (const workspace of workspaces.normal)
        byWorkspace[String(workspace.id)] = [];

    for (const workspace of workspaces.special)
        byWorkspace[workspace.name] = [];

    for (const window of toplevels) {
        const workspace = window?.workspace;
        if (!workspace)
            continue;

        const key = workspace.name?.startsWith("special:") ? workspace.name : String(workspace.id);
        if (!byWorkspace[key])
            byWorkspace[key] = [];

        byWorkspace[key].push(window);
    }

    return byWorkspace;
}

function workspaceTokenFromWindow(window) {
    const workspace = window?.workspace;
    if (!workspace)
        return "";

    return workspace.name?.startsWith("special:") ? workspace.name : String(workspace.id ?? "");
}
