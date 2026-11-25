# ``ExplorerMCP``

Public Swift MCP SDK adapters for the four research tools.

## Overview

The server registers a bounded catalogue for search, outline, section reading
and reference lookup. The client explicitly prepares its catalogue, then
uses the public SDK to exchange messages and validate the advertised output
schemas. The research adapter separately verifies source and revision
identity. The transport owner remains with the caller.

## Topics

### Server and client

- ``ExplorerTools``
- ``ExplorerToolObserver``
- ``MCPResearchClient``
- ``MCPResearchFailure``
- <doc:ResearchToolJourney>

## Knowledge as Resources (R5)

- ``ExplorerKnowledge``

The example's full server registers cache-only resource templates, three prompts and a digest-verified static Research Skill using MCPSkills. The original four-tool catalog remains available as a separate factory. No resource read starts an upstream fetch, and no prompt or skill invokes a model.
