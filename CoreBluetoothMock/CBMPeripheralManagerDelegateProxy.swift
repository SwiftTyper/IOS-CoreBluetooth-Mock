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

/// A helper class that allows setting delegate callbacks as closures.
///
/// - SeeAlso: ``CBMPeripheralManagerDelegate``
open class CBMPeripheralManagerDelegateProxy: NSObject, CBMPeripheralManagerDelegate {
    public var didUpdateState: ((CBMPeripheralManager) -> ())?
    public var willRestoreState: ((CBMPeripheralManager, [String : Any]) -> ())?
    public var didStartAdvertising: ((CBMPeripheralManager, Error?) -> ())?
    public var didAddService: ((CBMPeripheralManager, CBMService, Error?) -> ())?
    public var didSubscribe: ((CBMPeripheralManager, CBMCentral, CBMCharacteristic) -> ())?
    public var didUnsubscribe: ((CBMPeripheralManager, CBMCentral, CBMCharacteristic) -> ())?
    public var didReceiveRead: ((CBMPeripheralManager, CBMATTRequest) -> ())?
    public var didReceiveWrite: ((CBMPeripheralManager, [CBMATTRequest]) -> ())?
    public var isReadyToUpdateSubscribers: ((CBMPeripheralManager) -> ())?
    public var didPublishL2CAPChannel: ((CBMPeripheralManager, CBML2CAPPSM, Error?) -> ())?
    public var didUnpublishL2CAPChannel: ((CBMPeripheralManager, CBML2CAPPSM, Error?) -> ())?
    public var didOpenChannel: ((CBMPeripheralManager, CBML2CAPChannel?, Error?) -> ())?

    open func peripheralManagerDidUpdateState(_ peripheral: CBMPeripheralManager) {
        didUpdateState?(peripheral)
    }

    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                willRestoreState dict: [String : Any]) {
        willRestoreState?(peripheral, dict)
    }

    open func peripheralManagerDidStartAdvertising(_ peripheral: CBMPeripheralManager,
                                                   error: Error?) {
        didStartAdvertising?(peripheral, error)
    }

    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                didAdd service: CBMService,
                                error: Error?) {
        didAddService?(peripheral, service, error)
    }

    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                central: CBMCentral,
                                didSubscribeTo characteristic: CBMCharacteristic) {
        didSubscribe?(peripheral, central, characteristic)
    }

    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                central: CBMCentral,
                                didUnsubscribeFrom characteristic: CBMCharacteristic) {
        didUnsubscribe?(peripheral, central, characteristic)
    }

    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                didReceiveRead request: CBMATTRequest) {
        didReceiveRead?(peripheral, request)
    }

    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                didReceiveWrite requests: [CBMATTRequest]) {
        didReceiveWrite?(peripheral, requests)
    }

    open func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBMPeripheralManager) {
        isReadyToUpdateSubscribers?(peripheral)
    }

    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                didPublishL2CAPChannel PSM: CBML2CAPPSM,
                                error: Error?) {
        didPublishL2CAPChannel?(peripheral, PSM, error)
    }

    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                didUnpublishL2CAPChannel PSM: CBML2CAPPSM,
                                error: Error?) {
        didUnpublishL2CAPChannel?(peripheral, PSM, error)
    }

    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open func peripheralManager(_ peripheral: CBMPeripheralManager,
                                didOpen channel: CBML2CAPChannel?,
                                error: Error?) {
        didOpenChannel?(peripheral, channel, error)
    }
}
