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

import XCTest

@testable import BTrain

class FixedRoutingTests: BTTestCase {
    override var speedChangeRequestCeiling: Int? {
        25
    }

    func testBlockReserved() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")
        p.train.speed!.accelerationProfile = .none

        // Reserve a block with another route to make the train stop
        let b3 = layout.blocks[p.route.steps[2].stepBlockId]!
        b3.reservation = .init("2", .next)

        try p.assert("r1:{r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [r2[b3 ≏ ≏ ]] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1:{r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [r2[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1:{r1{b1 ≡ 🔵►1 ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [r2[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≡ }}")
        try p.assert("r1:{r1{b1 ≏ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [r2[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≡ ≏ }}")
        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≡ 🟡►1 ≏ ]] <t1(0,2)> [r2[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")
        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≏ ≡ 🔴►1 ]] <t1(0,2)> [r2[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")

        // Free block b3
        b3.trainInstance = nil
        b3.reservation = nil

        // Which is a simulation of a train moving out of b3, so trigger that event
        // so train 1 will restart
        p.layoutController.runControllers(.trainPositionChanged(p.train))

        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≏ ≡ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")

        p.stop()

        XCTAssertEqual(p.train.state, .stopping)

        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≏ ≡ 🔴►1 ]] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0)> !{b1 ≏ ≏ }")

        XCTAssertEqual(p.train.state, .stopped)
    }

    func testBlockBrakingSpeed() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)

        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        layout.blocks[0].brakingSpeed = 17

        let train = layout.train("1")

        try p.assert("r1:{r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1:{r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≡ 🔵►1 ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")
        try p.assert("r1:{r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≡ 🔵►1 ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1:{r1{b1 ≏ 🟡17!►1 ≡ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≡ 🟡17►1 ≏ }}")

        XCTAssertEqual(train.speed!.actualKph, 17)

        try p.assert("r1:{r1{b1 🔴!►1 ≡ ≏ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≏ ≡ 🔴►1 }}")
    }

    func testBlockDisabled() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        // Disable a block to make the train stop
        let b3 = layout.blocks[p.route.steps[2].stepBlockId]!
        b3.enabled = false

        try p.assert("r1:{r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1:{r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1:{r1{b1 ≡ 🔵►1 ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≡ }}")
        try p.assert("r1:{r1{b1 ≏ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≡ ≏ }}")
        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≡ 🟡►1 ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{b1 ≏ ≏ }")
        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≏ ≡ 🔴►1 ]] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{b1 ≏ ≏ }")

        // Re-enable b3
        b3.enabled = true
        p.layoutController.runControllers(.trainPositionChanged(p.train))

        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≏ ≡ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")

        p.stop()

        try p.assert("r1:{b1 ≏ ≏ } <t0> [r1[b2 ≏ ≡ 🔴►1 ]] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0)> !{b1 ≏ ≏ }")
    }

    func testStartNotInRoute() throws {
        let layout = LayoutLoop2().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b5")

        try p.assert("r1: {b1 ≏ ≏ } <t0> [b2 ≏ ≏ ] {b3 ≏ ≏ } <t1> [b4 ≏ ≏] {b1 ≏ ≏ }")

        XCTAssertThrowsError(try p.start()) { error in
            guard let layoutError = error as? LayoutError else {
                XCTFail()
                return
            }

            guard case .trainNotFoundInRoute(train: _, route: _) = layoutError else {
                XCTFail()
                return
            }
        }
    }

    func testStartInRouteButReversedDirection() throws {
        let layout = LayoutLoop2().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1", direction: .previous)

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] {b3 ≏ ≏ }} <t1> [b4 ≏ ≏] {r1{b1 🔴►1 ≏ ≏ }}")

        XCTAssertThrowsError(try p.start()) { error in
            guard let layoutError = error as? LayoutError else {
                XCTFail()
                return
            }

            guard case .trainNotFoundInRoute(train: _, route: _) = layoutError else {
                XCTFail()
                return
            }
        }

        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1", direction: .next)

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] {b3 ≏ ≏ }} <t1> [b4 ≏ ≏] {r1{b1 🔴►1 ≏ ≏ }}")
        try p.start()
    }

    func testMoveInsideBlock() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 🔴►1 ≡ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≡ }}")
        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≡ 🔵►1 ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≡ }}")
        try p.assert("r1: {r1{b1 ≏ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≡ ≏ }}")
        try p.assert("r1: {b1 ≏ ≏ } <t0> [r1[b2 ≡ 🔵►1 ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")
        try p.assert("r1: {b1 ≏ ≏ } <t0> [r1[b2 ≏ ≡ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")
        try p.assert("r1: {b1 ≏ ≏ } <t0> [r1[b2 ≏ ≏ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≡ 🔵►1 ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≏ 🔵►1 ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≏ ≡ 🔵►1 ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ 🟡!►1 ≡ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≡ 🟡►1 ≏ }}")
        try p.assert("r1: {r1{b1 ≏ 🟡!►1 ≏ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≏ 🟡►1 ≏ }}")
        try p.assert("r1: {r1{b1 🔴!►1 ≡ ≏ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≏ ≡ 🔴►1 }}")
    }

    func testMoveWith2LeadingReservation() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let t1 = layout.train("1")
        t1.maxNumberOfLeadingReservedBlocks = 2

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1: {r1{b1 🔵►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}", ["b2", "b3"])
        try p.assert("r1: {r1{b1 ≡ 🔵►1 ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≡ }}", ["b2", "b3"])
        try p.assert("r1: {r1{b1 ≏ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≡ ≏ }}", ["b2", "b3"])
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [r1[b2 ≡ 🔵►1 ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏}}", ["b3", "b1"])
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [r1[b2 ≏ ≡ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}", ["b3", "b1"])
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [r1[b2 ≏ ≏ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}", ["b3", "b1"])
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≡ 🔵►1 ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}", ["b1"])
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≏ 🔵►1 ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}", ["b1"])
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≏ ≡ 🔵►1 ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}", ["b1"])
        try p.assert("r1: {r1{b1 ≏ 🟡!►1 ≡ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≡ 🟡►1 ≏ }}", [])
        try p.assert("r1: {r1{b1 ≏ 🟡!►1 ≏ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≏ 🟡►1 ≏ }}", [])
        try p.assert("r1: {r1{b1 🔴!►1 ≡ ≏ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≏ ≡ 🔴►1 }}", [])
    }

    func testMoveWith2LeadingReservationWithLoop() throws {
        let layout = LayoutFigure8().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        let t1 = layout.trains[0]
        t1.maxNumberOfLeadingReservedBlocks = 2

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t1{ds2}> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3)> [b4 ≏ ≏ ] {r1{b1 🔴►1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t1{ds2},s01>> [r1[b2 ≏ ≏ ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s01>> [b4 ≏ ≏ ] {r1{b1 🟢►1 ≏ ≏ }}")
        try p.assert("r1: {b1 ≏ ≏ } <r1<t1{ds2},s23>> [r1[b2 ≡ 🟢►1 ≏ ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ≏ ≏ ]] {b1 ≏ ≏ }")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t1{ds2},s23>> [b2 ≏ ≏ ] [r1[b3 ≡ 🟢►1 ≏ ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ≏ ≏ ]] {r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [r1[b4 ≡ 🔵►1 ≏ ]] {r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≡ 🟡►1 ≏ }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [b4 ≏ ≏ ] {r1{b1 ≡ 🟡►1 ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≡ 🔴►1 }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [b4 ≏ ≏ ] {r1{b1 ≏ ≡ 🔴►1 }}")
    }

    func testMoveWith3LeadingReservationWithLoop() throws {
        let layout = LayoutFigure8().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        let t1 = layout.trains[0]
        t1.maxNumberOfLeadingReservedBlocks = 3

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t1{ds2}> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3)> [b4 ≏ ≏ ] {r1{b1 🔴►1 ≏ ≏ }}")

        try p.start()

        // b4 is not reserved because the turnout t1 is already reserved for b1->b2.
        try p.assert("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t1{ds2},s01>> [r1[b2 ≏ ≏ ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s01>> [b4 ≏ ≏ ] {r1{b1 🟢►1 ≏ ≏ }}")

        // Now that the train is in b2, the turnout t1 is free and the leading blocks can be reserved until b1, including b4.
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t1{ds2},s23>> [r1[b2 ≡ 🟢►1 ≏ ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ≏ ≏ ]] {r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t1{ds2},s23>> [b2 ≏ ≏ ] [r1[b3 ≡ 🟢►1 ≏ ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ≏ ≏ ]] {r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [r1[b4 ≡ 🔵►1 ≏ ]] {r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≡ 🟡►1 ≏ }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [b4 ≏ ≏ ] {r1{b1 ≡ 🟡►1 ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≡ 🔴►1 }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [b4 ≏ ≏ ] {r1{b1 ≏ ≡ 🔴►1 }}")
    }

    func testMoveWith3LeadingReservation() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let t1 = layout.train("1")
        t1.maxNumberOfLeadingReservedBlocks = 3

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1: {r1{b1 🔵►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≡ 🔵►1 ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≡ }}")
        try p.assert("r1: {r1{b1 ≏ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≡ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [r1[b2 ≡ 🔵►1 ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏}}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [r1[b2 ≏ ≡ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [r1[b2 ≏ ≏ 🔵►1 ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≡ 🔵►1 ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≏ 🔵►1 ≏ ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t0,l>> [b2 ≏ ≏ ] <t1(0,2),l> [r1[b3 ≏ ≡ 🔵►1 ]] <r1<t0(2,0),l>> !{r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ 🟡!►1 ≡ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≡ 🟡►1 ≏ }}")
        try p.assert("r1: {r1{b1 ≏ 🟡!►1 ≏ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≏ 🟡►1 ≏ }}")
        try p.assert("r1: {r1{b1 🔴!►1 ≡ ≏ }} <t0,l> [b2 ≏ ≏ ] <t1(0,2),l> [b3 ≏ ≏ ] <t0(2,0),l> !{r1{b1 ≏ ≡ 🔴►1 }}")
    }

    //       ┌─────────┐                              ┌─────────┐
    //    ┌──│ Block 2 │◀────┐         ┌─────────────▶│ Block 4 │──┐
    //    │  └─────────┘     │         │              └─────────┘  │
    //    │                  │         │                           │
    //    │                  │                                     │
    //    │                  └─────Turnout1 ◀───┐                  │
    //    │                                     │                  │
    //    │                            ▲        │                  │
    //    │  ┌─────────┐               │        │     ┌─────────┐  │
    //    └─▶│ Block 3 │───────────────┘        └─────│ Block 1 │◀─┘
    //       └─────────┘                              └─────────┘
    func testMoveWith1OccupiedReservationNoFeedbacks() throws {
        let layout = LayoutFigure8().newLayout().removeBlockGeometry().removeTrainGeometry()

        // Let's only define block length and omit feedback distances
        for block in layout.blocks.elements {
            block.length = 100
            block.feedbacks[0].distance = 20
            block.feedbacks[1].distance = 80
        }

        let t1 = layout.trains[0]
        // That way, the train always needs one occupied block reserved to account for its length
        t1.locomotive!.length = 20
        t1.wagonsLength = 130
        t1.maxNumberOfLeadingReservedBlocks = 1

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1", position: .end)

        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔴►1 }} <t1{ds2}> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3)> [r1[b4 ≏ ◼︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔴►1}}")

        try p.start()

        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔵►1 }} <r1<t1{ds2},s01>> [r1[b2 ≏ ≏ ]] [b3 ≏ ≏ ] <r1<t1{ds2}(2,3),s01>> [r1[b4 ≏ ◼︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔵►1}}")
        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 }} <r1<t1{ds2},s01>> [r1[b2 ◻︎1 ≡ 🔵►1 ≏ ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s01>> [r1[b4 ≏ ≏ ◼︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≏ ◻︎1}}")
        try p.assert("r1: {r1{b1 ≏ ◼︎1 ≏ ◻︎1 }} <r1<t1{ds2},s01>> [r1[b2 ◻︎1 ≏ ◻︎1 ≡ 🔵►1 ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s01>> [b4 ≏ ≏ ] {r1{b1 ≏ ◼︎1 ≏ ◻︎1}}")
        try p.assert("r1: {r1{b1 ≏ ≏ ◼︎1 }} <r1<t1{ds2},s01>> [r1[b2 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 ]] [r1[b3 ◻︎1 ≡ 🟡►1 ≏ ]] <r1<t1{ds2}(2,3),s01>> [b4 ≏ ≏ ] {r1{b1 ≏ ≏ ◼︎1}}")
        try p.assert("r1: {b1 ≏ ≏ } <r1<t1{ds2},s23>> [r1[b2 ≏ ◼︎1 ≏ ◻︎1 ]] [r1[b3 ◻︎1 ≏ ◻︎1 ≡ 🔵►1 ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ≏ ≏ ]] {b1 ≏ ≏ }")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t1{ds2},s23>> [r1[b2 ≏ ≏ ◼︎1 ]] [r1[b3 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ◻︎1 ≡ 🔵►1 ≏ ]] {r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t1{ds2},s23>> [b2 ≏ ≏ ] [r1[b3 ≏ ◼︎1 ≏ ◻︎1 ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ◻︎1 ≏ ◻︎1 ≡ 🔵►1 ]] {r1{b1 ≏ ≏ }}")
        try p.assert("r1: {r1{b1 ◻︎1 ≡ 🟡►1 ≏ }} <r1<t1{ds2},s23>> [b2 ≏ ≏ ] [r1[b3 ≏ ≏ ◼︎1]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≡ 🟡►1 ≏ }}")
        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≡ 🔴►1 }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [r1[b4 ≏ ◼︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≡ 🔴►1 }}")
    }

    func testMoveWith1OccupiedReservationWithFeedbacks() throws {
        let layout = LayoutFigure8().newLayout()

        for block in layout.blocks.elements {
            block.length = 100
            block.feedbacks[0].distance = 20
            block.feedbacks[1].distance = 100 - 20
        }

        let t1 = layout.trains[0]
        // That way, the train always needs one occupied block reserved to account for its length
        t1.locomotive!.length = 20
        t1.wagonsLength = 120
        t1.maxNumberOfLeadingReservedBlocks = 1

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1", position: .end)

        // b1: { w20 | w60 | >20 } b2: [ 20 | 60 | 20 ] b3: [ 20 | 60 | 20 ] b4: [ 20 | w60 | w20 ]
        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔴►1 }} <t1{ds2}> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3)> [r1[b4 ≏ ◼︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔴►1}}")

        try p.start()

        // b1: { w20 | w60 | >20 } b2: [ 20 | 60 | 20 ] b3: [ 20 | 60 | 20 ] b4: [ 20 | w60 | w20 ]
        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔵►1 }} <r1<t1{ds2},s01>> [r1[b2 ≏ ≏ ]] [b3 ≏ ≏ ] <r1<t1{ds2}(2,3),s01>> [r1[b4 ≏ ◼︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≏ 🔵►1}}")

        // b1: { w20 | w60 | w20 } b2: [ w20 | >60 | 20 ] b3: [ 20 | 60 | 20 ] b4: [ 20 | 60 | w20 ]
        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 }} <r1<t1{ds2},s01>> [r1[b2 ◻︎1 ≡ 🔵►1 ≏ ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s01>> [r1[b4 ≏ ≏ ◼︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≏ ◻︎1}}")

        // b1: { 20 | w60 | w20 } b2: [ w20 | w60 | >20 ] b3: [ 20 | 60 | 20 ] b4: [ 20 | 60 | 20 ]
        try p.assert("r1: {r1{b1 ≏ ◼︎1 ≏ ◻︎1 }} <r1<t1{ds2},s01>> [r1[b2 ◻︎1 ≏ ◻︎1 ≡ 🔵►1 ]] [r1[b3 ≏ ≏ ]] <r1<t1{ds2}(2,3),s01>> [b4 ≏ ≏ ] {r1{b1 ≏ ◼︎1 ≏ ◻︎1}}")

        // b1: { 20 | 60 | w20 } b2: [ w20 | w60 | w20 ] b3: [ w20 | >60 | 20 ] b4: [ 20 | 60 | 20 ]
        // Note: train is slowing down to stop because b4 cannot be reserved because the tail of the train still occupies the turnout
        try p.assert("r1: {r1{b1 ≏ ≏ ◼︎1 }} <r1<t1{ds2},s01>> [r1[b2 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 ]] [r1[b3 ◻︎1 ≡ 🟡►1 ≏ ]] <r1<t1{ds2}(2,3),s01>> [b4 ≏ ≏ ] {r1{b1 ≏ ≏ ◼︎1 }}")

        // b1: { 20 | 60 | 20 } b2: [ 20 | w60 | w20 ] b3: [ w20 | w60 | >20 ] b4: [ 20 | 60 | 20 ]
        // Note: the train accelerates again because the leading blocks can be reserved again now that the tail of the train
        // does not occupy turnout 1 anymore.
        try p.assert("r1: {b1 ≏ ≏ } <r1<t1{ds2},s23>> [r1[b2 ≏ ◼︎1 ≏ ◻︎1 ]] [r1[b3 ◻︎1 ≏ ◻︎1 ≡ 🔵►1 ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ≏ ≏ ]] {b1 ≏ ≏ }")

        // b1: { 20 | 60 | 20 } b2: [ 20 | 60 | w20 ] b3: [ w20 | w60 | w20 ] b4: [ w20 | >60 | 20 ]
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t1{ds2},s23>> [r1[b2 ≏ ≏ ◼︎1 ]] [r1[b3 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ◻︎1 ≡ 🔵►1 ≏ ]] {r1{b1 ≏ ≏ }}")

        // b1: { 20 | 60 | 20 } b2: [ 20 | 60 | w20 ] b3: [ w20 | w60 | w20 ] b4: [ w20 | >60 | 20 ]
        try p.assert("r1: {r1{b1 ≏ ≏ }} <r1<t1{ds2},s23>> [b2 ≏ ≏ ] [r1[b3 ≏ ◼︎1 ≏ ◻︎1 ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ◻︎1 ≏ ◻︎1 ≡ 🔵►1 ]] {r1{b1 ≏ ≏ }}")

        // b2: [ 20 | 60 | w20 ] b3: [ 20 | 60 | w20 ] b4: [ w20 | w60 | w20 ] b1: { w20 | >60 | 20 }
        try p.assert("r1: {r1{b1 ◻︎1 ≡ 🟡►1 ≏ }} <r1<t1{ds2},s23>> [b2 ≏ ≏ ] [r1[b3 ≏ ≏ ◼︎1 ]] <r1<t1{ds2}(2,3),s23>> [r1[b4 ◻︎1 ≏ ◻︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≡ 🟡►1 ≏ }}")

        // b2: [ 20 | 60 | w20 ] b3: [ 20 | 60 | 20 ] b4: [ 20 | w60 | w20 ] b1: { w20 | w60 | >20 }
        try p.assert("r1: {r1{b1 ◻︎1 ≏ ◻︎1 ≡ 🔴►1 }} <t1{ds2},s23> [b2 ≏ ≏ ] [b3 ≏ ≏ ] <t1{ds2}(2,3),s23> [r1[b4 ≏ ◼︎1 ≏ ◻︎1 ]] {r1{b1 ◻︎1 ≏ ◻︎1 ≡ 🔴►1 }}")
    }

    func testRouteReverseLoop() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r2", trainID: "2", fromBlockId: "b1")

        try layout.remove(trainId: layout.trains.elements.first!.id)

        try p.assert("r2: {r2{b1 🔴►2 ≏ ≏ }} <t0(0,2)> ![b3 ≏ ≏ ] <t1(2,0)> ![b2 ≏ ≏ ] <t0(1,0)> !{r2{b1 ≏ ≏ 🔴►2 }}")

        try p.start()

        try p.assert("r2: {r2{b1 🔵►2 ≏ ≏ }} <r2<t0(0,2),l>> ![r2[b3 ≏ ≏ ]] <t1(2,0)> ![b2 ≏ ≏ ] <r2<t0(1,0),l>> !{r2{b1 ≏ ≏ 🔵►2 }}")
        try p.assert("r2: {r2{b1 ≡ 🔵►2 ≏ }} <r2<t0(0,2),l>> ![r2[b3 ≏ ≏ ]] <t1(2,0)> ![b2 ≏ ≏ ] <r2<t0(1,0),l>> !{r2{b1 ≏ 🔵►2 ≡ }}")
        try p.assert("r2: {r2{b1 ≏ ≡ 🔵►2 }} <r2<t0(0,2),l>> ![r2[b3 ≏ ≏ ]] <t1(2,0)> ![b2 ≏ ≏ ] <r2<t0(1,0),l>> !{r2{b1 🔵►2 ≡ ≏ }}")
        try p.assert("r2: {b1 ≏ ≏ } <t0(0,2),l> ![r2[b3 ≡ 🔵!►2 ≏ ]] <r2<t1(2,0),l>> ![r2[b2 ≏ ≏ ]] <t0(1,0),l> !{b1 ≏ ≏ }")
        try p.assert("r2: {b1 ≏ ≏ } <t0(0,2),l> ![r2[b3 ≏ ≡ 🔵!►2 ]] <r2<t1(2,0),l>> ![r2[b2 ≏ ≏ ]] <t0(1,0),l> !{b1 ≏ ≏ }")
        try p.assert("r2: {r2{b1 ≏ ≏ }} <r2<t0(0,2)>> ![b3 ≏ ≏ ] <t1(2,0),l> ![r2[b2 ≡ 🔵!►2 ≏ ]] <r2<t0(1,0)>> !{r2{b1 ≏ ≏ }}")
        try p.assert("r2: {r2{b1 ≏ ≏ }} <r2<t0(0,2)>> ![b3 ≏ ≏ ] <t1(2,0),l> ![r2[b2 ≏ ≡ 🔵!►2 ]] <r2<t0(1,0)>> !{r2{b1 ≏ ≏ }}")
        try p.assert("r2: {r2{b1 ≏ 🟡!►2 ≡ }} <t0(0,2)> ![b3 ≏ ≏ ] <t1(2,0),l> ![b2 ≏ ≏ ] <t0(1,0)> !{r2{b1 ≡ 🟡►2 ≏ }}")
        try p.assert("r2: {r2{b1 🔴!►2 ≡ ≏ }} <t0(0,2)> ![b3 ≏ ≏ ] <t1(2,0),l> ![b2 ≏ ≏ ] <t0(1,0)> !{r2{b1 ≏ ≡ 🔴►2 }}")
    }

    func testRelaxModeNextModeFeedback() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        layout.detectUnexpectedFeedback = true

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")
        // The train should continue to the next block when the feedback of the next block is triggered
        try p.assert("r1: {b1 ≏ ≏ } <t0> [r1[b2 ≡ 🔵►1 ≏ ]] <r1<t1(0,2),l>> [r1[b3 ≏ ≏ ]] <t0(2,0)> !{b1 ≏ ≏ }")
    }

    func testRelaxModeNextBlockFeedbackTooFar() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        layout.detectUnexpectedFeedback = true

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")
        // The train should stop because the next block feedback is triggered but it is not the one expected
        // to be triggered given the direction of travel of the train
        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≡ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}", expectRuntimeError: true)
        XCTAssertNotNil(layout.runtimeError)
    }

    func testRelaxModeNextAndPreviousFeedbacks() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")

        layout.detectUnexpectedFeedback = true

        try p.assert("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] <t1(0,2)> [b3 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ }}")

        try p.start()

        try p.assert("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ }}")

        // Train position should be updated although the feedback is not next to the train but a bit further.
        try p.assert("r1: {r1{b1 ≏ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 🔵►1 ≡ ≏ }}")

        // A feedback behind the train (in the same block) is triggered. Because the train has an allowedDirection of .forward,
        // that feedback is simply ignored (we could throw an exception in the future if we wanted to). Note that if the train
        // was allowed to move in any direction, the back position would be updated by that feedback.
        try p.assert("r1: {r1{b1 ≡ ≏ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] <t1(0,2)> [b3 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 🔵►1 ≏ ≡ }}")
    }

    //                            ┌─────────┐
    //     ┌───▶   t125   ───────▶│ Block 2 │───────────────────────────┐
    //     │                      └─────────┘                           │
    //     │         ▲                                                  │
    //     │         │                                                  │
    // ┌─────────┐    │                                                  ▼
    // │ Block 1 │    │             ┌─────────┐                     ┌─────────┐
    // └─────────┘    └─────────────│ Block 5 │◀──────────────┐     │ Block 3 │
    //     ▲                       └─────────┘               │     └─────────┘
    //     │                                                 │          │
    //     │                                                 │          │
    //     │                                                 │          │
    //     │                                                 │          │
    //     │                       ┌─────────┐                          │
    //     └───────────────────────│ Block 4 │◀─────────   t345   ◀─────┘
    //                             └─────────┘
    func testNextBlockFeedbackHandling() throws {
        let layout = LayoutLoop2().newLayout().removeTrainGeometry()

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")
        try p.prepare(routeID: "r3", trainID: "2", fromBlockId: "b3")

        try p.assert2("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] {r2{b3 🔴►2 ≏ ≏ }} <t1> [b4 ≏ ≏] {r1{b1 🔴►1 ≏ ≏ }}",
                      "r3: {r2{b3 🔴►2 ≏ ≏ }} <t1(0,2)> [b5 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ 🔴►1 }}")

        try p.start(routeID: "r3", trainID: "2")

        try p.assert2("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] {r2{b3 🔵►2 ≏ ≏ }} <r2<t1,r>> [b4 ≏ ≏] {r1{b1 🔴►1 ≏ ≏ }}",
                      "r3: {r2{b3 🔵►2 ≏ ≏ }} <r2<t1(0,2),r>> [r2[b5 ≏ ≏ ]] <t0(2,0)> !{r1{b1 ≏ ≏ 🔴►1 }}")

        try p.assert2("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 🔴►1 ≏ ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≡ 🟡►2 ≏ ]] <t0(2,0)> !{r1{b1 ≏ ≏ 🔴►1 }}")

        try p.start(routeID: "r1", trainID: "1")

        try p.assert2("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 🟢►1 ≏ ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≏ 🟡►2 ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ 🟢►1 }}")

        try p.assert2("r1: {r1{b1 ≡ 🔵►1 ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 ≡ 🔵►1 ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≏ 🟡►2 ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ 🔵►1 ≡ }}")

        // Note: the last feedback of block b1 is activated which moves train 1 within b1. However, this feedback
        // is also used to move train 2 to block b1 but in this situation it should be ignored for train 2 because
        // block b1 is not free.
        try p.assert2("r1: {r1{b1 ≏ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 ≏ ≡ 🔵►1 }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≏ 🟡►2 ≏ ]] <r1<t0(2,0)>> !{r1{b1 🔵►1 ≡ ≏ }}")

        try p.assert2("r1: {r1{b1 ≏ ≏ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 ≏ ≏ 🔵►1 }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≏ 🟡►2 ≏ ]] <r1<t0(2,0)>> !{r1{b1 🔵►1 ≏ ≏ }}")

        // Train 1 moves to b2
        try p.assert2("r1: {r2{b1 ≏ ≏ }} <r2<t0,r>> [r1[b2 ≡ 🔵►1 ≏ ]] {r1{b3 ≏ ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≏ }} <t1(0,2),r> [r2[b5 ≏ 🔵►2 ≏ ]] <r2<t0(2,0),r>> !{r2{b1 ≏ ≏ }}")

        // Train 2 moves to the end of block b5
        try p.assert2("r1: {r2{b1 ≏ ≏ }} <r2<t0,r>> [r1[b2 ≡ 🔵►1 ≏ ]] {r1{b3 ≏ ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≏ }} <t1(0,2),r> [r2[b5 ≏ ≡ 🔵►2 ]] <r2<t0(2,0),r>> !{r2{b1 ≏ ≏ }}")

        // Now train 2 is starting again after reserving block b1 for itself
        try p.assert2("r1: {r2{b1 ≏ ≏ }} <r2<t0,r>> [r1[b2 ≏ 🔵►1 ≏ ]] {r1{b3 ≏ ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≏ }} <t1(0,2),r> [r2[b5 ≏ ≏ 🔵►2 ]] <r2<t0(2,0),r>> !{r2{b1 ≏ ≏ }}")

        // Train 2 moves to b1 (entering in the previous direction!)
        try p.assert2("r1: {r2{b1 ≏ 🟡!►2 ≡ }} <t0,r> [r1[b2 ≏ 🔵►1 ≏ ]] {r1{b3 ≏ ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 ≏ 🟡!►2 ≡ }}",
                      "r3: {r1{b3 ≏ ≏ }} <t1(0,2),r> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≡ 🟡►2 ≏ }}")
    }

    func testMoveRouteLoop() throws {
        let layout = LayoutLoop2().newLayout().removeTrainGeometry()

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1")
        try p.prepare(routeID: "r3", trainID: "2", fromBlockId: "b3")

        try p.assert2("r1: {r1{b1 🔴►1 ≏ ≏ }} <t0> [b2 ≏ ≏ ] {r2{b3 🔴►2 ≏ ≏ }} <t1> [b4 ≏ ≏] {r1{b1 🔴►1 ≏ ≏ }}",
                      "r3: {r2{b3 🔴►2 ≏ ≏ }} <t1(0,2)> [b5 ≏ ≏ ] <t0(2,0)> !{r1{b1 ≏ ≏ 🔴►1 }}")

        try p.start(routeID: "r1", trainID: "1")

        try p.assert2("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {r2{b3 🔴►2 ≏ ≏ }} <t1> [b4 ≏ ≏] {r1{b1 🟢►1 ≏ ≏ }}",
                      "r3: {r2{b3 🔴►2 ≏ ≏ }} <t1(0,2)> [b5 ≏ ≏ ] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ 🟢►1 }}")

        try p.start(routeID: "r3", trainID: "2")

        try p.assert2("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {r2{b3 🔵►2 ≏ ≏ }} <r2<t1,r>> [b4 ≏ ≏] {r1{b1 🟢►1 ≏ ≏ }}",
                      "r3: {r2{b3 🔵►2 ≏ ≏ }} <r2<t1(0,2),r>> [r2[b5 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ 🟢►1 }}")

        try p.assert2("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {r2{b3 ≡ 🔵►2 ≏ }} <r2<t1,r>> [b4 ≏ ≏] {r1{b1 🟢►1 ≏ ≏ }}",
                      "r3: {r2{b3 ≡ 🔵►2 ≏ }} <r2<t1(0,2),r>> [r2[b5 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ 🟢►1 }}")

        try p.assert2("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {r2{b3 ≡ ≡ 🔵►2 }} <r2<t1,r>> [b4 ≏ ≏] {r1{b1 🟢►1 ≏ ≏ }}",
                      "r3: {r2{b3 ≡ ≡ 🔵►2 }} <r2<t1(0,2),r>> [r2[b5 ≏ ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ 🟢►1 }}")

        try p.assert2("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 🟢►1 ≏ ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≡ 🟡►2 ≏ ]] <r1<t0(2,0)>> !{r1{b1 ≏ ≏ 🟢►1 }}")

        // Train 2 stops because block b1 is still in use by train 1.
        try p.assert2("r1: {r1{b1 🟢►1 ≏ ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 🟢►1 ≏ ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≡ ≡ 🔴►2 ]] <r1<t0(2,0)>> !{r1{b1  ≏ ≏ 🟢►1 }}")

        try p.assert2("r1: {r1{b1 ≡ 🔵►1 ≏ }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 ≡ 🔵►1 ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≏ ≏ 🔴►2 ]] <r1<t0(2,0)>> !{r1{b1 ≏ 🔵►1 ≡ }}")

        try p.assert2("r1: {r1{b1 ≡ ≡ 🔵►1 }} <r1<t0>> [r1[b2 ≏ ≏ ]] {b3 ≏ ≏ } <t1,r> [b4 ≏ ≏] {r1{b1 ≡ ≡ 🔵►1 }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2),r> [r2[b5 ≏ ≏ 🔴►2 ]] <r1<t0(2,0)>> !{r1{b1 🔵►1 ≡ ≡ }}")

        // Train 2 starts again because block 1 is now free (train 1 has moved to block 2).
        try p.assert2("r1: {r2{b1 ≏ ≏ }} <r2<t0,r>> [r1[b2 ≡ 🔵►1 ≏ ]] {r1{b3 ≏ ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≏ }} <t1(0,2),r> [r2[b5 ≏ ≏ 🔵►2 ]] <r2<t0(2,0),r>> !{r2{b1 ≏ ≏ }}")

        try p.assert2("r1: {r2{b1 ≏ ≏ }} <r2<t0,r>> [r1[b2 ≡ ≡ 🔵►1 ]] {r1{b3 ≏ ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≏ }} <t1(0,2),r> [r2[b5 ≏ ≏ 🔵►2 ]] <r2<t0(2,0),r>> !{r2{b1 ≏ ≏ }}")

        try p.assert2("r1: {r2{b1 ≏ 🟡!►2 ≡ }} <t0,r> [r1[b2 ≏ ≏ 🔵►1 ]] {r1{b3 ≏ ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 ≏ 🟡!►2 ≡ }}",
                      "r3: {r1{b3 ≏ ≏ }} <t1(0,2),r> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≡ 🟡!►2 ≏ }}")

        // Train 1 brakes because it has reached a station and should stop
        // Train 2 stops because it has reached the end of the last block of its route (b1).
        try p.assert2("r1: {r2{b1 🔴!►2 ≡ ≏ }} <t0,r> [b2 ≏ ≏ ] {r1{b3 ≡ 🟡►1 ≏ }} <t1,r> [b4 ≏ ≏] {r2{b1 🔴!►2 ≡ ≏ }}",
                      "r3: {r1{b3 ≡ 🟡►1 ≏ }} <t1(0,2),r> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≏ ≡ 🔴!►2  }}")

        // Train 1 has stopped because it is in a station (b3). It will restart shortly after.
        try p.assert2("r1: {r2{b1 🔴!►2 ≏ ≏ }} <t0,r> [b2 ≏ ≏ ] {r1{b3 ≏ ≡ 🔴►1 }} <t1,r> [b4 ≏ ≏] {r2{b1 🔴!►2 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≡ 🔴►1 }} <t1(0,2),r> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≏ ≏ 🔴!►2 }}")

        try p.assert2("r1: {r2{b1 🔴!►2 ≏ ≏ }} <t0,r> [b2 ≏ ≏ ] {r1{b3 ≏ ≏ 🔴►1 }} <t1,r> [b4 ≏ ≏] {r2{b1 🔴!►2 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≏ 🔴►1 }} <t1(0,2),r> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≏ ≏ 🔴!►2 }}")

        // Artificially set the restart time to 0 which will make train 1 restart again
        p.layoutController.restartTimerFired(layout.trains[0])

        try p.assert2("r1: {r2{b1 🔴!►2 ≏ ≏ }} <t0,r> [b2 ≏ ≏ ] {r1{b3 ≏ ≏ 🔵►1 }} <r1<t1>> [r1[b4 ≏ ≏]] {r2{b1 🔴!►2 ≏ ≏ }}",
                      "r3: {r1{b3 ≏ ≏ 🔵►1 }} <r1<t1(0,2)>> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≏ ≏ 🔴!►2 }}")

        try p.assert2("r1: {r2{b1 🔴!►2 ≏ ≏ }} <t0,r> [b2 ≏ ≏ ] {b3 ≏ ≏ } <t1> [r1[b4 ≡ 🟡►1 ≏]] {r2{b1 🔴!►2 ≏ ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2)> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≏ ≏ 🔴!►2 }}")

        // Train 1 stops again because there is a train in the next block b1 (train 2)
        try p.assert2("r1: {r2{b1 🔴!►2 ≏ ≏ }} <t0,r> [b2 ≏ ≏ ] {b3 ≏ ≏ } <t1> [r1[b4 ≡ ≡ 🔴►1 ]] {r2{b1 🔴!►2 ≏ ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2)> [b5 ≏ ≏ ] <t0(2,0),r> !{r2{b1 ≏ ≏ 🔴!►2 }}")

        // Let's remove train 2 artificially to allow train 1 to stop at the station b1
        try layout.remove(trainId: Identifier<Train>(uuid: "2"))
        p.layoutController.runControllers(.trainPositionChanged(p.train))

        try p.assert2("r1: {r1{b1 ≏ ≏ }} <t0,r> [b2 ≏ ≏ ] {b3 ≏ ≏ } <t1> [r1[b4 ≡ ≡ 🔵►1 ]] {r1{b1 ≏ ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2)> [b5 ≏ ≏ ] <t0(2,0),r> !{r1{b1 ≏ ≏ }}")

        try p.assert2("r1: {r1{b1 ≡ 🟡►1 ≏ }} <t0,r> [b2 ≏ ≏ ] {b3 ≏ ≏ } <t1> [b4 ≏ ≏ ] {r1{b1 ≡ 🟡►1 ≏ }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2)> [b5 ≏ ≏ ] <t0(2,0),r> !{r1{b1 ≏ 🟡►1 ≡ }}")

        // Train 1 finally stops at the station b1 which is its final block of the route
        try p.assert2("r1: {r1{b1 ≡ ≡ 🔴►1 }} <t0,r> [b2 ≏ ≏ ] {b3 ≏ ≏ } <t1> [b4 ≏ ≏ ] {r1{b1 ≡ ≡ 🔴►1 }}",
                      "r3: {b3 ≏ ≏ } <t1(0,2)> [b5 ≏ ≏ ] <t0(2,0),r> !{r1{b1  🔴►1 ≡ ≡ }}")
    }

    func testEntryBrakeStopFeedbacks() throws {
        let layout = LayoutComplexLoop().newLayout().removeTrainGeometry()

        let train = layout.trains[0]

        let b3 = layout.blocks[Identifier<Block>(uuid: "b3")]!
        b3.brakeFeedbackNext = Identifier<Feedback>(uuid: "fb3.1")
        b3.stopFeedbackNext = Identifier<Feedback>(uuid: "fb3.2")

        XCTAssertEqual(b3.entryFeedback(for: .next), Identifier<Feedback>(uuid: "fb3.1"))
        XCTAssertEqual(b3.brakeFeedback(for: .next), Identifier<Feedback>(uuid: "fb3.1"))
        XCTAssertEqual(b3.stopFeedback(for: .next), Identifier<Feedback>(uuid: "fb3.2"))

        let p = Package(layout: layout)
        try p.prepare(routeID: "0", trainID: "0", fromBlockId: "s1")

        try p.start()

        try p.assert("0: {r0{s1 🔵►0 ≏ }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6(0,2)> {r0{s1 🔵►0 ≏ }}")
        try p.assert("0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [r0[b1 ≡ 🔵►0 ]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6(0,2)> {s1 ≏ }")
        try p.assert("0: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]] <t5> <t6(0,2)> {s1 ≏ }")

        // Let's reserve s1 for train "1"
        layout.reserve("s1", with: "1", direction: .next)

        try p.assert("0: {r1{s1 ≏ }} <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ≏ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ≏ ]] <t5> <t6(0,2)> {r1{s1 ≏ }}")
        try p.assert("0: {r1{s1 ≏ }} <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≡ 🟡►0 ≏ ≏ ]] <t5> <t6(0,2)> {r1{s1 ≏ }}")
        XCTAssertEqual(train.state, .braking)

        // Note: the second feedback in b3 is the one defined as the "stop" feedback which is
        // why the train stops there.
        try p.assert("0: {r1{s1 ≏ }} <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≡ 🔴►0 ≏ ]] <t5> <t6(0,2)> {r1{s1 ≏ }}")

        XCTAssertTrue(train.scheduling == .managed)
        XCTAssertEqual(train.state, .stopped)

        // Free s1 so the train finishes its route
        layout.free("s1")
        p.layoutController.runControllers(.trainPositionChanged(p.train))

        try p.assert("0: {r0{s1 ≏ }} <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ 🔵►0 ≏ ]] <r0<t5>> <r0<t6(0,2),r>> {r0{s1 ≏ }}")
        try p.assert("0: {r0{s1 ≏ }} <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ≡ 🔵►0 ]] <r0<t5>> <r0<t6(0,2),r>> {r0{s1 ≏ }}")
        try p.assert("0: {r0{s1 ≏ }} <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≏ ≏ ≡ 🔵►0 ]] <r0<t5>> <r0<t6(0,2),r>> {r0{s1 ≏ }}")
        try p.assert("0: {r0{s1 ≡ 🔴►0 }} <t1(2,0),l> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ≏ ] <t5> <t6(0,2),r> {r0{s1 ≡ 🔴►0 }}")

        XCTAssertEqual(train.scheduling, .unmanaged)
        XCTAssertEqual(train.state, .stopped)

        // Now let's reverse the train direction and pick the reverse route
        try p.prepare(routeID: "1", trainID: "0", fromBlockId: "s1", direction: .previous)

        try p.assert("1: !{r0{s1 ≏ 🔴►0 }} <t6(2,0),r> <t5(1,0)> ![b3 ≏ ≏ ≏ ] <t4> ![b2 ≏ ] <t3(1,0)> ![b1 ≏ ] <t2,s> <t1(0,2),l> !{r0{s1 ≏ 🔴►0}}")

        try p.start(routeID: "1", trainID: "0")

        try p.assert("1: !{r0{s1 ≏ 🔵►0 }} <r0<t6(2,0),r>> <r0<t5(1,0)>> ![r0[b3 ≏ ≏ ≏ ]] <t4> ![b2 ≏ ] <t3(1,0)> ![b1 ≏ ] <t2,s> <t1(0,2),l> !{r0{s1 ≏ 🔵►0}}")
        try p.assert("1: !{r0{s1 ≡ 🔵►0 }} <r0<t6(2,0),r>> <r0<t5(1,0)>> ![r0[b3 ≏ ≏ ≏ ]] <t4> ![b2 ≏ ] <t3(1,0)> ![b1 ≏ ] <t2,s> <t1(0,2),l> !{r0{s1 ≡ 🔵►0 }}")

        try p.assert("1: !{s1 ≏ } <t6(2,0),r> <t5(1,0)> ![r0[b3 ≡ 🔵!►0 ≏ ≏ ]] <r0<t4>> ![r0[b2 ≏ ]] <t3(1,0)> ![b1 ≏ ] <t2,s> <t1(0,2),l> !{s1 ≏}")
        try p.assert("1: !{s1 ≏ } <t6(2,0),r> <t5(1,0)> ![b3 ≏ ≏ ≏ ] <t4> ![r0[b2 ≡ 🔵!►0 ]] <r0<t3(1,0)>> ![r0[b1 ≏ ]] <t2,s> <t1(0,2),l> !{s1 ≏}")
        try p.assert("1: !{r0{s1 ≏ }} <t6(2,0),r> <t5(1,0)> ![b3 ≏ ≏ ≏ ] <t4> ![b2 ≏ ] <t3(1,0)> ![r0[b1 ≡ 🔵!►0 ]] <r0<t2,s>> <r0<t1(0,2),l>> !{r0{s1 ≏}}")
        try p.assert("1: !{r0{s1 ≡ 🔴!►0 }} <t6(2,0),r> <t5(1,0)> ![b3 ≏ ≏ ≏ ] <t4> ![b2 ≏ ] <t3(1,0)> ![b1 ≏ ] <t2,s> <t1(0,2),l> !{r0{s1 ≡ 🔴►0 }}")
    }

    func testRouteStationRestart() throws {
        let layout = LayoutComplexLoop().newLayout().removeTrainGeometry()

        let p = Package(layout: layout)
        try p.prepare(routeID: "2", trainID: "0", fromBlockId: "s1")

        try p.assert("2: {r0{s1 🔴►0 ≏ }} <t1(2,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6(0,2)> {r0{s1 🔴►0 ≏ }}")

        try p.start()

        XCTAssertTrue(p.train.scheduling == .managed)

        try p.assert("2: {r0{s1 🔵►0 ≏ }} <r0<t1(2,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ } <r0<t1(1,0),l>> <r0<t2(1,0),s>> [r0[b1 ≏ ]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6(0,2)> {r0{s1 🔵►0 ≏ }}")
        try p.assert("2: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [r0[b1 ≡ 🔵►0]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ } <t1(1,0),l> <t2(1,0),s> [r0[b1 ≡ 🔵►0]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6(0,2)> {s1 ≏ }")
        try p.assert("2: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏] <t3> [r0[b2 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ } <t1(1,0),l> <t2(1,0),s> [b1 ≏] <t3> [r0[b2 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6(0,2)> {s1 ≏ }")
        try p.assert("2: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6>> {r0{s2 ≏ }} <t1(1,0),l> <t2(1,0),s> [b1 ≏] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6(0,2)>> {s1 ≏ }")
        try p.assert("2: {s1 ≏ } <t1(2,0),l> <t2(1,0),s> [b1 ≏] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {r0{s2 ≡ 🔴►0 }} <t1(1,0),l> <t2(1,0),s> [b1 ≏] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6(0,2)> {s1 ≏ }")

        XCTAssertEqual(p.train.state, .stopped)
        XCTAssertEqual(p.train.scheduling, .managed)

        // Artificially set the restart time to 0 which will make the train restart again
        p.layoutController.restartTimerFired(layout.trains[0])
        p.layoutController.waitUntilSettled()

        XCTAssertTrue(p.train.speed!.requestedKph > 0)

        // Assert that the train has restarted and is moving in the correct direction
        try p.assert("2: {s1 ≏ } <r0<t1(2,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {r0{s2 ≏ 🔵►0 }} <r0<t1(1,0),s>> <r0<t2(1,0),s>> [r0[b1 ≏]] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6(0,2)> {s1 ≏ }")
        try p.assert("2: {s1 ≏ } <t1(2,0),s> <t2(1,0),s> [r0[b1 ≡ 🔵►0]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6> {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [r0[b1 ≡ 🔵►0]] <r0<t3>> [r0[b2 ≏ ]] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6(0,2)> {s1 ≏ }")
        try p.assert("2: {s1 ≏ } <t1(2,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6> {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [r0[b2 ≡ 🔵►0 ]] <r0<t4(1,0)>> [r0[b3 ≏ ≏ ]] <t5> <t6(0,2)> {s1 ≏ }")
        try p.assert("2: {r0{s1 ≏ }} <t1(2,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6,r>> {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [r0[b3 ≡ 🔵►0 ≏ ]] <r0<t5>> <r0<t6(0,2),r>> {r0{s1 ≏ }}")
        try p.assert("2: {r0{s1 ≡ 🔴►0 }} <t1(2,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ]] <t5> <t6,r> {s2 ≏ } <t1(1,0),s> <t2(1,0),s> [b1 ≏ ] <t3> [b2 ≏ ] <t4(1,0)> [b3 ≏ ≏ ] <t5> <t6(0,2),r> {r0{s1 ≡ 🔴►0 }}")

        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testUpdateAutomaticRouteBrakingAndContinue() throws {
        let layout = LayoutPointToPoint().newLayout()

        let p = Package(layout: layout)
        try p.prepare(routeID: "0", trainID: "0", fromBlockId: "A", position: .end)

        try p.start()

        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ 🔵►0 ]] <r0<AB>> [r0[B ≏ ≏ ]] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB>> [r0[B ◻︎0 ≡ 🔵►0 ≏ ]] [r0[C ≏ ≏ ]] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB>> [r0[B ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] [r0[C ≏ ≏ ]] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")

        // Let's put another train in D
        layout.reserve("D", with: "1", direction: .next)

        // The train should brake
        try p.assert("0: |[A ≏ ≏ ] <AB> [r0[B ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] [r0[C ◻︎0 ≡ 🟡►0 ≏ ]] [r1[D ≏ ≏ ]] <DE(1,0)> [E ≏ ≏ ]|")

        // And now we free D...
        layout.free("D")
        p.layoutController.runControllers(.trainPositionChanged(p.train))

        // Which means the train should start accelerating again
        try p.assert("0: |[A ≏ ≏ ] <AB> [r0[B ≏ ◼︎0 ≏ ◻︎0 ]] [r0[C ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] [r0[D ≏ ≏ ]] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [r0[C ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] [r0[D ◻︎0 ≡ 🟢►0 ≏ ]] <r0<DE(1,0)>> [r0[E ≏ ≏ ]]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [r0[C ≏ ◼︎0 ≏ ◻︎0 ]] [r0[D ◻︎0 ≏ ◻︎0 ≡ 🟢►0 ]] <r0<DE(1,0)>> [r0[E ≏ ≏ ]]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [C ≏ ≏ ] [r0[D ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] <r0<DE(1,0)>> [r0[E ◻︎0 ≡ 🟡►0 ≏ ]]|")

        p.toggle("E.2")

        XCTAssertEqual(p.train.state, .stopped)
    }

    func testStraightLine1() throws {
        let layout = LayoutPointToPoint().newLayout()

        let p = Package(layout: layout)
        try p.prepare(routeID: "0", trainID: "0", fromBlockId: "A", position: .end)

        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ 🔴►0 ]] <AB> [B ≏ ≏ ] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")

        try p.start()

        XCTAssertTrue(p.train.scheduling == .managed)

        // A = 200
        // B=C=D=100
        // AB=DE=10
        // Train = 120
        // [A 20 ≏ 160 ≏ 20 ] <10> [B 20 ≏ 60 ≏ 20 ] [C 20 ≏ 60 ≏ 20 ] [D 20 ≏ 60 ≏ 20 ] <10> [E 20 ≏ 160 ≏ 20 ]
        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ 🔵►0 ]] <r0<AB>> [r0[B ≏ ≏ ]] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB>> [r0[B ◻︎0 ≡ 🔵►0 ≏ ]] [r0[C ≏ ≏ ]] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB>> [r0[B ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] [r0[C ≏ ≏ ]] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [r0[B ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] [r0[C ◻︎0 ≡ 🔵►0 ≏ ]] [r0[D ≏ ≏ ]] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [r0[B ≏ ◼︎0 ≏ ◻︎0 ]] [r0[C ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] [r0[D ≏ ≏ ]] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [r0[C ◼︎0 ≏ ◻︎0 ≏ ◻︎0]] [r0[D ◻︎0 ≡ 🟢►0 ≏ ]] <r0<DE(1,0)>> [r0[E ≏ ≏ ]]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [r0[C ≏ ◼︎0 ≏ ◻︎0]] [r0[D ◻︎0 ≏ ◻︎0 ≡ 🟢►0 ]] <r0<DE(1,0)>> [r0[E ≏ ≏ ]]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [C ≏ ≏ ] [r0[D ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] <r0<DE(1,0)>> [r0[E ◻︎0 ≡ 🟡►0 ≏ ]]|")
        try p.assert("0: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [r0[E ≏ ◼︎0 ≡ 🔴►0 ]]|")
    }

    func testStraightLine2() throws {
        let layout = LayoutPointToPoint().newLayout()

        let p = Package(layout: layout)
        try p.prepare(routeID: "1", trainID: "0", fromBlockId: "A", position: .end)

        try p.assert("1: |[r0[A ≏ ◼︎0 ≏ 🔴►0 ]] <AB(0,2)> [B2 ≏ ≏ ] ![C2 ≏ ≏ ] [D2 ≏ ≏ ] <DE(2,0)> [E ≏ ≏ ]|")

        try p.start()

        XCTAssertTrue(p.train.scheduling == .managed)

        // A = 200
        // B=C=D=100
        // AB=DE=10
        // Train = 120
        // [A 20 ≏ 160 ≏ 20 ] <10> [B2 20 ≏ 60 ≏ 20 ] [C2 20 ≏ 60 ≏ 20 ] [D2 20 ≏ 60 ≏ 20 ] <10> [E 20 ≏ 160 ≏ 20 ]
        try p.assert("1: |[r0[A ≏ ◼︎0 ≏ 🔵►0 ]] <r0<AB(0,2),r>> [r0[B2 ≏ ≏ ]] ![C2 ≏ ≏ ] [D2 ≏ ≏ ] <DE(2,0)> [E ≏ ≏ ]|")
        try p.assert("1: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB(0,2),r>> [r0[B2 ◻︎0 ≡ 🔵►0 ≏ ]] ![r0[C2 ≏ ≏ ]] [D2 ≏ ≏ ] <DE(2,0)> [E ≏ ≏ ]|")
        try p.assert("1: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB(0,2),r>> [r0[B2 ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] ![r0[C2 ≏ ≏ ]] [D2 ≏ ≏ ] <DE(2,0)> [E ≏ ≏ ]|")
        try p.assert("1: |[A ≏ ≏ ] <AB(0,2),r> [r0[B2 ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] ![r0[C2 ◻︎0 ≡ 🔵!►0 ≏ ]] [r0[D2 ≏ ≏ ]] <DE(2,0)> [E ≏ ≏ ]|")
        try p.assert("1: |[A ≏ ≏ ] <AB(0,2),r> [r0[B2 ≏ ◼︎0 ≏ ◻︎0 ]] ![r0[C2 ◻︎0 ≏ ◻︎0 ≡ 🔵!►0]] [r0[D2 ≏ ≏ ]] <DE(2,0)> [E ≏ ≏ ]|")
        try p.assert("1: |[A ≏ ≏ ] <AB(0,2),r> [B2 ≏ ≏ ] ![r0[C2 ◼︎0 ≏ ◻︎0 ≏ ◻︎0]] [r0[D2 ◻︎0 ≡ 🔵►0 ≏ ]] <r0<DE(2,0),l>> [r0[E ≏ ≏ ]]|")
        try p.assert("1: |[A ≏ ≏ ] <AB(0,2),r> [B2 ≏ ≏ ] ![r0[C2 ≏ ◼︎0 ≏ ◻︎0]] [r0[D2 ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] <r0<DE(2,0),l>> [r0[E ≏ ≏ ]]|")
        try p.assert("1: |[A ≏ ≏ ] <AB(0,2),r> [B2 ≏ ≏ ] ![C2 ≏ ≏ ] [r0[D2 ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] <r0<DE(2,0),l>> [r0[E ◻︎0 ≡ 🟡►0 ≏ ]]|")
        try p.assert("1: |[A ≏ ≏ ] <AB(0,2),r> [B2 ≏ ≏ ] ![C2 ≏ ≏ ] [D2 ≏ ≏ ] <DE(2,0),l> [r0[E ≏ ◼︎0 ≡ 🔴►0 ]]|")
    }

    func testRouteResolveSb1N() throws {
        let layout = LayoutLoopWithStations().newLayout()
        let train = layout.trains[0]
        let route = layout.routes[0]
        XCTAssertEqual(route.partialSteps.toStrings(layout), ["Station S", "b1:next", "Station N"])
        XCTAssertEqual(route.steps.description, "[]")

        try route.completePartialSteps(layout: layout, train: train)

        XCTAssertEqual(route.steps.toStrings(layout), ["Station S", "b1:next", "Station N"])
    }

    func testRouteResolveWithOnlyStartAndEndStationSpecified() throws {
        let layout = LayoutLoopWithStations().newLayout()
        let train = layout.trains[0]
        let route = layout.routes[1]

        for routeItem in route.partialSteps {
            if case let .station(station) = routeItem {
                let station = layout.stations[station.stationId]!
                for (index, _) in station.elements.enumerated() {
                    station.elements[index].direction = nil
                }
            }
        }

        XCTAssertEqual(route.partialSteps.description(layout), ["Station S", "Station N"])
        XCTAssertEqual(route.steps.description(layout), [])

        let resolver = RouteResolver(layout: layout, train: train)
        let results = try resolver.resolve(unresolvedPath: route.partialSteps)
        switch results {
        case let .success(resolvedPaths):
            XCTAssertEqual(resolvedPaths[0].toStrings(), ["s1:next", "ts2:(1>0)", "t1:(0>1)", "t2:(0>1)", "b1:next", "t4:(1>0)", "tn1:(0>1)", "n1:next"])
            XCTAssertEqual(resolvedPaths[1].toStrings(), ["s1:previous", "ts1:(1>0)", "b5:previous", "b4:previous", "tn2:(0>1)", "n1:previous"])

        case let .failure(error):
            XCTFail("Unexpected error: \(error.localizedDescription)")
        }
    }

    /// This test ensures that the speed is reduced enough (slower than the default brake speed) so the train can brake in block b1.
    /// We do that by artificially modifying the distance of the last feedback of block b1 in order for the distance from that feedback
    /// to the end of the block to be shorter than the distance needed for the train running at the default brake speed. This will force
    /// the algorithm to find a slower speed to make that work.
    func testRouteWithNotEnoughBrakingDistance() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let s1 = layout.block(named: "s1")

        let b1 = layout.block(named: "b1")

        let p = Package(layout: layout)

        try p.prepare(routeID: "r1", trainID: "0", fromBlockId: s1.uuid, position: .end)

        // Artificially modify the distance of the last feedback of block "b1" in order for it to be equal to the braking distance to stop the train.
        let d = try LayoutSpeed(layout: layout).distanceNeededToChangeSpeed(ofTrain: p.train, fromSpeed: LayoutFactory.DefaultBrakingSpeed, toSpeed: 0)
        b1.feedbacks[1].distance = b1.length! - d.distance

        try p.assert("r1: {r0{s1 ≏ ◼︎0 ≏ 🔴►0 }} <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ]")

        try p.start()

        try p.assert("r1: {r0{s1 ≏ ◼︎0 ≏ 🔵►0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ≏ ≏ ]]")
        try p.assert("r1: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ◼︎0 ≡ 🟡15►0 ≏ ]]")

        XCTAssertEqual(p.train.speed!.actualKph, 15)
        XCTAssertEqual(p.train.state, .braking)
        XCTAssertEqual(p.train.scheduling, .managed)

        try p.assert("r1: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ≏ ◼︎0 ≡ 🔴►0 ]]")
        XCTAssertEqual(p.train.speed!.actualKph, 0)
        XCTAssertEqual(p.train.state, .stopped)
        XCTAssertEqual(p.train.scheduling, .unmanaged)
    }

    func testRouteWithStopImmediately() throws {
        let layout = LayoutLoopWithStation().newLayout()
        let s1 = layout.block(named: "s1")

        let p = Package(layout: layout)

        try p.prepare(routeID: "r1", trainID: "0", fromBlockId: s1.uuid, position: .automatic)

        try p.assert("r1: {r0{s1 ≏ ◼︎0 ≏ 🔴►0 }} <t1{sr}(0,1),s> <t2{sr}(0,1),s> [b1 ≏ ≏ ]")

        try p.start()

        try p.assert("r1: {r0{s1 ≏ ◼︎0 ≏ 🔵►0 }} <r0<t1{sr}(0,1),s>> <r0<t2{sr}(0,1),s>> [r0[b1 ≏ ≏ ]]")
        try p.assert("r1: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ◼︎0 ≡ 🟡►0 ≏ ]]")

        // Stop the train for the first time - the train continues to run because it has not yet reached
        // the end of the block it is located in.
        p.stop()
        p.layoutController.waitUntilSettled()

        XCTAssertEqual(p.train.speed!.actualKph, LayoutFactory.DefaultBrakingSpeed)
        XCTAssertEqual(p.train.state, .braking)
        XCTAssertEqual(p.train.scheduling, .stopManaged)

        // Stop the train for the second time, this time, the train will stop immedately.
        p.stop()
        p.layoutController.waitUntilSettled()

        XCTAssertEqual(p.train.speed!.actualKph, 0)
        XCTAssertEqual(p.train.state, .stopped)
        XCTAssertEqual(p.train.scheduling, .unmanaged)

        try p.assert("r1: {s1 ≏ ≏ } <t1{sr}(0,1),s> <t2{sr}(0,1),s> [r0[b1 ◼︎0 ≏ 🔴►0 ≏ ]]")
    }

    func testStraightLine1WithIncompleteRoute() throws {
        let layout = LayoutPointToPoint().newLayout()

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "0", fromBlockId: "A", position: .end)

        XCTAssertEqual(p.route.partialSteps.description(layout), ["A:next", "C:next", "E:next"])
        XCTAssertEqual(p.route.steps.description(layout), ["A:next", "B:next", "C:next", "D:next", "E:next"])

        try p.assert("r1: |[r0[A ≏ ◼︎0 ≏ 🔴►0 ]] <AB> [B ≏ ≏ ] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")

        try p.start()

        XCTAssertTrue(p.train.scheduling == .managed)

        // A = 200
        // B=C=D=100
        // AB=DE=10
        // Train = 120
        // [A 20 ≏ 160 ≏ 20 ] <10> [B 20 ≏ 60 ≏ 20 ] [C 20 ≏ 60 ≏ 20 ] [D 20 ≏ 60 ≏ 20 ] <10> [E 20 ≏ 160 ≏ 20 ]
        try p.assert("r1: |[r0[A ≏ ◼︎0 ≏ 🔵►0 ]] <r0<AB>> [r0[B ≏ ≏ ]] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("r1: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB>> [r0[B ◻︎0 ≡ 🔵►0 ≏ ]] [r0[C ≏ ≏ ]] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("r1: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB>> [r0[B ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] [r0[C ≏ ≏ ]] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("r1: |[A ≏ ≏ ] <AB> [r0[B ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] [r0[C ◻︎0 ≡ 🔵►0 ≏ ]] [r0[D ≏ ≏ ]] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("r1: |[A ≏ ≏ ] <AB> [r0[B ≏ ◼︎0 ≏ ◻︎0 ]] [r0[C ◻︎0 ≏ ◻︎0 ≡ 🔵►0 ]] [r0[D ≏ ≏ ]] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("r1: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [r0[C ◼︎0 ≏ ◻︎0 ≏ ◻︎0]] [r0[D ◻︎0 ≡ 🟢►0 ≏ ]] <r0<DE(1,0)>> [r0[E ≏ ≏ ]]|")
        try p.assert("r1: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [r0[C ≏ ◼︎0 ≏ ◻︎0]] [r0[D ◻︎0 ≏ ◻︎0 ≡ 🟢►0 ]] <r0<DE(1,0)>> [r0[E ≏ ≏ ]]|")
        try p.assert("r1: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [C ≏ ≏ ] [r0[D ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] <r0<DE(1,0)>> [r0[E ◻︎0 ≡ 🟡►0 ≏ ]]|")
        try p.assert("r1: |[A ≏ ≏ ] <AB> [B ≏ ≏ ] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [r0[E ≏ ◼︎0 ≡ 🔴►0 ]]|")
    }

    /// Ensure the next feedback is properly determined when a loop is involved where there are more than one transition
    /// possible to reach the block that does the loop. In this case, we are using the complex layout with hidden station
    /// to run a train from (s3, previous) to (s3, next) via the block (L1, next)) > (L3, next) > (L1, previous).
    func testRouteWithLoop() throws {
        let layout = LayoutComplexWithHiddenStation().newLayout()
        layout.removeTrains()

        let train = layout.trains[0]
        let s3 = layout.block(named: "S3")

        let route = layout.route(named: "testRouteWithLoop")

        let p = Package(layout: layout)
        try p.prepare(routeID: route.id.uuid, trainID: train.id.uuid, fromBlockId: s3.id.uuid, position: .start, direction: .previous)

        train.locomotive!.length = 22
        train.wagonsLength = 0

        // Tip: use `try p.printASCII()` to get the inital ASCII representation
        try p.assert("r6: !{r16390{S3 ◼︎16390 ≏ ◻︎16390 ≏ ◻︎16390 ≏ 🔴►16390 }} <T15{ds}(3,2),s> <T18{sr}(0,2),r> [L1 ≏ ≏ ] <T19{sl}(1,0),s> <T20{sl}(1,0),s> <T22{sr}(0,2),r> [L3 ≏ ≏ ] <T21{sr}(2,0),r> <T22{sr}(1,0),r> <T20{sl}(0,1),s> <T19{sl}(0,1),s> ![L1 ≏ ≏ ] <T18{sr}(2,0),r> <T15{ds}(2,3),s> {r16390{S3 🔴►16390 ≏ ◻︎16390 ≏ ◻︎16390 ≏ ◼︎16390 }}")

        try p.start()

        try p.assert("r6: !{r16390{S3 ≏ ≏ ◼︎16390 ≏ 🔵►16390 }} <r16390<T15{ds}(3,2),s>> <r16390<T18{sr}(0,2),r>> [r16390[L1 ≏ ≏ ]] <r16390<T19{sl}(1,0),s>> <r16390<T20{sl}(1,0),s>> <r16390<T22{sr}(0,2),r>> [r16390[L3 ≏ ≏ ]] <T21{sr}(2,0),r> <r16390<T22{sr}(1,0),r>> <r16390<T20{sl}(0,1),s>> <r16390<T19{sl}(0,1),s>> ![r16390[L1 ≏ ≏ ]] <r16390<T18{sr}(2,0),r>> <r16390<T15{ds}(2,3),s>> {r16390{S3 🔵►16390 ≏ ◼︎16390 ≏ ≏ }}")

        try p.assert("r6: !{S3 ≏ ≏ ≏ } <T15{ds}(3,2),s> <r16390<T18{sr}(0,2),r>> [r16390[L1 ◼︎16390 ≡ 🔵►16390 ≏ ]] <r16390<T19{sl}(1,0),s>> <r16390<T20{sl}(1,0),s>> <r16390<T22{sr}(0,2),r>> [r16390[L3 ≏ ≏ ]] <T21{sr}(2,0),r> <r16390<T22{sr}(1,0),r>> <r16390<T20{sl}(0,1),s>> <r16390<T19{sl}(0,1),s>> ![r16390[L1 ≏ 🔵►16390 ≡ ◼︎16390 ]] <r16390<T18{sr}(2,0),r>> <T15{ds}(2,3),s> {S3 ≏ ≏ ≏ }")

        try p.assert("r6: !{S3 ≏ ≏ ≏ } <T15{ds}(3,2),s> <T18{sr}(0,2),r> [L1 ≏ ≏ ] <T19{sl}(1,0),s> <T20{sl}(1,0),s> <r16390<T22{sr}(0,2),r>> [r16390[L3 ◼︎16390 ≡ 🟡►16390 ≏ ]] <T21{sr}(2,0),r> <r16390<T22{sr}(1,0),r>> <T20{sl}(0,1),s> <T19{sl}(0,1),s> ![L1 ≏ ≏ ] <T18{sr}(2,0),r> <T15{ds}(2,3),s> {S3 ≏ ≏ ≏ }")
    }

    /// Test that a train that can move in any direction can start in a route that has a starting block
    /// that has different direction than the train located in that block.
    func testRouteChangeDirection() throws {
        let doc = LayoutDocument(layout: LayoutPointToPoint().newLayout())
        let layout = doc.layout
        let route = layout.route(named: "ABCDE")
        let train = layout.trains[0]
        let blockA = layout.block(named: "A")
        try doc.layoutController.setupTrainToBlock(train, blockA.id, naturalDirectionInBlock: .previous)

        train.locomotive?.allowedDirections = .forward
        XCTAssertThrowsError(try doc.start(trainId: train.id, withRoute: route.id, destination: nil))

        train.locomotive?.allowedDirections = .any
        XCTAssertNoThrow(try doc.start(trainId: train.id, withRoute: route.id, destination: nil))
    }

    func testASCIIProducer() throws {
        let layout = LayoutLoop1().newLayout().removeTrainGeometry()
        let producer = LayoutASCIIProducer(layout: layout)
        let route = layout.routes[0]
        let trainId = layout.trains[1].id

        let p = Package(layout: layout)
        try p.prepare(routeID: "r1", trainID: "1", fromBlockId: "b1", position: .start)

        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 🔴►1 ≏ ≏ }} <t0{sl}(0,1),s> [b2 ≏ ≏ ] <t1{sl}(0,2),l> [b3 ≏ ≏ ] <t0{sl}(2,0),l> !{r1{b1 ≏ ≏ 🔴►1 }}")

        try p.start()
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 🟢►1 ≏ ≏ }} <r1<t0{sl}(0,1),s>> [r1[b2 ≏ ≏ ]] <t1{sl}(0,2),l> [b3 ≏ ≏ ] <r1<t0{sl}(2,0),l>> !{r1{b1 ≏ ≏ 🟢►1 }}")

        p.toggle("f11")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 ≡ 🔵►1 ≏ }} <r1<t0{sl}(0,1),s>> [r1[b2 ≏ ≏ ]] <t1{sl}(0,2),l> [b3 ≏ ≏ ] <r1<t0{sl}(2,0),l>> !{r1{b1 ≏ 🔵►1 ≡ }}")

        p.toggle2("f11", "f12")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 ≏ ≡ 🟢►1 }} <r1<t0{sl}(0,1),s>> [r1[b2 ≏ ≏ ]] <t1{sl}(0,2),l> [b3 ≏ ≏ ] <r1<t0{sl}(2,0),l>> !{r1{b1 🟢►1 ≡ ≏ }}")

        p.toggle2("f12", "f21")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{b1 ≏ ≏ } <t0{sl}(0,1),s> [r1[b2 ≡ 🔵►1 ≏ ]] <r1<t1{sl}(0,2),l>> [r1[b3 ≏ ≏ ]] <t0{sl}(2,0),l> !{b1 ≏ ≏ }")

        p.toggle2("f21", "f22")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{b1 ≏ ≏ } <t0{sl}(0,1),s> [r1[b2 ≏ ≡ 🟢►1 ]] <r1<t1{sl}(0,2),l>> [r1[b3 ≏ ≏ ]] <t0{sl}(2,0),l> !{b1 ≏ ≏ }")

        p.toggle2("f22", "f31")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 ≏ ≏ }} <r1<t0{sl}(0,1),s>> [b2 ≏ ≏ ] <t1{sl}(0,2),l> [r1[b3 ≡ 🔵►1 ≏ ]] <r1<t0{sl}(2,0),l>> !{r1{b1 ≏ ≏ }}")

        p.toggle2("f31", "f32")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 ≏ ≏ }} <r1<t0{sl}(0,1),s>> [b2 ≏ ≏ ] <t1{sl}(0,2),l> [r1[b3 ≏ ≡ 🟢►1 ]] <r1<t0{sl}(2,0),l>> !{r1{b1 ≏ ≏ }}")

        p.toggle2("f32", "f12")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 ≏ 🟡►1 ≡ }} <t0{sl}(0,1),s> [b2 ≏ ≏ ] <t1{sl}(0,2),l> [b3 ≏ ≏ ] <t0{sl}(2,0),l> !{r1{b1 ≡ 🟡►1 ≏ }}")

        p.toggle2("f12", "f11")
        XCTAssertEqual(try producer.stringFrom(route: route, trainId: trainId), "{r1{b1 🔴►1 ≡ ≏ }} <t0{sl}(0,1),s> [b2 ≏ ≏ ] <t1{sl}(0,2),l> [b3 ≏ ≏ ] <t0{sl}(2,0),l> !{r1{b1 ≏ ≡ 🔴►1 }}")
    }
}
