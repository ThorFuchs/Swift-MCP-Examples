# Ownership and privacy

Retain bounded, redacted observations without changing SDK behavior.

## Overview

The server controller owns its actual host run and shutdown transition.
The client controller owns its finite guided task. Cancellation requests
termination; joining is a separate completion observation. A UI wait
deadline does not manufacture a join or release ownership of unsettled work.

The Activity store owns its bounded event collection. It retains at most
2,000 events or 2 MiB, with bounded per-event size and a separate bounded
recent-call sample. Redacted projections omit arguments, bodies, header
values, credentials and arbitrary provider text. The exchange recorder is
ephemeral, per inspected journey and never exported.

The application starts offline without automatically connecting or opening
a listener. HTTP demonstration binds to an explicitly started local
loopback host. It is not an authenticated public resource server.

The current example follows pre-release SDK branches; these docs describe
the current implementation rather than certifying the SDKs for production.
