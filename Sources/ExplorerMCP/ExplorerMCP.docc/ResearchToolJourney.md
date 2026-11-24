# Research tool journey

Use the same four tools through the real SDK server and client.

## Overview

The client calls `server/discover` and `tools/list`, with a limit of eight
catalogue pages during preparation. It requires all four tools and their
output schemas. The subsequent workflow is:

| Tool | Contract |
| --- | --- |
| search_articles | Returns bounded candidates in the selected project. |
| get_article_outline | Returns a pinned revision and its section locations. |
| read_article_section | Reads from the exact requested snapshot and part. |
| get_section_references | Returns associated reference metadata and unresolved identifiers. |

The public SDK validates structured output using the advertised schema.
The adapter decodes the structured envelope and checks its identity.
A received transport response does not establish successful validation.
Owned domain problems remain distinct from JSON-RPC rejection, invalid
responses, identity mismatch, transport failure and cancellation.

The optional tool observer wraps eligible catalogue handlers. It is not
a general HTTP request logger, packet capture or connection monitor.
