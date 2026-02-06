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

final class LayoutOnConnectTasks: ObservableObject {
    let layout: Layout
    let layoutController: LayoutController
    let interface: CommandInterface
    let catalog: LocomotiveFunctionsCatalog
    let discovery: LocomotiveDiscovery

    /// Property used to keep track of the progress
    @Published var connectionCompletionPercentage: Double? = nil
    @Published var connectionCompletionLabel: String? = nil

    var cancel = false
    var namestream: AsyncStream<String>?
    var namecont: AsyncStream<String>.Continuation?
    var lokstream: AsyncStream<CommandLocomotive?>?
    var lokcont: AsyncStream<CommandLocomotive?>.Continuation?

    init(layout: Layout, layoutController: LayoutController, interface: CommandInterface, locFuncCatalog: LocomotiveFunctionsCatalog, locomotiveDiscovery: LocomotiveDiscovery) {
        self.layout = layout
        self.layoutController = layoutController
        self.interface = interface
        self.catalog = locFuncCatalog
        self.discovery = locomotiveDiscovery
    }

    func performOnConnectTasks(simulator: Bool, activateTurnouts: Bool, completion: @escaping CompletionBlock) {
        cancel = false
        notifyProgress(label: "Fetching Locomotives", activateTurnouts: activateTurnouts, step: 0)
        fetchLocomotives {
            self.notifyProgress(label: "Querying Locomotives", activateTurnouts: activateTurnouts, step: 1)
            self.queryLocomotivesDirection {
                if activateTurnouts {
                    self.notifyProgress(label: "Activate Turnouts", activateTurnouts: activateTurnouts, step: 2)
                    self.layoutController.go {
                        self.applyTurnoutStateToDigitalController {
                            completion()
                        }
                    }
                } else {
                    self.notifyProgress(label: "Done", activateTurnouts: activateTurnouts, step: 2)
                    if !simulator {
                        // With the real digital controller, always start in stop mode by security
                        self.layoutController.stop {
                            completion()
                        }
                    } else {
                        completion()
                    }
                }
            }
        }
        
        if [.MS2,.box].contains( MarklinInterface().CS3 ) {
            // If not a CS2/CS3, set up a task to monitor Config Data Stream to catch
            // locomotive definitions. This procedure is called repetitively, so we only
            // want to define the callback once!
            if interface.callbacks.configChanges.all.count == 0 {
                interface.callbacks.register(forConfigDataStream: getConfigData)
            }
        }
    }
    
    private func lokCheck(_ name: String, _ mfxuid: UInt32) -> Bool {
        let sameName = layout.locomotives.elements.first(where:{$0.name == name})
        let sameUID = layout.locomotives.elements.first(where:{UInt32($0.uuid) == mfxuid})
        return ( sameName != nil && sameUID != nil && sameName == sameUID ) ? true : false
    }
    
    private func getConfigData(text: String){
        // Callback to handle complete Config Data Stream to see if it is of any interest
        var lines = text.split(whereSeparator: \.isNewline)
        let title = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        lines.remove(at:0)

        if title == "[lokliste]" {
            // This gives us the names of all of the locomotives
            var loks = [String](), names = [String](), name = "", uid = UInt32(0)
            for line in lines {
                let item = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "=")
                if item[0] == ".llindex" {
                    if name != "" { names.append(name) }
                    if name == "" || lokCheck(name, uid) { name = ""; continue }
                    loks.append(name); name = ""
                }
                if item[0] == ".name" { name = item[1] }
                if item[0] == ".mfxuid" { uid = item[1].valueFromHex ?? 0}
            }
            if name != "" { names.append(name); if lokCheck(name, uid) { loks.append(name) } }
            BTLogger.debug("[lokliste] found: \(names)")
            BTLogger.debug("[lokliste] querying: \(loks)")
            // Start a task to get info about each loco here; it would be run whenever a
            // [lokliste] stream is found.  This monitors manual changees to the loco list
            // on the MS2 (it rebroadcasts them after each change), as well as catching
            // the first .lokliste command issued on startup which defines/augments the
            // loco list.
            (namestream, namecont) = AsyncStream<String>.makeStream()
            (lokstream, lokcont) = AsyncStream<CommandLocomotive?>.makeStream()
            Task {
                var newloks = [CommandLocomotive](), newnames = [String]()
                for await lok in namestream! {
                    // Issue command to get a lokomotive data stream for the loco
                    // The result is a [lokomotive] data stream, processed below
                    try await Task.sleep(nanoseconds: 2_000_000_000) // important: let CAN bus quiesce
                    interface.execute(command: .lokinfo(name: lok), completion: {})
                    interface.execute(command: .lokinfo_(name: lok), completion: {})
                    interface.execute(command: .lokinfo__(name: lok), completion: {})
                    BTLogger.debug("Requesting \(lok)")
                    for await newlok in lokstream! {
                        if newlok == nil {break}
                        newloks.append(newlok!)
                    }
                    newnames.append(lok)
                }
                MainThreadQueue.sync {
                    BTLogger.debug("Registering \(newnames)")
                    discovery.process(locomotives: newloks, merge: true)
                }
            }
            for lok in loks {
                namecont!.yield(lok)
            }
            namecont!.finish()
        }
        
        if title == "[lokomotive]" {
            // This gives us all of the info about a particular locomotive
            // First parse into keyword = value dictionary
            var desc: [String : String] = [:]
            let multi = [".fkt","..nr","..typ","..dauer","..wert",".fkt2","..typ2","..dauer2","..wert2"]
            for line in lines {
                let item = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "=")
                if multi.contains(item[0]) { continue } // skip for later processing
                if item.count == 1 { desc[item[0]] = ""} else { desc[item[0]] = item[1] }
            }
            BTLogger.debug("Got [lokomotive] stream for \(desc[".name"] ?? "(unknown)")")
            
            // Accumulate function list
            // It should be possible to add function icons here, too
            var fns = [CommandLocomotiveFunction](), typ = 0, dauer = 0, wert = 0, nr = 0
            for line in lines {
                let item = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "="), it = item[0]
                if it == ".fkt" || it == ".fkt2"{
                    if typ+dauer+wert == 0 { continue } // only interested in functions
                    fns.append(CommandLocomotiveFunction(nr: UInt8(nr), state: UInt8(wert), type: UInt32(typ)))
                    typ = 0; dauer = 0; wert = 0; nr += 1
                    continue
                }
                if item.count > 1 && multi.contains(it) {
                    if it == "..typ" || it == "..typ2" { typ = Int(item[1]) ?? 0 }
                    if it == "..dauer" || it == "..dauer2" { dauer = Int(item[1]) ?? 0 }
                    if it == "..wert" || it == "..wert2" { wert = Int(item[1]) ?? 0 }
                }
            }
            fns.append(CommandLocomotiveFunction(nr: UInt8(nr), state: UInt8(wert), type: UInt32(typ)))
            
            let decoder = desc[".typ"] ?? "unknown"
            let vmax = SpeedStep(value: UInt16(desc[".vmax"]!) ?? 255)
            let dtyp: DecoderType =
                decoder == "dcc" ?      .DCC :
                decoder == "mfx" ?      .MFX :
                decoder == "mm2_prg" ?  .MM2 :
                decoder == "mm2_dil8" ? .MM2 :
                decoder == "sx1" ?      .SX1 :
                                        .DCC
            let speed = LocomotiveSpeed(steps: vmax, decoderType: dtyp)
            let maxSpeed = speed.speedKph(for: vmax)
            let lok = CommandLocomotive(
                uid: desc[".mfxuid"]!.valueFromHex ?? 0xffffffff,
                name: desc[".name"] ?? "(unknown)",
                address: desc[".adresse"]!.valueFromHex ?? 0,
                maxSpeed: UInt32(maxSpeed > 0 ? maxSpeed : speed.maxSpeed),
                decoderType: dtyp,
                icon: nil,
                functions: fns
            )
            lokcont!.yield(lok)
            lokcont!.yield(nil)
        }
    }

    private func notifyProgress(label: String, activateTurnouts: Bool, step: Int) {
        let progressPercentageStep = 1.0 / (activateTurnouts ? 3 : 2)
        connectionCompletionPercentage = Double(step) * progressPercentageStep
        connectionCompletionLabel = label
    }

    private func fetchLocomotives(completion: @escaping CompletionBlock) {
        catalog.globalAttributesChanged()

        discovery.discover(merge: true) {
            completion()
        }
    }

    private func queryLocomotivesDirection(completion: @escaping CompletionBlock) {
        let locomotives = layout.locomotives.elements.filter(\.enabled)
        guard !locomotives.isEmpty else {
            completion()
            return
        }

        var completionCount = 0
        for loc in locomotives {
            let command = Command.queryDirection(address: loc.address, decoderType: loc.decoder, descriptor: nil)
            interface.execute(command: command) {
                DispatchQueue.main.async {
                    completionCount += 1
                    if completionCount == locomotives.count {
                        completion()
                    }
                }
            }
        }
    }

    private func applyTurnoutStateToDigitalController(completion: @escaping CompletionBlock) {
        let turnouts = layout.turnouts.elements
        guard !turnouts.isEmpty else {
            completion()
            return
        }

        let delta = 1.0 - (connectionCompletionPercentage ?? 0)
        var activateTurnoutPercentage = 0.0
        var completionCount = 0
        for t in turnouts {
            layoutController.sendTurnoutState(turnout: t) { _ in
                guard self.cancel == false else {
                    return
                }
                completionCount += 1
                activateTurnoutPercentage = Double(completionCount) / Double(turnouts.count)
                self.connectionCompletionPercentage = 1.0 - delta + activateTurnoutPercentage / 1.0 * delta
                if completionCount == turnouts.count {
                    self.connectionCompletionPercentage = nil
                    self.connectionCompletionLabel = nil
                    completion()
                }
            }
        }
    }
}
