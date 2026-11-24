# Native qualification and review

Collect exact-source test receipts, rendered scenes and DocC archives.

## Overview

On macOS 27 with Swift 6.4:

```bash
bash Scripts/qualify-re04-local.sh
swift test --filter ExplorerMotionTests
bash Scripts/snapshot-design-local.sh
bash Scripts/build-docc-local.sh
```

The opt-in screenshot suite captures fifteen fixed viewports, including
five real loopback/offline Machine Room scenarios. Each of those executes
the real guided MCP client, checks six recorded exchanges and four terminal
handlers, and then captures actual views. The capture harness controls
hosting size and rejects mismatched geometry. The generated files include
dimensions, toolchain and source identity.

The snapshots are CALayer captures, not full Window Server renderings;
sidebar vibrancy, native glass and window chrome may differ. Review actual
windows and animation behavior separately. Source changes and screenshot
presence do not establish HIG conformance.

The DocC script exports internal and public symbol graphs using the Swift
toolchain and converts each of the six target-local catalogs into a separate
archive. Warnings are errors; coverage output identifies remaining symbol
documentation gaps. No dependency or CI workflow is modified by this step.
