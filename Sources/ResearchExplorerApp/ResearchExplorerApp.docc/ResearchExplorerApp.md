# ``ResearchExplorerApp``

A native macOS 27 research reader and inspectable Swift MCP demonstration.

## Overview

Research Explorer has three workspaces: Research, Server (MCP Machine
Room), and Activity. The reader prioritizes content, identity and evidence.
The Machine Room makes actual SDK behavior visible without changing it.
Activity is the detailed redacted flight recorder.

The presentation uses native SwiftUI navigation, selective Liquid Glass,
semantic dynamic colors, editor-style typography, and Swift Charts. The
default source is fictional and offline. Start the server and guided client
explicitly.

## Topics

### Architecture

- <doc:AppArchitecture>
- <doc:MachineRoomGuide>
- <doc:UnifiedResearch>
- ``AppLifetime``
- ``ExplorerRootView``

### Research and activity

- ``ResearchView``
- ``ArticleReaderView``
- ``ReadingPane``
- ``EvidencePane``
- ``ActivityView``

### Machine Room views

- ``ServerView``
- ``MachineRoomOverview``
- ``RequestActivityChart``
- ``MachineRoomAnalyticsGrid``
- ``MCPJourneyView``
- ``JourneyMilestoneRail``
- ``JourneyExchangeCharts``

### Design and accessibility

- <doc:MotionAndAccessibility>
- <doc:NativeReview>
- ``ExplorerDesign``
- ``ExplorerSettings``
