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
import SwiftUI

/// Implementation of the CommandInterface for the Marklin Central Station 3
final class MarklinInterface: CommandInterface, ObservableObject {
    @AppStorage(SettingsKeys.CS3)
    var CS3 : MarklinCS3.GizmoType = .CS3
    
    var callbacks = CommandInterfaceCallbacks()
    
    var layout: Layout?

    var client: Client?

    let locomotivesFetcher = MarklinFetchLocomotives()
    
    var CDStreams: [UInt16: ConfigDataStream] = [:]

    typealias CompletionBlock = () -> Void
    private var disconnectCompletionBlocks: CompletionBlock?

    /// True if CAN messages should be collected. The ``BTrain/MarklinInterface/messages`` will be populated as the message arrive.
    @Published var collectMessages = false

    /// Public array of messages that the interface received from the CS3. Used mainly
    /// for debugging purpose.
    @Published var messages = [MarklinCANMessage]()

    /// Map of CAN message to pending completion block.
    ///
    /// This map is used to invoke the completion block for each command based on the acknowledgement from the Central Station.
    /// Note that the CAN message should be a in a raw format, meaning it should hold values that are constant between the command and its acknowledgement.
    /// For example, the hash field should be left out because it will change between the command and the corresponding acknowledgement.
    private var completionBlocks = [MarklinCANMessage: [CompletionBlock]]()

    private let resources = MarklinInterfaceResources()
    
    private var first = true

    /// Returns the URL of the CS3 server
    private var serverURL: URL? {
        guard let address = client?.address else {
            return nil
        }
        let port: String
        if address == "localhost" {
            // When running with the simulator locally, we need to append the port.
            port = ":8080"
        } else {
            // When running with a real CS3, do not use the port otherwise the CS3 won't respond correctly.
            port = ""
        }

        return URL(string: "http://\(address)\(port)")
    }

    func connect(server: String, port: UInt16, layout: Layout, onReady: @escaping () -> Void, onError: @escaping (Error) -> Void, onStop: @escaping () -> Void) {
        self.layout = layout
        client = Client(address: server, port: port)
        if let client = client {
            client.start { [weak self] in
                if let serverURL = self?.serverURL {
                    self?.resources.fetchResources(server: serverURL) {
                        onReady()
                    }
                } else {
                    BTLogger.error("Unable to retrieve the server URL")
                    onReady()
                }
            } onData: { [weak self] msg in
                DispatchQueue.main.async {
                    self?.onMessage(msg: msg)
                }
            } onError: { [weak self] error in
                self?.client = nil
                onError(error)
            } onStop: { [weak self] in
                DispatchQueue.main.async {
                    self?.disconnectCompletionBlocks?()
                }
                self?.client = nil
                onStop()
            }
        }
    }

    func disconnect(_ completion: @escaping CompletionBlock) {
        disconnectCompletionBlocks = completion
        completionBlocks.removeAll()
        client?.stop()
    }

    func execute(command: Command, completion: CompletionBlock? = nil) {
        if case .locomotives = command, let serverURL = serverURL {
            locomotivesFetcher.fetchLocomotives(server: serverURL) { [weak self] result in
                self?.callbacks.locomotivesQueries.all.forEach { $0(result) }
                completion?()
            }
        } else {
            guard let (message, priority) = MarklinCANMessage.from(command: command) else {
                completion?()
                return
            }

            send(message: message, priority: priority, completion: completion)
        }
    }

    // Maximum value of the speed parameters that can be specified in the CAN message.
    static let maxCANSpeedValue = 1000

    func speedValue(for steps: SpeedStep, decoder: DecoderType) -> SpeedValue {
        let v = Double(steps.value) * Double(MarklinInterface.maxCANSpeedValue) / Double(decoder.steps)
        let value = ceil(v)
        return SpeedValue(value: min(UInt16(MarklinInterface.maxCANSpeedValue), UInt16(value)))
    }

    func speedSteps(for value: SpeedValue, decoder: DecoderType) -> SpeedStep {
        guard value.value > 0 else {
            return .zero
        }

        let adjustedValue = min(value.value, UInt16(MarklinInterface.maxCANSpeedValue))
        let v = Double(adjustedValue) / Double(MarklinInterface.maxCANSpeedValue) * Double(decoder.steps)
        let roundedSteps = round(v)
        if roundedSteps == 0 {
            let ceiledSteps = ceil(v)
            return SpeedStep(value: UInt16(ceiledSteps))
        } else {
            return SpeedStep(value: UInt16(roundedSteps))
        }
    }

    func defaultLocomotiveFunctionAttributes() -> [CommandLocomotiveFunctionAttributes] {
        resources.locomotiveFunctions()
    }

    func locomotiveFunctionAttributesFor(type: UInt32) -> CommandLocomotiveFunctionAttributes {
        resources.locomotiveFunctionAttributesFor(type: type)
    }

    // MARK: -

    func onMessage(msg: MarklinCANMessage) {
        if collectMessages {
            messages.append(msg)
        }
        if msg.isAck {
            handleAcknowledgment(msg)
        } else {
            handleCommand(msg)
        }
    }

    static func isKnownMessage(msg: MarklinCANMessage) -> Bool {
        if MarklinCommand.from(message: msg) != nil {
            return true
        } else {
            let cmd = Command.from(message: msg)
            if case .unknown = cmd {
                return false
            } else {
                return true
            }
        }
    }

    private func handleCommand(_ msg: MarklinCANMessage) {
        if let cmd = MarklinCommand.from(message: msg) {
            // Handle any Marklin-specific command first
            switch cmd {
            case .configDataStream(hash: let hash, length: let length, CRC: let CRC, data: let data, descriptor: _):
                // Define and handle Config Data Streams from any device
                if length != nil {  // indicates start of a new stream
                    if CDStreams[hash] != nil {
                        let item = CDStreams[hash]!
                        BTLogger.error("Already have an unfinished stream for \(hash.toHex()) \(item.length())")
                    }
                    CDStreams[hash] = ConfigDataStream(length!, CRC!)
                } else {            // continues data on some stream
                    guard let item = CDStreams[hash] else {
                        BTLogger.error("No Config Data Stream for defined for \(hash.toHex()), but packet received")
                        return
                    }
                    item.extend(data)
                    if item.ready() && !item.corrupt() {
                        // Process the stream now
                        CDStreams.removeValue(forKey: hash)  // Finished with it now
                        callbacks.configChanges.all.forEach { $0(item.data) }
                    } else if item.ready() && item.corrupt() {
                        BTLogger.error("Corrupted Config Data Stream for \(hash.toHex()) \(item.length()), discarding")
                        CDStreams.removeValue(forKey: hash)
                    }
                }
                break
            case .discovery(UID: _, index: _, code: _, descriptor: _):
                assertionFailure("Should never send a discovery packet")
            case .bind(UID: _, addr: _, descriptor: _):
                break
            case .verify(UID: _, addr: _, descriptor: _):
                break
            }
            return
        }

        let cmd = Command.from(message: msg)
        switch cmd {
        case let .emergencyStop(address, decoderType, _, _):
            // Execute a command to query the direction of the locomotive at this particular address
            // The response from this command is going to be processed below in the case .direction
            execute(command: .queryDirection(address: address, decoderType: decoderType))

        case let .speed(address, decoderType, value, _, _):
            callbacks.speedChanges.all.forEach { $0(address, decoderType, value, msg.isAck) }

        default:
            break
        }
    }

    private func handleAcknowledgment(_ msg: MarklinCANMessage) {
        if let cmd = MarklinCommand.from(message: msg) {
            // Handle any Marklin-specific command first
            switch cmd {
            case .configDataStream:
                BTLogger.error("Should never see an ACK for a Config Data Stream (ignored)")
                break // ignore ack for this command
            case .discovery(let UID, let index, let code, _):
                BTLogger.debug("got discovery ack \(UID.toHex()) index \(index)")
                if index == 0x20 && code == 0x00 {
                    let loks = layout?.locomotives
                    if loks?.elements.count == 0 { return }
                    let lok = loks!.elements[0]
                    BTLogger.debug("starting registration for \(UID.toHex()) lok \(lok.name) address \(lok.address)")
                    send(message: MarklinCANMessageFactory.MFXbind(UID: UID, addr: UInt16(lok.address)), priority: .high)
                }
            case .bind(let UID, let addr, _):
                if msg.dlc != 6 {
                    BTLogger.error("MFX loco registration failed on bind")
                    break
                }
                BTLogger.debug("got MFX BIND ack for \(UID.toHex()) addr \(addr)")
                send(message: MarklinCANMessageFactory.MFXverify(UID: UID, addr: addr), priority: .high)
            case .verify(let UID, let addr, _):
                if msg.dlc == 6 { BTLogger.error("MFX loco registration failed on verify") }
                else if msg.dlc != 7 { BTLogger.error("MFX loco registration unexpected result (fail) on verify") }
                else {
                    BTLogger.debug("MFX loco \(UID.toHex()) registered as MFX \(addr)")
                }
            }
            return
        }

        // Handle generic command
        let cmd = Command.from(message: msg)
        switch cmd {
        case .go:
            triggerCompletionBlock(for: msg)
            callbacks.stateChanges.all.forEach { $0(true) }

        case .stop:
            triggerCompletionBlock(for: msg)
            callbacks.stateChanges.all.forEach { $0(false) }

        case let .speed(address, decoderType, value, _, _):
            if completionBlocks[msg.raw] == nil {
                // If there isn't a completion block for this speed change,
                // it is probably a programming or hardware error.
                BTLogger.error("Unexpected speed change completion for loco \(address.toHex())")
                let mask = decoderType?.mask ?? 0x3ff, addr = UInt16(address) & mask
                for block in completionBlocks.filter(
                       { addr == (( (UInt16($0.key.byte2) << 8) | UInt16($0.key.byte3) ) & mask) }
                ) {
                    // We are looking for a completion for a speed command ack from this loco
                    BTLogger.error("...forcing completion of \(block.key)")
                    triggerCompletionBlock(for: block.key)
                }
            } else {
                triggerCompletionBlock(for: msg)
            }
            callbacks.speedChanges.all.forEach { $0(address, decoderType, value, msg.isAck) }

        case let .direction(address, decoderType, direction, _, _):
            triggerCompletionBlock(for: msg)
            callbacks.directionChanges.all.forEach { $0(address, decoderType, direction) }

        case let .function(address, decoderType, index, value, _, _):
            triggerCompletionBlock(for: msg)
            callbacks.functionChanges.all.forEach { $0(address, decoderType, index, value) }

        case let .turnout(address, state, power, _, _):
            triggerCompletionBlock(for: msg)
            callbacks.turnoutChanges.all.forEach { $0(address, state, power, msg.isAck) }

        case let .feedback(deviceID, contactID, _, newValue, _, _, _):
            triggerCompletionBlock(for: msg)
            callbacks.feedbackChanges.all.forEach { $0(deviceID, contactID, newValue) }

        case .locomotives:
            triggerCompletionBlock(for: msg)

        default:
            break
        }
    }

    private func triggerCompletionBlock(for message: MarklinCANMessage) {
        if let blocks = completionBlocks[message.raw] {
            for completionBlock in blocks {
                completionBlock()
            }
            completionBlocks[message.raw] = nil
        }
    }

    private func send(message: MarklinCANMessage, priority: Command.Priority, completion: CompletionBlock? = nil) {
        guard let client = client else {
            BTLogger.error("Cannot send message to Digital Controller because the client is nil!")
            completion?()
            return
        }

        if let completion = completion {
            completionBlocks[message.raw] = (completionBlocks[message.raw] ?? []) + [completion]
        }

        if first && CS3 == .box {
            // Could send PING and check whether response includes an MS2 (or CS3!) to check for
            // master controller conflicts; if MS2/CS3 registers a loco it can cause problems if we
            // try to, too.
            client.send(data: MarklinCANMessageFactory.boot().data, priority: true, onCompletion: {})
            first = false
        }
        
        client.send(data: message.data, priority: priority == .high) {
            // no-op as we don't care about when the message is done being sent down the wire
        }
    }
}

extension MarklinInterface: MetricsProvider {
    var metrics: [Metric] {
        if let queue = client?.connection.dataQueue {
            return [.init(id: queue.name, value: String(queue.scheduledCount))]
        } else {
            return []
        }
    }
}

extension MarklinCS3.Lok {
    var decoderType: DecoderType? {
        switch dectyp {
        case "mfx+", "mfx":
            return .MFX
        case "mm":
            return .MM
        default:
            return nil
        }
    }

    func toCommand(icon: Data?) -> CommandLocomotive {
        let actualFunctions = funktionen.filter { $0.typ2 != 0 }
        let functions = actualFunctions.map { CommandLocomotiveFunction(nr: $0.nr, state: $0.state, type: $0.typ2, toggle: .value($0.isMoment)) }
        return CommandLocomotive(uid: uid.valueFromHex, name: name, address: address, maxSpeed: tachomax, decoderType: decoderType, icon: icon, functions: functions)
    }
}

extension String {
    var locomotiveDecoderType: DecoderType {
        switch self {
        case "mfx":
            return .MFX
        case "mm_prg":
            return .MM
        case "mm2_prg":
            return .MM2
        case "mm2_dil8":
            return .MM
        case "dcc":
            return .DCC
        case "sx1":
            return .SX1
        default:
            return .MFX
        }
    }
}

class ConfigDataStream: CustomStringConvertible {
   private var expectedLength: UInt32
   private var expectedCRC: UInt16
   private var actualLength: UInt32 = 0
   private var actualCRC: UInt16 = 0xffff

   var data: String = ""

   var description: String {
      return "length: \(expectedLength),\(actualLength); CRC \(expectedCRC.toHex()),\(actualCRC.toHex()); text:\n \(data)"
   }

   init(_ length: UInt32, _ CRC: UInt16) {
      self.expectedLength = length
      self.expectedCRC = CRC
   }

   private func CRC(_ byt: UInt8, _ old: UInt16) -> UInt16 {
      var acc = old ^ (UInt16(byt) << 8)
      for _ in 0...7 {
         if (acc & 0x8000) != 0 {
            acc = (acc << 1) ^ 0x1021
         } else {
            acc <<= 1
         }
      }
      return acc
   }

   func extend(_ str: [UInt8]) -> Void {
      self.data += String(bytes: str, encoding: .utf8)!
      self.actualLength += UInt32(str.count)
      for c in str {
         self.actualCRC = CRC(c, self.actualCRC)
      }
   }

   func ready() -> Bool {
      return self.actualLength >= self.expectedLength
   }

   func corrupt() -> Bool {
      return (
         (self.expectedCRC != self.actualCRC) ||
         (self.expectedLength != self.actualLength)
      )
   }
    
   func length() -> (UInt32,UInt32) {
       return (self.actualLength, self.expectedLength)
   }
}
