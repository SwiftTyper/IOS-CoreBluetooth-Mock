/*
* Copyright (c) 2026, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import CoreBluetooth

/// Specification of a mock central.
///
/// A mock central represents a remote device (e.g. a phone or a computer) that
/// connects to the simulated local device, which acts as a peripheral using
/// ``CBMPeripheralManagerMock``. The specification is used to simulate the
/// central's behavior: connecting, discovering advertisements, subscribing to
/// characteristics, reading and writing values.
///
/// The mock central interacts with all ``CBMPeripheralManagerMock`` instances,
/// as all of them share the same local GATT database.
///
/// Notifications and indications sent by the peripheral manager are delivered
/// to the ``CBMCentralSpec/delegate``.
public class CBMCentralSpec {
    /// The central identifier.
    public let identifier: UUID
    /// The maximum amount of data, in bytes, that the central can receive in a
    /// single notification or indication.
    public let maximumUpdateValueLength: Int
    /// The connection interval.
    ///
    /// Requests and updates are delivered a connection interval later.
    public let connectionInterval: TimeInterval
    /// The delegate that will receive notifications and indications.
    public var delegate: CBMCentralSpecDelegate?
    /// A flag indicating whether the central is connected to the simulated device.
    public internal(set) var isConnected: Bool = false
    /// The connection latency requested by a peripheral manager using
    /// ``CBMPeripheralManager/setDesiredConnectionLatency(_:for:)``, or `nil`
    /// if it was not set.
    public internal(set) var desiredConnectionLatency: CBMPeripheralManagerConnectionLatency?

    /// Creates a specification of a mock central.
    /// - Parameters:
    ///   - identifier: The central identifier. If not given, a random UUID will be used.
    ///   - maximumUpdateValueLength: The maximum amount of data, in bytes, that the
    ///                               central can receive in a single notification or
    ///                               indication. Defaults to 20 bytes (MTU 23 - 3).
    ///   - connectionInterval: The connection interval, in seconds.
    ///   - delegate: The delegate that will receive notifications and indications.
    public init(identifier: UUID = UUID(),
                maximumUpdateValueLength: Int = 20,
                connectionInterval: TimeInterval = 0.045,
                delegate: CBMCentralSpecDelegate? = nil) {
        self.identifier = identifier
        self.maximumUpdateValueLength = max(1, maximumUpdateValueLength)
        self.connectionInterval = connectionInterval
        self.delegate = delegate
    }

    /// Simulates the central scanning for the simulated local device.
    ///
    /// The method returns the advertisement data, which the central would receive
    /// from the local device, or `nil` if no peripheral manager is advertising,
    /// or the advertised services do not match the given filter.
    ///
    /// When multiple peripheral managers are advertising, the advertised service
    /// UUIDs are merged and the first local name is used.
    /// - Parameter serviceUUIDs: An optional list of service UUIDs to filter
    ///                           advertisements by. If `nil` or empty, any
    ///                           advertisement is returned.
    /// - Returns: The advertisement data, or `nil` if the local device is not
    ///            advertising matching services.
    public func simulateScan(withServices serviceUUIDs: [CBMUUID]? = nil) -> [String : Any]? {
        guard CBMCentralManagerMock.managerState == .poweredOn else {
            return nil
        }
        let advertisements = CBMPeripheralManagerMock.existingManagers
            .compactMap { $0.currentAdvertisementData }
        guard !advertisements.isEmpty else {
            return nil
        }
        var uuids: [CBMUUID] = []
        advertisements
            .compactMap { $0[CBMAdvertisementDataServiceUUIDsKey] as? [CBMUUID] }
            .flatMap { $0 }
            .forEach { uuid in
                if !uuids.contains(uuid) {
                    uuids.append(uuid)
                }
            }
        if let filter = serviceUUIDs, !filter.isEmpty,
           !uuids.contains(where: filter.contains) {
            return nil
        }
        var data: [String : Any] = [
            CBMAdvertisementDataIsConnectable : true as NSNumber
        ]
        if let name = advertisements
            .compactMap({ $0[CBMAdvertisementDataLocalNameKey] as? String })
            .first {
            data[CBMAdvertisementDataLocalNameKey] = name
        }
        if !uuids.isEmpty {
            data[CBMAdvertisementDataServiceUUIDsKey] = uuids
        }
        return data
    }

    /// Simulates the central connecting to the simulated local device.
    ///
    /// The Bluetooth adapter must be powered on. Peripheral managers are not
    /// notified about new connections, unless the central subscribes to a
    /// characteristic or sends a request.
    public func simulateConnection() {
        guard CBMCentralManagerMock.managerState == .poweredOn else {
            NSLog("Warning: Central can not connect when Bluetooth is not powered on")
            return
        }
        guard !isConnected else {
            return
        }
        isConnected = true
        CBMPeripheralManagerMock.centralDidConnect(self)
    }

    /// Simulates the central disconnecting from the simulated local device.
    ///
    /// All peripheral managers will be notified about the central unsubscribing
    /// from all characteristics it was subscribed to using
    /// ``CBMPeripheralManagerDelegate/peripheralManager(_:central:didUnsubscribeFrom:)-7k1ei``.
    public func simulateDisconnection() {
        guard isConnected else {
            return
        }
        isConnected = false
        CBMPeripheralManagerMock.centralDidDisconnect(self)
    }

    /// Simulates the central enabling notifications or indications on the
    /// given characteristic.
    ///
    /// The peripheral manager which published the characteristic will receive
    /// ``CBMPeripheralManagerDelegate/peripheralManager(_:central:didSubscribeTo:)-4jl9z``
    /// a connection interval later. The characteristic must have `.notify` or
    /// `.indicate` property, otherwise the request is ignored.
    /// - Parameter characteristic: The characteristic to subscribe to.
    public func simulateSubscription(to characteristic: CBMMutableCharacteristic) {
        guard isConnected else {
            NSLog("Warning: Central \(identifier) is not connected")
            return
        }
        guard !characteristic.properties.isDisjoint(with: [
            .notify, .indicate, .notifyEncryptionRequired, .indicateEncryptionRequired
        ]) else {
            NSLog("Warning: Characteristic \(characteristic.uuid) does not support notifications or indications")
            return
        }
        guard let manager = CBMPeripheralManagerMock.manager(owning: characteristic) else {
            NSLog("Warning: Characteristic \(characteristic.uuid) has not been published")
            return
        }
        manager.central(self, didSubscribeTo: characteristic)
    }

    /// Simulates the central disabling notifications or indications on the
    /// given characteristic.
    ///
    /// The peripheral manager which published the characteristic will receive
    /// ``CBMPeripheralManagerDelegate/peripheralManager(_:central:didUnsubscribeFrom:)-7k1ei``
    /// a connection interval later.
    /// - Parameter characteristic: The characteristic to unsubscribe from.
    public func simulateUnsubscription(from characteristic: CBMMutableCharacteristic) {
        guard isConnected else {
            NSLog("Warning: Central \(identifier) is not connected")
            return
        }
        guard let manager = CBMPeripheralManagerMock.manager(owning: characteristic) else {
            NSLog("Warning: Characteristic \(characteristic.uuid) has not been published")
            return
        }
        manager.central(self, didUnsubscribeFrom: characteristic)
    }

    /// Simulates a read request sent from the central.
    ///
    /// If the characteristic has a cached value, it is returned automatically.
    /// Otherwise, the peripheral manager which published the characteristic will
    /// receive ``CBMPeripheralManagerDelegate/peripheralManager(_:didReceiveRead:)-8sx65``
    /// a connection interval later and the completion handler will be called with
    /// the result after the peripheral manager responds using
    /// ``CBMPeripheralManager/respond(to:withResult:)``.
    /// - Parameters:
    ///   - characteristic: The characteristic to read.
    ///   - offset: The offset of the first byte to read.
    ///   - completion: The completion handler called with the value read, or
    ///                 an error (``CBMATTError`` or ``CBMError``).
    public func simulateReadRequest(for characteristic: CBMMutableCharacteristic,
                                    offset: Int = 0,
                                    completion: @escaping (Result<Data, Error>) -> Void) {
        guard isConnected else {
            completion(.failure(CBMError(.notConnected)))
            return
        }
        guard let manager = CBMPeripheralManagerMock.manager(owning: characteristic) else {
            completion(.failure(CBMATTError(.attributeNotFound)))
            return
        }
        manager.central(self, didRequestReadOf: characteristic,
                        offset: offset, completion: completion)
    }

    /// Simulates a write request (write with response) sent from the central.
    ///
    /// The peripheral manager which published the characteristic will receive
    /// ``CBMPeripheralManagerDelegate/peripheralManager(_:didReceiveWrite:)-1d33g``
    /// a connection interval later and the completion handler will be called with
    /// the result after the peripheral manager responds using
    /// ``CBMPeripheralManager/respond(to:withResult:)``.
    /// - Parameters:
    ///   - data: The data to write.
    ///   - characteristic: The characteristic to write.
    ///   - offset: The offset of the first byte to write.
    ///   - completion: The completion handler called when the write completes, or
    ///                 fails with an error (``CBMATTError`` or ``CBMError``).
    public func simulateWriteRequest(_ data: Data,
                                     for characteristic: CBMMutableCharacteristic,
                                     offset: Int = 0,
                                     completion: @escaping (Result<Void, Error>) -> Void) {
        guard isConnected else {
            completion(.failure(CBMError(.notConnected)))
            return
        }
        guard let manager = CBMPeripheralManagerMock.manager(owning: characteristic) else {
            completion(.failure(CBMATTError(.attributeNotFound)))
            return
        }
        manager.central(self, didRequestWrite: data, to: characteristic,
                        offset: offset, withResponse: true, completion: completion)
    }

    /// Simulates a write command (write without response) sent from the central.
    ///
    /// The peripheral manager which published the characteristic will receive
    /// ``CBMPeripheralManagerDelegate/peripheralManager(_:didReceiveWrite:)-1d33g``
    /// a connection interval later. The central is not notified about the result.
    /// - Parameters:
    ///   - data: The data to write.
    ///   - characteristic: The characteristic to write.
    public func simulateWriteCommand(_ data: Data,
                                     for characteristic: CBMMutableCharacteristic) {
        guard isConnected else {
            NSLog("Warning: Central \(identifier) is not connected")
            return
        }
        guard let manager = CBMPeripheralManagerMock.manager(owning: characteristic) else {
            NSLog("Warning: Characteristic \(characteristic.uuid) has not been published")
            return
        }
        manager.central(self, didRequestWrite: data, to: characteristic,
                        offset: 0, withResponse: false, completion: nil)
    }
}

extension CBMCentralSpec: Equatable {

    public static func == (lhs: CBMCentralSpec, rhs: CBMCentralSpec) -> Bool {
        return lhs.identifier == rhs.identifier
    }

}
