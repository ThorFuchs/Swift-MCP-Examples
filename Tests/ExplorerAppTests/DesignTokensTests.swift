// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import ResearchExplorerApp

/// Structural guardrails for the editorial system; native screenshots and
/// VoiceOver/contrast checks are required separately before claiming HIG review.
@Suite struct ExplorerDesignTokenTests {
    @Test func spacingScaleIsStrictlyIncreasing() {
        #expect(ExplorerDesign.Space.xxs < ExplorerDesign.Space.xs)
        #expect(ExplorerDesign.Space.xs < ExplorerDesign.Space.sm)
        #expect(ExplorerDesign.Space.sm < ExplorerDesign.Space.md)
        #expect(ExplorerDesign.Space.md < ExplorerDesign.Space.lg)
        #expect(ExplorerDesign.Space.lg < ExplorerDesign.Space.xl)
        #expect(ExplorerDesign.Space.xl < ExplorerDesign.Space.xxl)
    }

    @Test func readingMeasureRemainsInsideContentCanvas() {
        #expect(ExplorerDesign.Layout.articleMaxWidth < ExplorerDesign.Layout.contentMaxWidth)
        #expect(ExplorerDesign.Layout.evidenceWidth > ExplorerDesign.Layout.outlineWidth)
        #expect(ExplorerDesign.Layout.outlineWidth >= 200)
    }
}
