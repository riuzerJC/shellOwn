#pragma once

#include <qstring.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

class UpdatesConfig : public settings::ObjectNode {
    CONFIG_NODE(UpdatesConfig, settings::ObjectNode)

    // Seconds between update detection polls
    CONFIG_GLOBAL_PROPERTY(int, checkInterval, 1800)
    // Directory holding the Nix flake; empty when the Nix path is unused
    CONFIG_GLOBAL_PROPERTY(QString, flakePath, {})
    // Terminal emulator used for privileged or interactive actions; empty to use the shell default
    CONFIG_GLOBAL_PROPERTY(QString, terminal, {})
};

} // namespace caelestia::config
