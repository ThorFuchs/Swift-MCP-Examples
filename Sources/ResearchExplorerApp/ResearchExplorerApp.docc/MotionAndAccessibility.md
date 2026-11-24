# Motion and accessibility

Use state-driven motion to communicate change, not to create traffic.

## Overview

`ExplorerDesign.Motion` centralizes four short animation roles: metric,
chart, selection and status. Numeric text transitions operate only on
measured numeric labels. Status replacement and SF Symbol transitions are
tied to actual changes. Chart transitions depend on measured counts or
sample identities, not the wall-clock refresh tick. Selection emphasis is
synchronized between the two exchange charts.

Respect the system Reduce Motion preference. When it is enabled, the
custom animation policy returns nil and animated content transitions use
identity where applicable. The animation policy never starts, cancels,
joins, or delays a task. No repeating animation simulates a packet stream.

Native controls, textual phase and outcome labels, exact numeric values,
keyboard-accessible Pickers, and chart accessibility descriptions provide
alternatives to movement and color. Liquid Glass is reserved for native
navigation and interaction; reading and chart surfaces remain opaque.

Manual review is still required with VoiceOver, Full Keyboard Access,
Increase Contrast, Reduce Transparency, Reduce Motion, light and dark
appearance, and compact windows.
