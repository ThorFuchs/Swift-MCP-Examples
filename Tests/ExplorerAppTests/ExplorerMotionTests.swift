// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import ResearchExplorerApp

struct ExplorerMotionTests {
    @Test func everyMotionRoleHonorsReduceMotion() {
        for role in ExplorerDesign.Motion.Role.allCases {
            #expect(ExplorerDesign.Motion.animation(role, reduceMotion: true) == nil)
            #expect(ExplorerDesign.Motion.animation(role, reduceMotion: false) != nil)
            #expect(role.duration > 0 && role.duration < 0.25)
        }
    }
}
