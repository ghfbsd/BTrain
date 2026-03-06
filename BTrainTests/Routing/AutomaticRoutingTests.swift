// Copyright 2021-22 Jean Bovet
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

@testable import BTrain
import XCTest

class AutomaticRoutingTests: BTTestCase {
    override var speedChangeRequestCeiling: Int? {
        17
    }

    func testUpdateAutomaticRoute() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s1 = layout.blocks[Identifier<Block>(uuid: "s1")]!

        let p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        try p.assert("automatic-0: {r0{s1 ◼︎0 ≏ 🔵►0 }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {s2 ≏ }", ["b1"])

        // Let's put another train in b2 and b5, resulting in no possible path forward
        layout.reserve("b2", with: "1", direction: .next)
        layout.reserve("b5", with: "1", direction: .next)

        try p.assert("automatic-0: {r0{s1 ◼︎0 ≏ 🔵►0 }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [r1[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {s2 ≏ }", ["b1"])

        // Move s1 -> b1
        p.toggle("fb1")

        // The controller will generate a new automatic route because "b2" is occupied.
        // However, the resulting route is empty because there is no route possible without avoiding b2.
        try p.assert("automatic-0:", [])

        XCTAssertEqual(p.train.state, .stopped)
        XCTAssertEqual(p.train.scheduling, .managed)

        // Let's remove the occupation of b2
        layout.free("b2")
        p.layoutController.runControllers(.trainPositionChanged(p.train))

        // Train restarts with a new route
        try p.assert("automatic-0: [r0[b1 ◼︎0 ≏ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {s2 ≏ }", ["b2"])

        // Move b1 -> b2
        try p.assert("automatic-0: [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]] <t5> <t6> {s2 ≏ }", ["b3"])

        // Move b2 -> b3
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🔵►0 ≏ ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}", ["s2"])
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}", ["s2"])
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔵►0 ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}", ["s2"])

        // Move b3 -> s2
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≡ 🔴►0 }}", [])

        // The train is still running because the route is .endless
        XCTAssertEqual(p.train.scheduling, .managed)
    }

    func testUpdateAutomaticRouteWithReservedTurnout() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let s1 = layout.block(named: "s1")

        // The route will choose "s2" as the arrival block
        var p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .custom(index: 1), routeSteps: ["s1:next", "b1:next", "s2:next"])

        try p.assert("automatic-0: {r0{s1 ◼︎0 ≏ 🔵►0 ≏ }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ≏ ≏ ]] <t4{sl}(1,0),s> {s2 ≏ ≏ }")

        p.stop()

        // Note: the train the stops only after triggering the stop feedback of the block.
        try p.assert("automatic-0: {r0{s1 ≏ ◼︎0 ≡ 🔴►0 }} <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ] <t4{sl}(1,0),s> {s2 ≏ ≏ }")

        // Let's artificially reserve turnout t2. This should cause the automatic route to be re-evaluated to find an alternate path
        layout.turnout(named: "t2").reserved = .init(train: .init(uuid: "7"), sockets: .init(fromSocketId: 0, toSocketId: 1))

        p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b2:next", "b3:next", "s2:next"])

        try p.assert("automatic-0: {r0{s1 ≏ ◼︎0 ≏ 🔵►0 }} <r0<t1{sr}(0,2),r>> [r0[b2 ≏ ≏ ]] <t3{sr}(1,0),s> [b3 ≏ ≏ ] <t4{sl}(2,0),s> {s2 ≏ ≏ }")
    }

    func testUpdateAutomaticRouteWithBlockToAvoid() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s1 = layout.blocks[Identifier<Block>(uuid: "s1")]!
        let train = layout.trains[0]

        // The route will choose "s2" as the arrival block
        var p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "b2:next", "b3:next", "s2:next"])
        p.toggle("fs1") // allows the train to stops by indicating that the stop feedback has been triggered
        p.stop(drainAll: true)

        // Let's mark "s2" as to avoid
        train.blocksToAvoid.append(.init(Identifier<Block>(uuid: "s2")))

        // The route will choose "s1" instead
        p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "b2:next", "b3:next", "s1:next"])
        p.stop(drainAll: true)

        // Now let's mark also "s1" as to avoid
        train.blocksToAvoid.append(.init(Identifier<Block>(uuid: "s1")))

        // There will be no possible route to find
        p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, expectedState: .stopped, routeSteps: [])
        XCTAssertEqual(p.route.steps.count, 0)
    }

    func testAutomaticRouteWithTurnoutToAvoid() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s1 = layout.blocks[Identifier<Block>(uuid: "s1")]!

        // The route will choose "s2" as the arrival block
        var p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "b2:next", "b3:next", "s2:next"])
        p.toggle("fs1") // allows the train to stops by indicating that the stop feedback has been triggered
        p.stop(drainAll: true)

        // Let's mark "t5" as to avoid
        layout.trains[0].turnoutsToAvoid.append(.init(Identifier<Turnout>(uuid: "t5")))

        // No route is possible with t5 to avoid
        p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, expectedState: .stopped, routeSteps: [])
        XCTAssertEqual(p.route.steps.count, 0)
    }

    // This test ensures that the algorithm finds an alternative free path when multiple paths are available
    // to reach the same block but one of the path is reserved. "Layout Complex" will be used with the following scenario:
    // OL3 to NE3:
    // There are two direct paths that exist:
    // (1) OL3 > F.3 > F.1 > F.2 > M.1 > C.1 > C.3 > NE3
    // (2) OL3 > F.3 > F.1 > F.2 > C.3 > NE3
    // Path (1) is chosen first because it is the most natural one.
    // However, if M.1 is reserved, for example, then path (2) should be found.
    func testAutomaticRouteWithAlternateRoute() throws {
        let layout = LayoutComplex().newLayout().removeTrains()

        let train = layout.trains[0]
        let ol3 = layout.block("OL3")
        let ne3 = layout.block("NE3")

        let routeId = Route.automaticRouteId(for: train.id)
        let route = layout.route(for: routeId, trainId: train.id)!
        route.steps = [.block(RouteItemBlock(ol3, .next)), .block(RouteItemBlock(ne3, .next))]

        let m1 = layout.turnout("M.1")
        m1.reserved = .init(train: Identifier<Train>(uuid: "foo"), sockets: nil)

        let p = try setup(layout: layout, fromBlockId: ol3.id, destination: .init(ne3.id, direction: .next), position: .end, routeSteps: ["OL3:next", "NE3:next"])
        try p.assert("automatic-16390: [r16390[OL3 ◼︎16390 ≏ ◻︎16390 ≏ 🔵►16390 ]] <r16390<F.3{sr}(0,1),s>> <r16390<F.1{sr}(0,1),s>> <r16390<F.2{sr}(0,2),r>> <r16390<C.3{sr}(1,0),s>> {r16390{NE3 ≏ ≏ }}")
    }

    func testAutomaticRouteNoRouteToSiding() throws {
        let layout = LayoutPointToPoint().newLayout()

        // There is no automatic route possible because there are no stations but only two siding blocks at each end of the route.
        // This will be supported in the future for certain type of train.
        let p = try setup(layout: layout, fromBlockId: Identifier<Block>(uuid: "A"), destination: nil, position: .end, expectedState: .stopped, routeSteps: [])
        XCTAssertEqual(p.route.steps.count, 0)
    }

    func testAutomaticRouteFinishing() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s1 = layout.blocks[Identifier<Block>(uuid: "s1")]!

        let p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        try p.assert("automatic-0: {r0{s1 ◼︎0 ≏ 🔵►0 }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }")

        p.finish()
        XCTAssertEqual(p.train.scheduling, .finishManaged)

        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🔵►0 ≏ ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔵►0 ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≡ 🔴►0 }}")

        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testFinishingDoesNotStopUntilEndOfRoute() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s1 = layout.blocks[Identifier<Block>(uuid: "s1")]!

        let p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        try p.assert("automatic-0: {r0{s1 ◼︎0 ≏ 🔵►0 }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")

        // Let's put another train in b2 and b5
        layout.reserve("b2", with: "1", direction: .next)
        layout.reserve("b5", with: "1", direction: .next)

        // Indicate that we want the train to finish once the route is completed
        p.finish()
        XCTAssertEqual(p.train.scheduling, .finishManaged)

        try p.assert("automatic-0: {r0{s1 ◼︎0 ≏ 🔵►0 }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [r1[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")

        // Move s1 -> b1
        p.toggle("fb1")

        // The controller will generate a new automatic route because "b2" is occupied.
        // However, the resulting route is empty because there is no route possible without avoiding b2.
        try p.assert("automatic-0:", [])

        // Let's remove the occupation of b2
        layout.free("b2")
        p.layoutController.runControllers(.trainPositionChanged(p.train))

        // Train restarts with a new route
        try p.printASCII()
        try p.assert("automatic-0: [r0[b1 ◼︎0 ≏ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {s2 ≏ }", ["b2"])

        // Move b1 -> b2
        try p.assert("automatic-0: [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]] <t5> <t6> {s2 ≏ }", ["b3"])

        // Move b2 -> b3
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🔵►0 ≏ ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}", ["s2"])
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}", ["s2"])
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔵►0 ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}", ["s2"])

        // Move b3 -> s2
        try p.assert("automatic-0: [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≡ 🔴►0 }}", [])

        // The train has stopped because it has been asked to finish the route
        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testAutomaticRouteStationRestart() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!

        let p = try setup(layout: layout, fromBlockId: s2.id, destination: nil, position: .end, routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        // Duplicate this test with leading blocks to 2 to see how the speed changes
        //        p.train.maxNumberOfLeadingReservedBlocks = 2

        try p.assert("automatic-0: {r0{s2 ◼︎0 ≏ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≏ 🔵►0 }}")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🔵►0 ≏ ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔵►0 ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔴►0 }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≡ 🔴►0 }}")

        // Artificially set the restart time to 0 which will make the train restart again
        p.layoutController.restartTimerFired(layout.trains[0])
        p.layoutController.waitUntilSettled()

        XCTAssertGreaterThan(p.loc.speed.requestedKph, 0)

        // When restarting, the train automatic route will be updated
        XCTAssertEqual(p.route.steps.toStrings(layout), ["s2:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        // Assert that the train has restarted and is moving in the correct direction
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≏ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≏ 🔵►0 }}")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {s2 ≏ }")
    }

    func testAutomaticRouteStationRestartFinishing() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!

        let p = try setup(layout: layout, fromBlockId: s2.id, destination: nil, position: .end, routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        try p.assert("automatic-0: {r0{s2 ◼︎0 ≏ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≏ 🔵►0 }}")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🔵►0 ≏ ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔵►0 ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔴►0 }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≡ 🔴►0 }}")

        // Simulate the user tapping on the "Finish" button while the timer counts down
        p.finish()
        XCTAssertEqual(p.train.scheduling, .finishManaged)

        // Artificially set the restart time to 0 which will make the train restart again
        p.layoutController.restartTimerFired(p.train)

        // Make sure the train is not moving because we requested to finish the route!
        XCTAssertTrue(p.loc.speed.requestedKph == 0)

        // Make sure the route hasn't changed
        XCTAssertEqual(p.route.steps.toStrings(layout), ["s2:next", "b1:next", "b2:next", "b3:next", "s2:next"])
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔴►0 }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≡ 🔴►0 }}")
    }

    /// Same as ``testAutomaticRouteStationRestartFinishing`` but with a station block with 2 feedbacks (s2) that simulates
    /// a stop that includes a ``LayoutControllerEvent/movedInsideBlock`` event which exhibit different code path.
    func testAutomaticRouteStationRestartFinishing2() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let s1 = layout.block(named: "s1")

        // The route will choose "s2" as the arrival block
        let p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "s2:next"])

        try p.assert("automatic-0: {r0{s1 ≏ ◼︎0 ≏ 🔵►0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ≏ ≏ ]] <t4{sl}(1,0),s> {s2 ≏ ≏ }")
        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ◼︎0 ≡ 🔵►0 ≏ ]] <r0<t4{sl}(1,0),s>> {r0{s2 ≏ ≏ }}")
        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ≏ ◼︎0 ≡ 🔵►0 ]] <r0<t4{sl}(1,0),s>> {r0{s2 ≏ ≏ }}")
        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ] <t4{sl}(1,0),s> {r0{s2 ◼︎0 ≡ 🟡►0 ≏ }}")
        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ] <t4{sl}(1,0),s> {r0{s2 ≏ ◼︎0 ≡ 🔴►0 }}")

        // Simulate the user tapping on the "Finish" button while the timer counts down
        p.finish()
        XCTAssertEqual(p.train.scheduling, .finishManaged)

        // Artificially set the restart time to 0 which will make the train restart again
        p.layoutController.restartTimerFired(p.train)

        // Make sure the train is not moving because we requested to finish the route!
        XCTAssertTrue(p.loc.speed.requestedKph == 0)

        // Make sure the route hasn't changed
        XCTAssertEqual(p.route.steps.toStrings(layout), ["s1:next", "b1:next", "s2:next"])

        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ] <t4{sl}(1,0),s> {r0{s2 ≏ ◼︎0 ≡ 🔴►0 }}")
    }

    func testAutomaticRouteStationRestartWhenStoppingInPreviousBlock() throws {
        let layout = LayoutComplex().newLayout().removeTrains()
        let ne4 = layout.blocks[Identifier<Block>(uuid: "NE4")]!
        let train = layout.trains[1]
        train.wagonsLength = nil
        train.maxNumberOfLeadingReservedBlocks = 1

        let loc = train.locomotive!
        loc.length = nil
        loc.directionForward = true

        let p = try setup(layout: layout, train: train, fromBlockId: ne4.id, destination: nil, position: .end, direction: .previous, routeSteps: ["NE4:previous", "M1:next", "M2U:next", "LCF1:next"])

        XCTAssertTrue(train.timeUntilAutomaticRestart == 0)

        try p.assert("automatic-16405: !{r16405{NE4 🟢►16405 ≏ ≏ }} <r16405<C.1{tw}(1,0),s>> <r16405<M.1{sl}(0,1),s>> [r16405[M1 ≏ ≏ ≏ ]] <Z.1{sr}(0,1),s> [M2U ≏ ] <Z.2{sl}(1,0),s> <Z.4{sl}(0,1),l> {LCF1 ≏ ≏ }")
        try p.assert("automatic-16405: !{NE4 ≏ ≏ } <C.1{tw}(1,0),s> <M.1{sl}(0,1),s> [r16405[M1 ≡ 🟢►16405 ≏ ≏ ]] <r16405<Z.1{sr}(0,1),s>> [r16405[M2U ≏ ]] <Z.2{sl}(1,0),s> <Z.4{sl}(0,1),l> {LCF1 ≏ ≏ }")

        XCTAssertEqual(train.state, .running)
        p.digitalController.pause()

        // Stop request should happen in M2U but the actual stopping of the train should
        // only happen in LCF1, where the restart time should be triggered because LCF1 is a station.
        try p.assert("automatic-16405: !{NE4 ≏ ≏ } <C.1{tw}(1,0),s> <M.1{sl}(0,1),s> [M1 ≏ ≏ ≏ ] <Z.1{sr}(0,1),s> [r16405[M2U ≡ 🔴►16405 ]] <r16405<Z.2{sl}(1,0),s>> <r16405<Z.4{sl}(0,1),l>> {r16405{LCF1 ≏ ≏ }}")

        XCTAssertEqual(train.state, .stopping)
        XCTAssertTrue(p.layoutController.pausedTrainTimers.isEmpty)

        try p.assert("automatic-16405: !{NE4 ≏ ≏ } <C.1{tw}(1,0),s> <M.1{sl}(0,1),s> [M1 ≏ ≏ ≏ ] <Z.1{sr}(0,1),s> [M2U ≏ ] <Z.2{sl}(1,0),s> <Z.4{sl}(0,1),l> {r16405{LCF1 ≡ 🔴►16405 ≏ }}")

        p.digitalController.resume()

        p.layoutController.waitUntilSettled()

        XCTAssertEqual(train.state, .stopped)
        XCTAssertFalse(p.layoutController.pausedTrainTimers.isEmpty)
        XCTAssertTrue(train.timeUntilAutomaticRestart > 0)
    }

    func testAutomaticRouteStationRestartCannotUpdateAutomaticRouteImmediately() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!

        let p = try setup(layout: layout, fromBlockId: s2.id, destination: nil, position: .end, routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        try p.assert("automatic-0: {r0{s2 ◼︎0 ≏ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≏ 🔵►0 }}")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🔵►0 ≏ ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ≏ }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔵►0 ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }}")
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔴►0 }} <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≡ 🔴►0 }}")

        // Let's add a train in the next block b1 that will prevent the train in s2 from immediately restarting
        try p.layoutController.setupTrainToBlock(layout.trains[1], Identifier<Block>(uuid: "b1"), naturalDirectionInBlock: .next)
        p.layoutController.runControllers(.trainPositionChanged(layout.trains[1]))

        // Wait until the train route has been updated (which happens when it restarts)
        p.layoutController.restartTimerFired(layout.trains[0])

        // However, in this situation, the route will be empty because a train is blocking the next block
        XCTAssertEqual(p.route.steps.count, 0)

        // Now remove the train from the block b1 in order for the train in s2 to start again properly this time
        try layout.remove(trainId: layout.trains[1].id)
        p.layoutController.runControllers(.trainPositionChanged(layout.trains[0]))

        // When restarting, the train automatic route will be updated
        XCTAssertEqual(p.route.steps.toStrings(layout), ["s2:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        // Assert that the train has restarted and is moving in the correct direction
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≏ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {r0{s2 ◼︎0 ≏ 🔵►0 }}")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
    }

    func testAutomaticRouteModeOnce() throws {
        let layout = LayoutComplexLoop().newLayout()

        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!
        let b3 = layout.blocks[Identifier<Block>(uuid: "b3")]!

        let p = try setup(layout: layout, fromBlockId: s2.id, destination: Destination(b3.id), routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next"])

        try p.assert("automatic-0: {r0{s2 🔵►0 ≏ }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🟡►0 ≏ ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🟡►0 ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔴►0 ]]")

        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testAutomaticRouteModeOnceWithUnreachableDestinationPosition() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!
        let b3 = layout.blocks[Identifier<Block>(uuid: "b3")]!

        // Position 0 is not reachable because when the train enters block b3, it is because the first feedback is detected,
        // which is always position 1. We want to make sure that if that is the case, the TrainController still stops the
        // train when it reaches the end of the block because there is no other block left in the route
        let p = try setup(layout: layout, fromBlockId: s2.id, destination: Destination(b3.id, direction: .next), routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next"])

        try p.assert("automatic-0: {r0{s2 🔵►0 ≏ }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🟡►0 ≏ ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🟡►0 ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔴►0 ]]")

        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testAutomaticRouteModeOnceWithReservedBlock() throws {
        let layout = LayoutComplexLoop().newLayout().removeTrainGeometry()
        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!
        let b3 = layout.blocks[Identifier<Block>(uuid: "b3")]!

        let p = try setup(layout: layout, fromBlockId: s2.id, destination: Destination(b3.id), routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next"])

        try p.assert("automatic-0: {r0{s2 🔵►0 ≏ }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")

        // Let's add a train in the block b2
        try p.layoutController.setupTrainToBlock(layout.trains[1], Identifier<Block>(uuid: "b2"), naturalDirectionInBlock: .next)

        try p.assert("automatic-0: {r0{s2 ≡ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [r1[b2 ≏ 🔴►1 ]] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {r0{s2 ≏ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [r1[b2 ≏ 🔴►1 ]] <t4(1,0)> [b3 ≏ ≏ ≏ ]")

        // Move from s2 to b1, the route is also updated because b2 is occupied
        try p.assert("automatic-0: [r0[b1 ≡ 🔵►0 ]] <r0<t3{sr}(0,2),r>> ![r0[b5 ≏ ]] <t7{sr}(2,0),s> <t5{sr}(2,0),s> ![b3 ≏ ≏ ≏ ]")

        try p.assert("automatic-0: [b1 ≏ ] <t3(0,2),r> ![r0[b5 ≡ 🔵!►0 ]] <r0<t7(2,0),r>> <r0<t5(2,0),r>> ![r0[b3 ≏ ≏ ≏ ]]")
        try p.assert("automatic-0: [b1 ≏ ] <t3(0,2),r> ![b5 ≏ ] <t7(2,0),r> <t5(2,0),r> ![r0[b3 ≡ 🟡!►0 ≏ ≏ ]]")
        try p.assert("automatic-0: [b1 ≏ ] <t3(0,2),r> ![b5 ≏ ] <t7(2,0),r> <t5(2,0),r> ![r0[b3 ≏ ≡ 🟡!►0 ≏ ]]")
        try p.assert("automatic-0: [b1 ≏ ] <t3(0,2),r> ![b5 ≏ ] <t7(2,0),r> <t5(2,0),r> ![r0[b3 ≏ ≏ ≡ 🔴!►0 ]]")

        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testAutomaticRouteModeOnceAndStopBeforeReachingDestination() throws {
        let layout = LayoutComplexLoop().newLayout()

        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!
        let b3 = layout.blocks[Identifier<Block>(uuid: "b3")]!

        let p = try setup(layout: layout, fromBlockId: s2.id, destination: Destination(b3.id), routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next"])

        try p.assert("automatic-0: {r0{s2 🔵►0 ≏ }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]]")

        p.stop()

        XCTAssertEqual(p.train.scheduling, .stopManaged)

        p.layoutController.waitUntilSettled()

        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testAutomaticRouteModeOnceAndFinishBeforeReachingDestination() throws {
        let layout = LayoutComplexLoop().newLayout()

        let s2 = layout.blocks[Identifier<Block>(uuid: "s2")]!
        let b3 = layout.blocks[Identifier<Block>(uuid: "b3")]!

        let p = try setup(layout: layout, fromBlockId: s2.id, destination: Destination(b3.id), routeSteps: ["s2:next", "b1:next", "b2:next", "b3:next"])

        try p.assert("automatic-0: {r0{s2 🔵►0 ≏ }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {r0{s2 ◼︎0 ≡ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]]")

        p.finish()

        XCTAssertEqual(p.train.scheduling, .finishManaged)

        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ◼︎0 ≡ 🟡►0 ≏ ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ◼︎0 ≡ 🟡►0 ≏ ]]")
        try p.assert("automatic-0: {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ◼︎0 ≡ 🔴►0 ]]")

        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testEmergencyStop() throws {
        let layout = LayoutComplexLoop().newLayout()
        let s1 = layout.blocks[Identifier<Block>(uuid: "s1")]!

        let p = try setup(layout: layout, fromBlockId: s1.id, destination: nil, position: .end, routeSteps: ["s1:next", "b1:next", "b2:next", "b3:next", "s2:next"])

        try p.assert("automatic-0: {r0{s1 ◼︎0 ≏ 🔵►0 }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [r0[b1 ◼︎0 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ }")
        try p.assert("automatic-0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }")

        // Trigger an unexpected feedback so the LayoutController does an emergency stop
        try p.assert("automatic-0: {s1 ≡ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≏ 🔴►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }", expectRuntimeError: true)
        try p.assert("automatic-0: {s1 ≡ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≏ 🔴►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }", expectRuntimeError: true)
        try p.assert("automatic-0: {s1 ≡ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ◼︎0 ≏ 🔴►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ }", expectRuntimeError: true)

        // The train must be in stopped state
        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    // MARK: - - Backward

    //    ┌─────────┐                      ┌─────────┐             ┌─────────┐
    //    │   s1    │───▶  t1  ───▶  t2  ─▶│   b1    │─▶  t4  ────▶│   s2    │
    //    └─────────┘                      └─────────┘             └─────────┘
    //         ▲            │         │                    ▲            │
    //         │            │         │                    │            │
    //         │            ▼         ▼                    │            │
    //         │       ┌─────────┐                    ┌─────────┐       │
    //         │       │   b2    │─▶ t3  ────────────▶│   b3    │       │
    //         │       └─────────┘                    └─────────┘       ▼
    //    ┌─────────┐                                              ┌─────────┐
    //    │   b5    │◀─────────────────────────────────────────────│   b4    │
    //    └─────────┘                                              └─────────┘

    /// Test that a locomotive that does not support going backward will not move when a route that requires
    /// it to go backward is chosen. The route path finder will fail to find a path for the train and the train won't move.
    func testBackwardRouteWithLocomotiveThatDontGoBackward() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let s1 = layout.block(named: "s1")
        let s2 = layout.block(named: "s2")

        let t1 = layout.trains[0]
        t1.locomotive!.directionForward = true
        t1.locomotive!.allowedDirections = .forward

        _ = try setup(layout: layout, fromBlockId: s1.id, destination: .init(s2.id, direction: .next), position: .end, direction: .previous, expectedState: .stopped, routeSteps: [])
    }

    func testBackwardRoute() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let s1 = layout.block(named: "s1")
        let s2 = layout.block(named: "s2")

        let t1 = layout.trains[0]
        t1.locomotive!.length = 20
        t1.wagonsLength = s1.length! - 60

        t1.locomotive!.directionForward = false
        t1.locomotive!.allowedDirections = .any
        t1.isTailDetected = true

        // s1: [ >---- ]>
        let p = try setup(layout: layout, fromBlockId: s1.id, destination: .init(s2.id, direction: .next), position: .automatic, direction: .next, routeSteps: ["s1:next", "b1:next", "s2:next"])

        // The route requires the train to move backward
        XCTAssertFalse(t1.directionForward)
        XCTAssertEqual(s1.trainInstance?.direction, .next)

        try p.assert("automatic-0: {r0{s1 ≏ 🔵!►⟷0 ≏ ◼︎0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ≏ ≏ ]] <t4{sl}(1,0),s> {s2 ≏ ≏ }", ["b1"])

        try p.assert("automatic-0: {r0{s1 ≏ 🔵!►⟷0 ≡ ◼︎0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ≏ ≏ ]] <t4{sl}(1,0),s> {s2 ≏ ≏ }", ["b1"])

        try p.assert("automatic-0: {r0{s1 ≏ ≏ 🔵!►⟷0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ◻︎0 ≡ ◼︎0 ≏ ]] <r0<t4{sl}(1,0),s>> {r0{s2 ≏ ≏ }}", ["s2"])

        try p.assert("automatic-0: {r0{s1 ≏ ≏ 🔵!►⟷0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ◻︎0 ≡ ◼︎0 ≏ ]] <r0<t4{sl}(1,0),s>> {r0{s2 ≏ ≏ }}", ["s2"])

        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ≏ 🟡!►⟷0 ≏ ◻︎0 ]] <r0<t4{sl}(1,0),s>> {r0{s2 ◻︎0 ≡ ◼︎0 ≏ }}", [])

        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ] <t4{sl}(1,0),s> {r0{s2 ≏ 🔴!►⟷0 ≡ ◼︎0 }}", [])

        XCTAssertEqual(p.train.state, .stopped)

        // Start the train to go back to s1, by reversing its direction
        try p.start(destination: Destination(s1.id, direction: .previous), expectedState: .running, routeSteps: ["s2:previous", "b1:previous", "s1:previous"])

        try p.assert("automatic-0: !{r0{s2 ≏ ◼︎0 ≡ 🔵!►0 }} <r0<t4{sl}(0,1),s>> ![r0[b1 ≏ ≏ ]] <t2{sr}(1,0),s> <t1{sr}(1,0),s> !{s1 ≏ ≏ }", ["b1"])

        try p.assert("automatic-0: !{r0{s2 ≏ ◼︎0 ≏ ◻︎0 }} <r0<t4{sl}(0,1),s>> ![r0[b1 ◻︎0 ≡ 🔵!►0 ≏ ]] <r0<t2{sr}(1,0),s>> <r0<t1{sr}(1,0),s>> !{r0{s1 ≏ ≏ }}", ["s1"])

        // Trigger a feedback near the back of the train, this feedback should be ignored (because it is
        // behind the front position of the train) and it won't be un-expected because it is located in
        // a block where the train is located (and because the train can move in any direction, it can
        // have a magnet at the rear of the train).
        try p.assert("automatic-0: !{r0{s2 ≏ ◼︎0 ≡ ◻︎0 }} <r0<t4{sl}(0,1),s>> ![r0[b1 ◻︎0 ≏ 🔵!►0 ≏ ]] <r0<t2{sr}(1,0),s>> <r0<t1{sr}(1,0),s>> !{r0{s1 ≏ ≏ }}", ["s1"])

        try p.assert("automatic-0: !{s2 ≏ ≏ } <t4{sl}(0,1),s> ![r0[b1 ≏ ≏ ◼︎0 ]] <r0<t2{sr}(1,0),s>> <r0<t1{sr}(1,0),s>> !{r0{s1 ◻︎0 ≡ 🟡!►0 ≏ }}", [])

        try p.assert("automatic-0: !{s2 ≏ ≏ } <t4{sl}(0,1),s> ![b1 ≏ ≏ ] <t2{sr}(1,0),s> <t1{sr}(1,0),s> !{r0{s1 ≏ ◼︎0 ≡ 🔴!►0 }}", [])

        XCTAssertEqual(p.train.state, .stopped)
    }

    func testBackwardRoute_HeadOnly() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let s1 = layout.block(named: "s1")
        let s2 = layout.block(named: "s2")

        let t1 = layout.trains[0]
        t1.locomotive!.length = 20
        t1.wagonsLength = s1.length! - 60

        t1.locomotive!.directionForward = false
        t1.locomotive!.allowedDirections = .any
        t1.isTailDetected = false

        // s1: [ >---- ]>
        let p = try setup(layout: layout, fromBlockId: s1.id, destination: .init(s2.id, direction: .next), position: .automatic, direction: .next, routeSteps: ["s1:next", "b1:next", "s2:next"])

        // The route requires the train to move backward
        XCTAssertFalse(t1.directionForward)
        XCTAssertEqual(s1.trainInstance?.direction, .next)

        try p.assert("automatic-0: {r0{s1 ≏ 🔵!►⟷0 ≏ ◼︎0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ≏ ≏ ]] <t4{sl}(1,0),s> {s2 ≏ ≏ }", ["b1"])

        try p.assert("automatic-0: {r0{s1 ≏ ≡ 🟢!►0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ◼︎{10.001}0 ≏ ≏ ]] <r0<t4{sl}(1,0),s>> {r0{s2 ≏ ≏ }}", ["s2"])

        try p.assert("automatic-0: {r0{s1 ≏ ≡ 🟢!►0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ◼︎{10.001}0 ≏ ≏ ]] <r0<t4{sl}(1,0),s>> {r0{s2 ≏ ≏ }}", ["s2"])

        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ≡ 🔵!►0 ≏ ◼︎0 ]] <r0<t4{sl}(1,0),s>> {r0{s2 ≏ ≏ }}", ["s2"])

        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ≏ ≡ 🟡!►0 ]] <r0<t4{sl}(1,0),s>> {r0{s2 ◻︎0 ≏ ◼︎{25.001}0 ≏ }}", [])

        try p.assert("automatic-0: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ] <t4{sl}(1,0),s> {r0{s2 ≡ 🔴!►0 ≏ ◼︎0 }}", [])

        XCTAssertEqual(p.train.state, .stopped)

        // Start the train to go back to s1, by reversing its direction
        try p.start(destination: Destination(s1.id, direction: .previous), expectedState: .running, routeSteps: ["s2:previous", "b1:previous", "s1:previous"])

        try p.assert("automatic-0: !{r0{s2 ≏ ◼︎0 ≡ 🔵!►0 }} <r0<t4{sl}(0,1),s>> ![r0[b1 ≏ ≏ ]] <t2{sr}(1,0),s> <t1{sr}(1,0),s> !{s1 ≏ ≏ }", ["b1"])

        try p.assert("automatic-0: !{r0{s2 ≏ ◼︎0 ≏ ◻︎0 }} <r0<t4{sl}(0,1),s>> ![r0[b1 ◻︎0 ≡ 🔵!►0 ≏ ]] <r0<t2{sr}(1,0),s>> <r0<t1{sr}(1,0),s>> !{r0{s1 ≏ ≏ }}", ["s1"])

        // Trigger a feedback near the back of the train, this feedback should be ignored (because it is
        // behind the front position of the train) and it won't be un-expected because it is located in
        // a block where the train is located (and because the train can move in any direction, it can
        // have a magnet at the rear of the train).
        try p.assert("automatic-0: !{r0{s2 ≏ ◼︎0 ≡ ◻︎0 }} <r0<t4{sl}(0,1),s>> ![r0[b1 ◻︎0 ≏ 🔵!►0 ≏ ]] <r0<t2{sr}(1,0),s>> <r0<t1{sr}(1,0),s>> !{r0{s1 ≏ ≏ }}", ["s1"])

        try p.assert("automatic-0: !{s2 ≏ ≏ } <t4{sl}(0,1),s> ![r0[b1 ≏ ≏ ◼︎0 ]] <r0<t2{sr}(1,0),s>> <r0<t1{sr}(1,0),s>> !{r0{s1 ◻︎0 ≡ 🟡!►0 ≏ }}", [])

        try p.assert("automatic-0: !{s2 ≏ ≏ } <t4{sl}(0,1),s> ![b1 ≏ ≏ ] <t2{sr}(1,0),s> <t1{sr}(1,0),s> !{r0{s1 ≏ ◼︎0 ≡ 🔴!►0 }}", [])

        XCTAssertEqual(p.train.state, .stopped)
    }

    //    ┌─────────┐                      ┌─────────┐             ┌─────────┐
    //    │   s1    │───▶  t1  ───▶  t2  ─▶│   b1    │─▶  t4  ────▶│   s2    │
    //    └─────────┘                      └─────────┘             └─────────┘
    //         ▲            │         │                    ▲            │
    //         │            │         │                    │            │
    //         │            ▼         ▼                    │            │
    //         │       ┌─────────┐                    ┌─────────┐       │
    //         │       │   b2    │─▶ t3  ────────────▶│   b3    │       │
    //         │       └─────────┘                    └─────────┘       ▼
    //    ┌─────────┐                                              ┌─────────┐
    //    │   b5    │◀─────────────────────────────────────────────│   b4    │
    //    └─────────┘                                              └─────────┘
    func testMoveForwardAndChangeToBackward() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let train = layout.trains[0]
        train.locomotive!.allowedDirections = .any
        train.isTailDetected = true
        train.locomotive?.length = 20
        train.wagonsLength = 0

        // Note: the train is layout in the s2 in the direction .next but the route will find the shortest path to s2 which requires the train to move backward
        let p = try setup(layout: layout, fromBlockId: layout.block(named: "s2").id, destination: nil, position: .automatic, direction: .next, routeSteps: ["s2:next", "b4:next", "b5:next", "s1:next"])

        // ******************
        // **** s2 -> s1 ****
        // ******************

        try p.assert("automatic-0: {r0{s2 ≏ ◼︎0 ≏ 🔵►0 }} [r0[b4 ≏ ≏ ]] [b5 ≏ ≏ ] {s1 ≏ ≏ }", ["b4"])
        try p.assert("automatic-0: {s2 ≏ ≏ } [r0[b4 ◼︎0 ≡ 🔵►0 ≏ ]] [r0[b5 ≏ ≏ ]] {s1 ≏ ≏ }", ["b5"])
        try p.assert("automatic-0: {s2 ≏ ≏ } [b4 ≏ ≏ ] [r0[b5 ◼︎0 ≡ 🔵►0 ≏ ]] {r0{s1 ≏ ≏ }}", ["s1"])
        try p.assert("automatic-0: {s2 ≏ ≏ } [b4 ≏ ≏ ] [b5 ≏ ≏ ] {r0{s1 ◼︎0 ≡ 🟡►0 ≏ }}", [])
        try p.assert("automatic-0: {s2 ≏ ≏ } [b4 ≏ ≏ ] [b5 ≏ ≏ ] {r0{s1 ≏ ◼︎0 ≡ 🔴►0 }}", [])

        // Artificially set the restart time to 0 which will make the train restart again
        p.layoutController.restartTimerFired(train)
        p.layoutController.waitUntilSettled()

        // ******************
        // **** s1 -> s2 ****
        // ******************

        // Note: because the train changed direction inside s1, the position of the tail cannot be represented
        // accurately with the ASCII representation which is why the distance of the tail is specified.
        try p.assert("automatic-0: !{r0{s1 🔵!►0 ≏ ◼︎{60.001}0 ≏ }} ![r0[b5 ≏ ≏ ]] ![b4 ≏ ≏ ] !{s2 ≏ ≏ }", ["b5"])
        try p.assert("automatic-0: !{r0{s1 ≏ 🔵!►0 ≡ ◼︎0 }} ![r0[b5 ≏ ≏ ]] ![b4 ≏ ≏ ] !{s2 ≏ ≏ }", ["b5"])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![r0[b5 🔵!►0 ≡ ◼︎0 ≏ ]] ![r0[b4 ≏ ≏ ]] !{s2 ≏ ≏ }", ["b4"])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![b5 ≏ ≏ ] ![r0[b4 🔵!►0 ≡ ◼︎0 ≏ ]] !{r0{s2 ≏ ≏ }}", ["s2"])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![b5 ≏ ≏ ] ![b4 ≏ ≏ ] !{r0{s2 🟡!►0 ≡ ◼︎0 ≏ }}", [])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![b5 ≏ ≏ ] ![b4 ≏ ≏ ] !{r0{s2 ≏ 🔴!►0 ≡ ◼︎0 }}", [])

        // Artificially set the restart time to 0 which will make the train restart again
        p.layoutController.restartTimerFired(train)
        p.layoutController.waitUntilSettled()

        // ******************
        // **** s2 -> s1 ****
        // ******************

        try p.assert("automatic-0: {r0{s2 ◼︎0 ≏ 🔵►{39.999}0 ≏ }} [r0[b4 ≏ ≏ ]] [b5 ≏ ≏ ] {s1 ≏ ≏ }", ["b4"])
        try p.assert("automatic-0: {s2 ≏ ≏ } [r0[b4 ◼︎0 ≡ 🔵►0 ≏ ]] [r0[b5 ≏ ≏ ]] {s1 ≏ ≏ }", ["b5"])
        try p.assert("automatic-0: {s2 ≏ ≏ } [b4 ≏ ≏ ] [r0[b5 ◼︎0 ≡ 🔵►0 ≏ ]] {r0{s1 ≏ ≏ }}", ["s1"])
        try p.assert("automatic-0: {s2 ≏ ≏ } [b4 ≏ ≏ ] [b5 ≏ ≏ ] {r0{s1 ◼︎0 ≡ 🟡►0 ≏ }}", [])
        try p.assert("automatic-0: {s2 ≏ ≏ } [b4 ≏ ≏ ] [b5 ≏ ≏ ] {r0{s1 ≏ ◼︎0 ≡ 🔴►0 }}", [])

        // Artificially set the restart time to 0 which will make the train restart again
        p.layoutController.restartTimerFired(train)
        p.layoutController.waitUntilSettled()

        // ******************
        // **** s1 -> s2 ****
        // ******************

        // Note: because the train changed direction inside s1, the position of the tail cannot be represented
        // accurately with the ASCII representation which is why the distance of the tail is specified.
        try p.assert("automatic-0: !{r0{s1 🔵!►0 ≏ ◼︎{60.001}0 ≏ }} ![r0[b5 ≏ ≏ ]] ![b4 ≏ ≏ ] !{s2 ≏ ≏ }", ["b5"])
        try p.assert("automatic-0: !{r0{s1 ≏ 🔵!►0 ≡ ◼︎0 }} ![r0[b5 ≏ ≏ ]] ![b4 ≏ ≏ ] !{s2 ≏ ≏ }", ["b5"])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![r0[b5 🔵!►0 ≡ ◼︎0 ≏ ]] ![r0[b4 ≏ ≏ ]] !{s2 ≏ ≏ }", ["b4"])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![b5 ≏ ≏ ] ![r0[b4 🔵!►0 ≡ ◼︎0 ≏ ]] !{r0{s2 ≏ ≏ }}", ["s2"])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![b5 ≏ ≏ ] ![b4 ≏ ≏ ] !{r0{s2 🟡!►0 ≡ ◼︎0 ≏ }}", [])
        try p.assert("automatic-0: !{s1 ≏ ≏ } ![b5 ≏ ≏ ] ![b4 ≏ ≏ ] !{r0{s2 ≏ 🔴!►0 ≡ ◼︎0 }}", [])
    }

    //    ┌─────────┐                      ┌─────────┐             ┌─────────┐
    //    │   s1    │───▶  t1  ───▶  t2  ─▶│   b1    │─▶  t4  ────▶│   s2    │
    //    └─────────┘                      └─────────┘             └─────────┘
    //         ▲            │         │                    ▲            │
    //         │            │         │                    │            │
    //         │            ▼         ▼                    │            │
    //         │       ┌─────────┐                    ┌─────────┐       │
    //         │       │   b2    │─▶ t3  ────────────▶│   b3    │       │
    //         │       └─────────┘                    └─────────┘       ▼
    //    ┌─────────┐                                              ┌─────────┐
    //    │   b5    │◀─────────────────────────────────────────────│   b4    │
    //    └─────────┘                                              └─────────┘
    func testMoveForwardAndChangeToBackwardInMiddleOfRoute() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let train = layout.trains[0]
        train.locomotive!.allowedDirections = .any
        train.locomotive?.length = 20
        // TODO: do the same test with this turned to false
        train.isTailDetected = true
        train.wagonsLength = 0

        // Note: the train is layout in the s2 in the direction .next but the route will find the shortest path to s2 which requires the train to move backward
        let p = try setup(layout: layout, fromBlockId: layout.block(named: "s2").id, destination: nil, position: .automatic, direction: .next, routeSteps: ["s2:next", "b4:next", "b5:next", "s1:next"])

        // ******************
        // **** s2 -> s1 ****
        // ******************

        try p.assert("automatic-0: {r0{s2 ≏ ◼︎0 ≏ 🔵►0 }} [r0[b4 ≏ ≏ ]] [b5 ≏ ≏ ] {s1 ≏ ≏ }", ["b4"])

        let b5 = layout.block(named: "b5")
        try p.layoutController.setupTrainToBlock(layout.trains[1], b5.id, naturalDirectionInBlock: .next)
        p.layoutController.runControllers(.trainPositionChanged(layout.trains[1]))

        try p.assert("automatic-0: {r0{s2 ≏ ◼︎0 ≏ 🔵►0 }} [r0[b4 ≏ ≏ ]] [r1[b5 ≏ ◼︎1 ≏ 🔴►1 ]] {s1 ≏ ≏ }", ["b4"])

        // Note: because s2 is reserved by another train, the route for `train` is updated to drive the train
        // back to s2 because the train can move backwards.
        try p.assert("automatic-0: ![r0[b4 ≏ 🟡►0 ≡ ◼︎0 ]] !{r0{s2 ≏ ≏ }}", ["s2"])

        // Pause the change in direction command acknowledgement in order to verify the state of the train before
        // it actually changes direction.
        p.digitalController.pauseChangeInDirection = true
        try p.assert("automatic-0: ![r0[b4 🔴►0 ≡ ◼︎0 ≏ ]] !{s2 ≏ ≏ }", [])

        // Resume the change in direction command, at which point the train will change its direction and restart again
        p.digitalController.pauseChangeInDirection = false
        try p.assert("automatic-0: ![r0[b4 🔵!►0 ≡ ◼︎{60.001}0 ≏ ]] !{r0{s2 ≏ ≏ }}", ["s2"])
    }

    // MARK: - - Utility

    private func setup(layout: Layout, fromBlockId: Identifier<Block>, destination: Destination?, position: Package.Position = .start, direction: Direction = .next, expectedState: Train.State = .running, routeSteps: [String]) throws -> Package {
        try setup(layout: layout, train: layout.trains[0], fromBlockId: fromBlockId, destination: destination, position: position, direction: direction, expectedState: expectedState, routeSteps: routeSteps)
    }

    private func setup(layout: Layout, train: Train, fromBlockId: Identifier<Block>, destination: Destination?, position: Package.Position = .start, direction: Direction = .next, expectedState: Train.State = .running, routeSteps: [String]) throws -> Package {
        let p = Package(layout: layout)
        try p.prepare(trainID: train.uuid, fromBlockId: fromBlockId.uuid, position: position, direction: direction)
        try p.start(destination: destination, expectedState: expectedState, routeSteps: routeSteps)
        return p
    }
}
