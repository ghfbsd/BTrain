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

final class RouteFunctionsTests: BTTestCase {
    func testStartAndStopFunctions() throws {
        let layout = LayoutPointToPoint().newLayout()

        let p = Package(layout: layout)
        try p.prepare(routeID: "0", trainID: "0", fromBlockId: "A", position: .end)

        p.route.startFunctions = RouteItemFunctions(functions: [RouteItemFunction(type: 1)])
        p.route.stopFunctions = RouteItemFunctions(functions: [RouteItemFunction(type: 1, trigger: .disable)])

        p.loc.functions.definitions = [.init(nr: 0, state: 0, type: 1)]

        try p.start()

        XCTAssertEqual(p.digitalController.triggeredFunctions.count, 1)
        XCTAssertEqual(p.digitalController.triggeredFunctions, [.init(address: 6, index: 0, value: 1)])

        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ 🔵►0 ]] <r0<AB>> [r0[B ≏ ≏ ]] [C ≏ ≏ ] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[r0[A ≏ ◼︎0 ≏ ◻︎0 ]] <r0<AB>> [r0[B ◻︎0 ≡ 🔵►0 ≏ ]] [r0[C ≏ ≏ ]] [D ≏ ≏ ] <DE(1,0)> [E ≏ ≏ ]|")
        try p.assert("0: |[A ≏ ≏ ] <AB{sr}(0,1),s> [r0[B ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] [r0[C ◻︎0 ≡ 🔵►0 ≏ ]] [r0[D ≏ ≏ ]] <DE{sl}(1,0),s> [E ≏ ≏ ]|")
        try p.assert("0: |[A ≏ ≏ ] <AB{sr}(0,1),s> [B ≏ ≏ ] [r0[C ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] [r0[D ◻︎0 ≡ 🟢►0 ≏ ]] <r0<DE{sl}(1,0),s>> [r0[E ≏ ≏ ]]|")
        try p.assert("0: |[A ≏ ≏ ] <AB{sr}(0,1),s> [B ≏ ≏ ] [C ≏ ≏ ] [r0[D ◼︎0 ≏ ◻︎0 ≏ ◻︎0 ]] <r0<DE{sl}(1,0),s>> [r0[E ◻︎0 ≡ 🟡►0 ≏ ]]|")
        try p.assert("0: |[A ≏ ≏ ] <AB{sr}(0,1),s> [B ≏ ≏ ] [C ≏ ≏ ] [D ≏ ≏ ] <DE{sl}(1,0),s> [r0[E ≏ ◼︎0 ≡ 🔴►0 ]]|")

        XCTAssertEqual(p.digitalController.triggeredFunctions.count, 2)
        XCTAssertEqual(p.digitalController.triggeredFunctions, [.init(address: 6, index: 0, value: 1), .init(address: 6, index: 0, value: 0)])
    }
}
