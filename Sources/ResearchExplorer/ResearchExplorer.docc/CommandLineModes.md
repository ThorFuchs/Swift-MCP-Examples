# Command-line modes

Choose an explicit direct or MCP execution mode.

## Overview

From the repository root on the supported native Swift toolchain:

```bash
swift run research-explorer --walkthrough
swift run research-explorer --mcp-client
swift run research-explorer --stdio
```

The walkthrough is labeled DIRECT because it invokes the service without
MCP. The client mode starts a real stdio child, performs readiness discovery,
prepares the catalogue and calls the four research tools. On normal completion
it closes the child input and joins the transport. Failure cancels and joins
the owned run. The explicit stdio server reserves stdout for protocol frames;
diagnostics go to stderr.

No command above starts a public HTTP listener. Use the macOS app's Server
workspace for the explicit loopback HTTP demonstration.
