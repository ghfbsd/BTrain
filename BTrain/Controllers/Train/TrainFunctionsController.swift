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

import Foundation

final class TrainFunctionsController {
    let catalog: LocomotiveFunctionsCatalog?
    let interface: CommandInterface
    var active: UInt8 = 0

    internal init(catalog: LocomotiveFunctionsCatalog?, interface: CommandInterface) {
        self.catalog = catalog
        self.interface = interface
    }

    func execute(functions: RouteItemFunctions, train: Train) {
        guard let functions = functions.functions else {
            return
        }

        guard let locomotive = train.locomotive else {
            return
        }

        BTLogger.debug("Execute \(functions.count) functions for train '\(train.name)'")

        for f in functions {
            let def: CommandLocomotiveFunction
            if let locFunction = f.locFunction {
                def = locFunction
            } else if let definition = locomotive.functions.definitions.first(where: { $0.type == f.type }) {
                def = definition
            } else {
                BTLogger.warning("Function \(f.type) not found in locomotive \(locomotive)")
                continue
            }

            let act = switch(f.trigger){case .enable: "Enable"; case .disable: "Disable"; case .pulse: "Pulse"}
            if let name = catalog?.name(for: def.type) {
                BTLogger.debug("\(act) function \(name) of type \(def.type) at index \(def.nr) with \(locomotive.name)")
            } else {
                BTLogger.debug("\(act) function of type \(def.type) at index \(def.nr) with \(locomotive.name)")
            }

            active += 1
            execute(locomotive: locomotive, function: def, trigger: f.trigger, duration: f.duration)
        }
    }

    func execute(locomotive: Locomotive, function: CommandLocomotiveFunction, trigger: RouteItemFunction.Trigger, duration: TimeInterval) {
        switch trigger {
        case .enable, .disable:
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.executeSingle(locomotive: locomotive, function: function, trigger: trigger)
            }

        case .pulse:
            executePulse(locomotive: locomotive, function: function, duration: duration)
        }
    }

    private func executeSingle(locomotive: Locomotive, function: CommandLocomotiveFunction, trigger: RouteItemFunction.Trigger) {
        let initialValue = trigger == .disable ? 0 : 1
        interface.execute(command: .function(address: locomotive.address, decoderType: locomotive.decoder, index: function.nr, value: UInt8(initialValue)), completion: {
            self.active -= function.toggle ? 0 : 1
        })

        if function.toggle {
            // The Digital Controller (at least the CS3) does not toggle it back
            // automatically, so we have to do it.
            let finalValue = UInt8(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.interface.execute(command: .function(address: locomotive.address, decoderType: locomotive.decoder, index: function.nr, value: finalValue), completion: { self.active -= 1 })
            }
        }
    }

    private func executePulse(locomotive: Locomotive, function: CommandLocomotiveFunction, duration: TimeInterval) {
        let initialValue = UInt8(1)
        interface.execute(command: .function(address: locomotive.address, decoderType: locomotive.decoder, index: function.nr, value: initialValue), completion: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            let finalValue = UInt8(0)
            self.interface.execute(command: .function(address: locomotive.address, decoderType: locomotive.decoder, index: function.nr, value: finalValue), completion: { self.active -= 1 })
        }
    }
}
