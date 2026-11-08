// Integration regression: publish and update real Bonjour TXT records, without
// connecting to another device or sending a file. Link against the built library.
import Foundation
import CryptoKit
import Network
@testable import NearbyShare

func base64(_ data:Data) -> String {
	data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
		.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func require(_ condition:@autoclosure () -> Bool, _ message:String) {
	guard condition() else {
		fputs("FAIL: \(message)\n", stderr)
		exit(1)
	}
}

func waitFor(_ message:String, _ condition:() -> Bool) {
	let deadline=Date().addingTimeInterval(8)
	while !condition() && Date()<deadline {
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
	}
	require(condition(), message)
}

func endpointInfo(name:String?, qrData:Data?=nil) -> Data {
	var data=Data([name==nil ? 0x12 : 0x02])+Data(repeating: 0, count: 16)
	if let name {
		data.append(UInt8(name.utf8.count))
		data.append(Data(name.utf8))
	}
	if let qrData {
		data.append(contentsOf: [1, UInt8(qrData.count)])
		data.append(qrData)
	}
	return data
}

func qrKeys(_ key:String) -> (token:Data, encryptionKey:SymmetricKey) {
	var encoded=key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
	while encoded.count%4 != 0 {encoded += "="}
	let input=SymmetricKey(data: Data(base64Encoded: encoded)!)
	let token=HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: Data(),
		info: Data("advertisingContext".utf8), outputByteCount: 16)
	let encryptionKey=HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: Data(),
		info: Data("encryptionKey".utf8), outputByteCount: 16)
	return (token.withUnsafeBytes {Data($0)}, encryptionKey)
}

final class Observer:ShareExtensionDelegate {
	let endpointID:String
	var latest:RemoteDeviceInfo?
	var starts=0
	init(endpointID:String) {self.endpointID=endpointID}
	func addDevice(device:RemoteDeviceInfo) {if device.id==endpointID {latest=device}}
	func removeDevice(id:String) {if id==endpointID {latest=nil}}
	func startTransferWithQrCode(device:RemoteDeviceInfo) {if device.id==endpointID {starts += 1}}
	func connectionWasEstablished(pinCode:String) {}
	func connectionFailed(with error:Error) {}
	func transferAccepted() {}
	func transferProgress(progress:Double) {}
	func transferFinished() {}
}

// Permit only our own local fixture; production ignores loopback announcements.
let endpointID=String(UUID().uuidString.prefix(4))
let serviceName=base64(Data([0x23])+Data(endpointID.utf8)+Data([0xFC, 0x9F, 0x5E, 0, 0]))
let manager=NearbyConnectionManager(serviceFilter: {result in
	if case let .service(name, _, _, _)=result.endpoint {return name==serviceName}
	return false
})
let observer=Observer(endpointID: endpointID)
let service=NetService(domain: "local.", type: "_FC9F5ED42C8A._tcp.", name: serviceName, port: 33333)
func advertise(name:String?, qrData:Data?=nil) {
	require(service.setTXTRecord(NetService.data(fromTXTRecord: ["n": Data(base64(endpointInfo(name: name, qrData: qrData)).utf8)])), "publish TXT record")
}

// Observe the event type independently: a remove/add cycle would not reproduce
// the ignored .changed callback that caused this regression.
var metadataChanges=0
let browser=NWBrowser(for: .bonjourWithTXTRecord(type: "_FC9F5ED42C8A._tcp.", domain: nil), using: .tcp)
browser.browseResultsChangedHandler={_, changes in
	for change in changes {
		if case let .changed(_, result, flags)=change,
		   case let .service(name, _, _, _)=result.endpoint,
		   name==serviceName, flags.contains(.metadataChanged) {metadataChanges += 1}
	}
}
browser.start(queue: .main)
manager.addShareExtensionDelegate(observer)
manager.startDeviceDiscovery()
let firstKeys=qrKeys(manager.generateQrCodeKey())
advertise(name: "Discovery regression before scan")
service.publish()
waitFor("discover named device before QR scan") {observer.latest?.name=="Discovery regression before scan"}
require(observer.starts==0, "no transfer before matching QR data")

advertise(name: "Discovery regression after scan", qrData: firstKeys.token)
waitFor("TXT update must start QR transfer and refresh device name") {
	observer.starts==1 && observer.latest?.name=="Discovery regression after scan"
}
advertise(name: "Discovery regression repeated update", qrData: firstKeys.token)
waitFor("refresh same endpoint on repeated TXT update") {observer.latest?.name=="Discovery regression repeated update"}
require(observer.starts==1, "same QR session must start only once")

let secondKeys=qrKeys(manager.generateQrCodeKey())
advertise(name: "Discovery regression second QR", qrData: secondKeys.token)
waitFor("fresh QR session can start on the same endpoint") {observer.starts==2}

advertise(name: nil, qrData: Data(repeating: 0x42, count: 16))
waitFor("remove stale named device when it becomes private") {observer.latest==nil}
let privateKeys=qrKeys(manager.generateQrCodeKey())
let encrypted=try AES.GCM.seal(Data("Discovery regression private".utf8), using: privateKeys.encryptionKey,
	authenticating: privateKeys.token).combined!
advertise(name: nil, qrData: encrypted)
waitFor("decrypt private device name and start QR transfer after TXT update") {
	observer.starts==3 && observer.latest?.name=="Discovery regression private"
}
require(metadataChanges>=4, "regression must exercise actual Bonjour metadata changes")

service.stop()
waitFor("remove stopped service") {observer.latest==nil}
manager.stopDeviceDiscovery()
manager.removeShareExtensionDelegate(observer)
manager.clearQrCodeKey()
browser.cancel()
print("PASS: Bonjour updates, refreshed names, one start per QR session, fresh QR sessions, private names, removal")
