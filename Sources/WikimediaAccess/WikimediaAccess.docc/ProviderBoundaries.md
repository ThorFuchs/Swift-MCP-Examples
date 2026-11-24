# Provider boundaries

Understand source switching, admission and snapshot ownership.

## Overview

The default provider is the fictional offline collection. Selecting Wikipedia
English is a separate user action; startup does not make a network request.
The service validates the selected project, query and candidate bounds, and
limits provider operations to two admitted operations rather than retaining
an unbounded waiting queue.

The outline operation resolves the candidate, checks the provider's identity
receipt, normalizes or admits the fetched revision, and inserts the resulting
snapshot into its bounded cache. Section and reference calls must name the
same admitted snapshot and part. Cache expiry is surfaced as a failure, not
an implicit update.

Live content is a bounded plain-text projection. Preserve the source URL,
revision, retrieval time, license and unresolved citation metadata. See the
repository's live-source contract and third-party notices for detailed
provider and attribution constraints.
