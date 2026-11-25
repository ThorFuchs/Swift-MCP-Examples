# R5 — Knowledge as MCP Resources

The real local HTTP/stdio server now registers two cache-only Resource Templates, three research prompts and one static MCP Skill via the existing SDK. Four tool names and schemas are unchanged. The server catalog limit rises from 4 to 10 entries (4 tools, 2 templates, 3 prompts, 1 skill-file resource); page size stays 4. The public four-tool catalog factory remains available with its default includeKnowledge=false. The full example's makeServer explicitly enables knowledge.

Resource URI: wre://knowledge/{provider}/{project}/{page}/{revision}/{normalizer}/outline or .../part/{part}/section. The full admitted snapshot identity is mandatory. Only the canonical component grammar is accepted; no URL fetching. Read-only cached projections return application/json resource text. Section text is capped at 4 KiB; inner and outer serialization bounds are charged before encoding, with explicit limit failures. Expiry/mismatch/unsupported historical license returns invalid resource input; never fetch latest. Cache hint is private with zero TTL. The Reader's Evidence panel exposes selectable exact addresses, not a claim that a resource remains cached.

Prompts: explore_topic, compare_concepts, review_evidence; one required topic, at most 256 UTF-8 bytes, owned instructions; no execution or sampling. The actual evidence-research skill is registered via MCPSkills and served as skill://evidence-research/SKILL.md with the SDK's manifest/digest contract. It is static, bounded and never contains user query logs, collected evidence or notes.

MCP Resources are accessible to compatible clients using the existing anonymous local development host only. The two existing packages' revisions remain pinned; the manifest adds existing MCPSkills and MCPSkillsClient product dependencies, not a new external package. No production auth or universal MCP compatibility claim. Native build and real SDK acceptance pending.

## Native qualification

Run `swift test --filter ResearchResourceAddressTests` and `swift test --filter MCPHTTPJourneyTests/knowledgeResourcesPromptsAndSkillOverHTTP`. The latter starts the actual local HTTP host, performs real SDK discovery, template/prompt/resource reads, verifies a skill with MCPSkillsClient, and tests expired and malformed resource errors. Tool handler metrics must remain at two (search and outline), and cleanup must join. Native execution is pending.
