import CoreBluetooth
import Foundation

public enum BLEConstants {
    public static var serviceUUID: CBUUID { CBUUID(string: "7A4E0001-9B2C-4F6A-A8D1-3E5F7C9B0001") }
    public static var authCharacteristicUUID: CBUUID { CBUUID(string: "7A4E0002-9B2C-4F6A-A8D1-3E5F7C9B0002") }
    public static let centralRestoreIdentifier = "io.github.inazumimakoto.OurHours.central"
    public static let peripheralRestoreIdentifier = "io.github.inazumimakoto.OurHours.peripheral"
    public static let authTimeoutSeconds: TimeInterval = 6
    public static let failedPeerCooldownSeconds: TimeInterval = 300
    public static let knownPeerConnectionFailureCooldownSeconds: TimeInterval = 15
    public static let knownPeerAuthFailureCooldownSeconds: TimeInterval = 15
    public static let invalidHandleRediscoveryDelaySeconds: TimeInterval = 0.6
}
