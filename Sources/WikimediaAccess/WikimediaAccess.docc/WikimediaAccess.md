# ``WikimediaAccess``

Bounded research providers and the revision-pinned research service.

## Overview

The provider adapter yields owned domain data to the service. The fictional
fixture provider reads the bundled corpus. The live Wikipedia provider is an
explicitly chosen source and does not substitute fictional data on failure.

The service checks candidate and source identity, admits a normalized
revision, and retains it in a bounded snapshot cache. Section/reference
operations use that exact cached revision rather than fetching a replacement.

## Topics

### Service and provider contract

- ``ExplorerService``
- ``ExplorerProvider``
- ``FixtureProvider``
- ``WikipediaProvider``
- <doc:ProviderBoundaries>
