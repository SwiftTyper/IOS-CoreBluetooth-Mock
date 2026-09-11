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

/// Mock implementation of the ``CBMPeripheralManager``.
///
/// This implementation will interact only with mock centrals created using
/// ``CBMCentralSpec``. The state of the Bluetooth adapter is shared with
/// ``CBMCentralManagerMock`` and can be controlled using
/// ``CBMCentralManagerMock/simulatePowerOn()``, ``CBMCentralManagerMock/simulatePowerOff()``
/// and other simulation methods.
open class CBMPeripheralManagerMock: CBMPeripheralManager {

    /// A list of all mock peripheral managers instantiated by user.
    private static var managers: [WeakRef<CBMPeripheralManagerMock>] = []
    /// A list of mock centrals currently connected to the simulated device.
    private static var centrals: [WeakRef<CBMCentralSpec>] = []
    /// A mutex queue for managing managers and centrals.
    private static let mutex: DispatchQueue = DispatchQueue(label: "Mutex")

    /// Size of the transmit queue for notifications and indications.
    ///
    /// Only this many updates can be sent without waiting for
    /// ``CBMPeripheralManagerDelegate/peripheralManagerIsReady(toUpdateSubscribers:)-1n35f``.
    private static let updateQueueSize = 20

    /// A list of all existing mock peripheral managers.
    internal static var existingManagers: [CBMPeripheralManagerMock] {
        return mutex.sync {
            managers.compactMap { $0.ref }
        }
    }

    /// A list of all mock centrals connected to the simulated device.
    internal static var connectedCentrals: [CBMCentralSpec] {
        return mutex.sync {
            centrals.compactMap { $0.ref }
        }
    }

    /// This method is called whenever the state of the Bluetooth adapter or
    /// the authorization status changes.
    ///
    /// All managers that are not in powered on state stop advertising and forget
    /// all published services and connected centrals.
    internal static func notifyManagers() {
        let existingManagers = self.existingManagers
        existingManagers.forEach { manager in
            // ...stop advertising and remove all services if state changed
            // to any other state than `.poweredOn`.
            if manager.state != .poweredOn {
                manager.reset()
            }
            // ...and notify delegate.
            manager.queue.async {
                manager.delegate?.peripheralManagerDidUpdateState(manager)
            }
        }
        // When the adapter is turned off, all centrals get disconnected.
        if CBMCentralManagerMock.managerState != .poweredOn {
            disconnectAllCentrals()
        }
        // Compact the list, if any of managers were disposed.
        mutex.sync {
            managers.removeAll { $0.ref == nil }
        }
    }

    /// Removes all peripheral manager instances and disconnects all mock centrals.
    ///
    /// This method is called from ``CBMCentralManagerMock/tearDownSimulation()``.
    internal static func tearDown() {
        mutex.sync {
            managers.removeAll()
        }
        disconnectAllCentrals()
    }

    private static func disconnectAllCentrals() {
        let connectedCentrals = self.connectedCentrals
        mutex.sync {
            centrals.removeAll()
        }
        connectedCentrals.forEach { $0.isConnected = false }
    }

    /// Method called when a mock central has connected to the simulated device.
    /// - Parameter central: The central that has connected.
    internal static func centralDidConnect(_ central: CBMCentralSpec) {
        mutex.sync {
            centrals.removeAll { $0.ref == nil }
            if !centrals.contains(where: { $0.ref === central }) {
                centrals.append(WeakRef(central))
            }
        }
    }

    /// Method called when a mock central has disconnected from the simulated device.
    ///
    /// All peripheral managers will be notified about the central unsubscribing from
    /// all characteristics it was subscribed to.
    /// - Parameter central: The central that has disconnected.
    internal static func centralDidDisconnect(_ central: CBMCentralSpec) {
        mutex.sync {
            centrals.removeAll { $0.ref == nil || $0.ref === central }
        }
        existingManagers.forEach { manager in
            manager.central(didDisconnect: central)
        }
    }

    /// Returns the mock peripheral manager that has published the service containing
    /// the given characteristic, or `nil` if the characteristic was not published.
    /// - Parameter characteristic: The characteristic to look for.
    internal static func manager(owning characteristic: CBMCharacteristic) -> CBMPeripheralManagerMock? {
        return existingManagers.first { $0.owns(characteristic) }
    }

    /// The dispatch queue used for all callbacks.
    internal let queue: DispatchQueue
    /// A mutex queue for synchronizing access to the transmit queue.
    private let mutex: DispatchQueue = DispatchQueue(label: "Mutex")
    /// A list of published services.
    private var services: [CBMMutableService] = []
    /// The data that is currently being advertised.
    private var advertisementData: [String : Any]?
    /// A map of centrals known to this peripheral manager.
    private var centrals: [UUID : CBMCentralMock] = [:]
    /// A list of requests that have not been responded to yet.
    private var pendingRequests: [CBMATTRequestMock] = []
    /// Number of updates in the transmit queue.
    private var pendingUpdates: Int = 0
    /// A flag set to true when ``updateValue(_:for:onSubscribedCentrals:)``
    /// returned `false` due to the transmit queue being full.
    private var readyNotificationPending: Bool = false
    /// A flag set to true few milliseconds after the manager is created.
    /// Some features, like the state are not available when manager hasn't
    /// been initialized yet.
    private var initialized: Bool {
        // This method returns true if the manager is added to
        // the list of managers.
        // Calling tearDownSimulation() will remove all managers
        // from that list, making them uninitialized again.
        CBMPeripheralManagerMock.mutex.sync {
            CBMPeripheralManagerMock.managers.contains { $0.ref == self }
        }
    }

    // MARK: - Initializers

    public init() {
        self.queue = DispatchQueue.main
        super.init(true)
        initialize()
    }

    public init(delegate: CBMPeripheralManagerDelegate?,
                queue: DispatchQueue?) {
        self.queue = queue ?? DispatchQueue.main
        super.init(true)
        self.delegate = delegate
        initialize()
    }

    public init(delegate: CBMPeripheralManagerDelegate?,
                queue: DispatchQueue?,
                options: [String : Any]?) {
        self.queue = queue ?? DispatchQueue.main
        super.init(true)
        self.delegate = delegate
        if let options = options,
           let identifierKey = options[CBMPeripheralManagerOptionRestoreIdentifierKey] as? String,
           let dict = CBMPeripheralManagerMock.simulateStateRestoration?(identifierKey) {
            var state: [String : Any] = [:]
            if let services = dict[CBMPeripheralManagerRestoredStateServicesKey] as? [CBMMutableService] {
                state[CBMPeripheralManagerRestoredStateServicesKey] = services
                self.services = services
            }
            if let advertisementData = dict[CBMPeripheralManagerRestoredStateAdvertisementDataKey] as? [String : Any] {
                state[CBMPeripheralManagerRestoredStateAdvertisementDataKey] = advertisementData
                self.advertisementData = advertisementData
                self.isAdvertising = true
            }
            delegate?.peripheralManager(self, willRestoreState: state)
        }
        initialize()
    }

    private func initialize() {
        queue.async { [weak self] in
            if let self = self {
                CBMPeripheralManagerMock.mutex.sync {
                    CBMPeripheralManagerMock.managers.append(WeakRef(self))
                }
                self.delegate?.peripheralManagerDidUpdateState(self)
            }
        }
    }

    // MARK: - Peripheral manager simulation methods

    /// This simulation method is called when a mock peripheral manager was
    /// created with an option to restore the state
    /// (``CBMPeripheralManagerOptionRestoreIdentifierKey``).
    ///
    /// The returned map, if not `nil`, will be passed to
    /// ``CBMPeripheralManagerDelegate/peripheralManager(_:willRestoreState:)-4tv1g`` before creation.
    /// - SeeAlso: ``CBMPeripheralManagerRestoredStateServicesKey``
    /// - SeeAlso: ``CBMPeripheralManagerRestoredStateAdvertisementDataKey``
    public static var simulateStateRestoration: ((_ identifierKey: String) -> [String : Any]?)?

    // MARK: - CBPeripheralManager mock methods

    open override var state: CBMManagerState {
        guard initialized else {
            return .unknown
        }
        guard CBMCentralManagerMock.isAuthorized else {
            return .unauthorized
        }
        return CBMCentralManagerMock.managerState
    }

    @available(iOS, introduced: 13.0, deprecated: 13.1)
    @available(macOS, introduced: 10.15)
    @available(tvOS, introduced: 13.0, deprecated: 13.1)
    @available(watchOS, introduced: 6.0, deprecated: 6.1)
    open override var authorization: CBMManagerAuthorization {
        if let rawValue = CBMCentralManagerMock.bluetoothAuthorization,
           let authorization = CBMManagerAuthorization(rawValue: rawValue) {
            return authorization
        } else {
            // If `simulateAuthorization(:)` was not called, .allowedAlways is assumed.
            return .allowedAlways
        }
    }

    @available(iOS 13.1, macOS 10.15, tvOS 13.1, watchOS 6.1, *)
    open override class var authorization: CBMManagerAuthorization {
        if let rawValue = CBMCentralManagerMock.bluetoothAuthorization,
           let authorization = CBMManagerAuthorization(rawValue: rawValue) {
            return authorization
        } else {
            // If `simulateAuthorization(:)` was not called, .allowedAlways is assumed.
            return .allowedAlways
        }
    }

    open override func startAdvertising(_ advertisementData: [String : Any]?) {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        // Advertising can be started only once.
        guard !isAdvertising else {
            queue.async { [weak self] in
                if let self = self {
                    self.delegate?.peripheralManagerDidStartAdvertising(self, error: CBMError(.alreadyAdvertising))
                }
            }
            return
        }
        // Only the local name and the list of service UUIDs are supported.
        var data: [String : Any] = [:]
        if let name = advertisementData?[CBMAdvertisementDataLocalNameKey] as? String {
            data[CBMAdvertisementDataLocalNameKey] = name
        }
        if let serviceUUIDs = advertisementData?[CBMAdvertisementDataServiceUUIDsKey] as? [CBMUUID] {
            data[CBMAdvertisementDataServiceUUIDsKey] = serviceUUIDs
        }
        let unsupportedKeys = advertisementData?.keys.filter { key in
            key != CBMAdvertisementDataLocalNameKey && key != CBMAdvertisementDataServiceUUIDsKey
        } ?? []
        if !unsupportedKeys.isEmpty {
            NSLog("Warning: Advertisement data keys \(unsupportedKeys) are not supported and will be ignored")
        }
        self.advertisementData = data
        queue.async { [weak self] in
            // Advertising may have been stopped in the meantime.
            if let self = self, self.state == .poweredOn, self.advertisementData != nil {
                self.isAdvertising = true
                self.delegate?.peripheralManagerDidStartAdvertising(self, error: nil)
            }
        }
    }

    open override func stopAdvertising() {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        isAdvertising = false
        advertisementData = nil
    }

    open override func setDesiredConnectionLatency(_ latency: CBMPeripheralManagerConnectionLatency,
                                                   for central: CBMCentral) {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        // The central must be known to this peripheral manager.
        guard let central = central as? CBMCentralMock,
              centrals[central.identifier] === central else {
            return
        }
        central.spec.desiredConnectionLatency = latency
    }

    open override func add(_ service: CBMMutableService) {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        // The same service instance can be added only once.
        guard !services.contains(where: { $0 === service }) else {
            NSLog("[CoreBluetoothMock] API MISUSE: Service \(service.uuid) has already been added")
            report(service, error: CBMError(.invalidParameters))
            return
        }
        // All characteristics must be mutable.
        guard let characteristics = (service.characteristics ?? []) as? [CBMMutableCharacteristic] else {
            NSLog("[CoreBluetoothMock] API MISUSE: All characteristics of service \(service.uuid) must be CBMMutableCharacteristic")
            report(service, error: CBMError(.invalidParameters))
            return
        }
        // Characteristics with cached values must be read-only.
        let readOnly = characteristics.allSatisfy { characteristic in
            characteristic.value == nil ||
            (characteristic.properties.isSubset(of: .read) &&
             characteristic.permissions.isSubset(of: [.readable, .readEncryptionRequired]))
        }
        guard readOnly else {
            NSLog("[CoreBluetoothMock] API MISUSE: Characteristics with cached values must be read-only")
            report(service, error: CBMError(.invalidParameters))
            return
        }
        services.append(service)
        report(service, error: nil)
    }

    private func report(_ service: CBMMutableService, error: Error?) {
        queue.async { [weak self] in
            if let self = self, self.state == .poweredOn {
                self.delegate?.peripheralManager(self, didAdd: service, error: error)
            }
        }
    }

    open override func remove(_ service: CBMMutableService) {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        guard let index = services.firstIndex(where: { $0 === service }) else {
            return
        }
        services.remove(at: index)
        unsubscribeAllCentrals(from: service)
    }

    open override func removeAllServices() {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        services.forEach { unsubscribeAllCentrals(from: $0) }
        services.removeAll()
    }

    open override func respond(to request: CBMATTRequest, withResult result: CBMATTError.Code) {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        // The request must be pending.
        guard let request = request as? CBMATTRequestMock,
              let index = pendingRequests.firstIndex(where: { $0 === request }) else {
            NSLog("[CoreBluetoothMock] API MISUSE: \(request) is not pending, or has already been responded to")
            return
        }
        pendingRequests.remove(at: index)
        request.respond(result)
    }

    open override func updateValue(_ value: Data,
                                   for characteristic: CBMMutableCharacteristic,
                                   onSubscribedCentrals centrals: [CBMCentral]?) -> Bool {
        // Peripheral manager must be in powered on state.
        guard ensurePoweredOn() else { return false }
        // The characteristic must have been published by this peripheral manager.
        guard owns(characteristic) else {
            NSLog("[CoreBluetoothMock] API MISUSE: Characteristic \(characteristic.uuid) has not been added to \(self)")
            return false
        }
        // Get the list of subscribed and connected centrals that should be notified.
        let targets = (characteristic.subscribedCentrals ?? [])
            .compactMap { $0 as? CBMCentralMock }
            .filter { central in
                centrals?.contains(where: { $0.identifier == central.identifier }) ?? true
            }
            .filter { $0.spec.isConnected }
        // If no central is subscribed, the update is dropped, but the method succeeds.
        guard !targets.isEmpty else {
            return true
        }
        // Emulate the limited size of the transmit queue.
        let enqueued: Bool = mutex.sync {
            guard pendingUpdates < CBMPeripheralManagerMock.updateQueueSize else {
                readyNotificationPending = true
                return false
            }
            pendingUpdates += 1
            return true
        }
        guard enqueued else {
            return false
        }
        // Each central receives the update a connection interval later.
        var delay: TimeInterval = 0
        targets.forEach { central in
            let spec = central.spec
            // Values longer than the maximum update value length are truncated.
            let data = Data(value.prefix(central.maximumUpdateValueLength))
            delay = max(delay, spec.connectionInterval)
            queue.asyncAfter(deadline: .now() + spec.connectionInterval) { [weak self] in
                guard let self = self, self.state == .poweredOn,
                      spec.isConnected, self.owns(characteristic),
                      characteristic.subscribedCentrals?.contains(where: {
                          $0.identifier == central.identifier
                      }) ?? false else {
                    return
                }
                spec.delegate?.central(spec, didReceiveUpdate: data, for: characteristic)
            }
        }
        // When the update is sent, there is space in the transmit queue again.
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            let notifyReady: Bool = self.mutex.sync {
                self.pendingUpdates -= 1
                if self.readyNotificationPending &&
                   self.pendingUpdates < CBMPeripheralManagerMock.updateQueueSize {
                    self.readyNotificationPending = false
                    return true
                }
                return false
            }
            if notifyReady && self.state == .poweredOn {
                self.delegate?.peripheralManagerIsReady(toUpdateSubscribers: self)
            }
        }
        return true
    }

    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open override func publishL2CAPChannel(withEncryption encryptionRequired: Bool) {
        fatalError("L2CAP mock is not implemented")
    }

    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open override func unpublishL2CAPChannel(_ PSM: CBML2CAPPSM) {
        fatalError("L2CAP mock is not implemented")
    }

    fileprivate func ensurePoweredOn() -> Bool {
        guard state == .poweredOn else {
            NSLog("[CoreBluetoothMock] API MISUSE: \(self) can only accept this command while in the powered on state")
            return false
        }
        return true
    }

    /// Stops advertising, removes all services, pending requests and centrals.
    ///
    /// This method is called when the Bluetooth adapter is turned off.
    private func reset() {
        isAdvertising = false
        advertisementData = nil
        services.forEach { unsubscribeAllCentrals(from: $0) }
        services.removeAll()
        pendingRequests.removeAll()
        centrals.removeAll()
        mutex.sync {
            pendingUpdates = 0
            readyNotificationPending = false
        }
    }

    private func unsubscribeAllCentrals(from service: CBMService) {
        service.characteristics?
            .compactMap { $0 as? CBMMutableCharacteristic }
            .forEach { $0.subscribedCentrals = nil }
    }

    // MARK: - Central simulation methods

    /// Returns whether the given characteristic has been published by this manager.
    /// - Parameter characteristic: The characteristic to look for.
    internal func owns(_ characteristic: CBMCharacteristic) -> Bool {
        return services.contains { service in
            service.characteristics?.contains { $0 === characteristic } ?? false
        }
    }

    /// The data that is currently being advertised, or `nil` if the manager
    /// is not advertising.
    internal var currentAdvertisementData: [String : Any]? {
        return isAdvertising ? advertisementData : nil
    }

    /// The services published by this manager.
    internal var publishedServices: [CBMMutableService] {
        return services
    }

    /// Returns the local ``CBMCentralMock`` instance for the given central
    /// specification, creating it if needed.
    /// - Parameter spec: The central specification.
    private func central(for spec: CBMCentralSpec) -> CBMCentralMock {
        if let central = centrals[spec.identifier] {
            return central
        }
        let central = CBMCentralMock(basedOn: spec)
        centrals[spec.identifier] = central
        return central
    }

    /// Method called when a mock central has disconnected.
    ///
    /// The delegate will be notified about the central unsubscribing from all
    /// characteristics.
    /// - Parameter spec: The central that has disconnected.
    fileprivate func central(didDisconnect spec: CBMCentralSpec) {
        guard let central = centrals.removeValue(forKey: spec.identifier) else {
            return
        }
        pendingRequests.removeAll { $0.central.identifier == spec.identifier }
        services.forEach { service in
            service.characteristics?
                .compactMap { $0 as? CBMMutableCharacteristic }
                .forEach { characteristic in
                    guard characteristic.subscribedCentrals?.contains(where: {
                        $0.identifier == central.identifier
                    }) ?? false else {
                        return
                    }
                    characteristic.subscribedCentrals?.removeAll {
                        $0.identifier == central.identifier
                    }
                    queue.async { [weak self] in
                        if let self = self, self.state == .poweredOn {
                            self.delegate?.peripheralManager(self,
                                                             central: central,
                                                             didUnsubscribeFrom: characteristic)
                        }
                    }
                }
        }
    }

    /// Simulates a mock central enabling notifications or indications on the
    /// given characteristic.
    /// - Parameters:
    ///   - spec: The central specification.
    ///   - characteristic: The target characteristic.
    internal func central(_ spec: CBMCentralSpec,
                          didSubscribeTo characteristic: CBMMutableCharacteristic) {
        queue.asyncAfter(deadline: .now() + spec.connectionInterval) { [weak self] in
            guard let self = self, self.state == .poweredOn,
                  spec.isConnected, self.owns(characteristic) else {
                return
            }
            let central = self.central(for: spec)
            var subscribedCentrals = characteristic.subscribedCentrals ?? []
            guard !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) else {
                return
            }
            subscribedCentrals.append(central)
            characteristic.subscribedCentrals = subscribedCentrals
            self.delegate?.peripheralManager(self, central: central, didSubscribeTo: characteristic)
        }
    }

    /// Simulates a mock central disabling notifications or indications on the
    /// given characteristic.
    /// - Parameters:
    ///   - spec: The central specification.
    ///   - characteristic: The target characteristic.
    internal func central(_ spec: CBMCentralSpec,
                          didUnsubscribeFrom characteristic: CBMMutableCharacteristic) {
        queue.asyncAfter(deadline: .now() + spec.connectionInterval) { [weak self] in
            guard let self = self, self.state == .poweredOn,
                  spec.isConnected, self.owns(characteristic),
                  let central = self.centrals[spec.identifier],
                  characteristic.subscribedCentrals?.contains(where: {
                      $0.identifier == central.identifier
                  }) ?? false else {
                return
            }
            characteristic.subscribedCentrals?.removeAll { $0.identifier == central.identifier }
            self.delegate?.peripheralManager(self, central: central, didUnsubscribeFrom: characteristic)
        }
    }

    /// Simulates a read request sent from a mock central.
    ///
    /// Characteristics with cached values are handled automatically, without
    /// involving the delegate.
    /// - Parameters:
    ///   - spec: The central specification.
    ///   - characteristic: The target characteristic.
    ///   - offset: The offset of the first byte to read.
    ///   - completion: The completion handler called with the result of the request.
    internal func central(_ spec: CBMCentralSpec,
                          didRequestReadOf characteristic: CBMMutableCharacteristic,
                          offset: Int,
                          completion: @escaping (Result<Data, Error>) -> Void) {
        let queue = self.queue
        let interval = spec.connectionInterval
        let reply: (Result<Data, Error>) -> Void = { result in
            queue.asyncAfter(deadline: .now() + interval) {
                completion(result)
            }
        }
        // Only readable characteristics can be read.
        guard characteristic.properties.contains(.read) else {
            reply(.failure(CBMATTError(.readNotPermitted)))
            return
        }
        // Characteristics with cached values are handled by the system.
        if let value = characteristic.value {
            guard offset <= value.count else {
                reply(.failure(CBMATTError(.invalidOffset)))
                return
            }
            reply(.success(value.subdata(in: offset..<value.count)))
            return
        }
        let central = self.central(for: spec)
        let request = CBMATTRequestMock(central: central,
                                        characteristic: characteristic,
                                        offset: offset,
                                        value: nil) { request, result in
            if result == .success {
                reply(.success(request.value ?? Data()))
            } else {
                reply(.failure(CBMATTError(result)))
            }
        }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self = self, self.state == .poweredOn,
                  spec.isConnected, self.owns(characteristic) else {
                reply(.failure(CBMError(.notConnected)))
                return
            }
            self.pendingRequests.append(request)
            self.delegate?.peripheralManager(self, didReceiveRead: request)
        }
    }

    /// Simulates a write request or command sent from a mock central.
    /// - Parameters:
    ///   - spec: The central specification.
    ///   - data: The data to write.
    ///   - characteristic: The target characteristic.
    ///   - offset: The offset of the first byte to write.
    ///   - withResponse: Whether the write is a request (`true`) or a command (`false`).
    ///   - completion: The completion handler called with the result of the request.
    ///                 Not called for write commands.
    internal func central(_ spec: CBMCentralSpec,
                          didRequestWrite data: Data,
                          to characteristic: CBMMutableCharacteristic,
                          offset: Int,
                          withResponse: Bool,
                          completion: ((Result<Void, Error>) -> Void)?) {
        let queue = self.queue
        let interval = spec.connectionInterval
        let reply: (Result<Void, Error>) -> Void = { result in
            queue.asyncAfter(deadline: .now() + interval) {
                completion?(result)
            }
        }
        // Only writable characteristics can be written.
        let permitted = withResponse ?
            characteristic.properties.contains(.write) :
            characteristic.properties.contains(.writeWithoutResponse)
        guard permitted else {
            reply(.failure(CBMATTError(.writeNotPermitted)))
            return
        }
        // The maximum length of an attribute value is 512 bytes.
        guard offset + data.count <= 512 else {
            reply(.failure(CBMATTError(.invalidAttributeValueLength)))
            return
        }
        let central = self.central(for: spec)
        let request = CBMATTRequestMock(central: central,
                                        characteristic: characteristic,
                                        offset: offset,
                                        value: data,
                                        completion: withResponse ? { _, result in
            if result == .success {
                reply(.success(()))
            } else {
                reply(.failure(CBMATTError(result)))
            }
        } : nil)
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self = self, self.state == .poweredOn,
                  spec.isConnected, self.owns(characteristic) else {
                reply(.failure(CBMError(.notConnected)))
                return
            }
            self.pendingRequests.append(request)
            self.delegate?.peripheralManager(self, didReceiveWrite: [request])
        }
    }

    open override var debugDescription: String {
        return "<CBMPeripheralManager: services: \(services.count), advertising: \(isAdvertising)>"
    }
}
