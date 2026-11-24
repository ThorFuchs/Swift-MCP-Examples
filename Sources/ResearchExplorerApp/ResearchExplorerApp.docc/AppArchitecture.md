# Application architecture

Follow data and ownership from research sources to the native UI.

## Overview

`ExplorerRootView` selects one of three native workspaces. `AppLifetime`
owns the selected source, research controller, server controller, guided
client and observation loop. The Reader projects an exact revision into
outline, article and evidence panes. Compact windows move auxiliary controls
out of the three-column arrangement.

The Server workspace uses the existing run-matched snapshot for all
server charts. The guided client uses its own finite task and optional
exchange records. Activity displays bounded redacted retained events.

The presentation does not add SDK dependencies or substitute its own wire
protocol. Core and HTTP release readiness remain separate from this app's
native review. The app has its own independent release and documentation
requirements.
