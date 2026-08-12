import AppKit
import Carbon

@MainActor
protocol AppleEventSenderPIDDescriptorReading {
    func senderPIDAttribute() -> AppleEventSenderPIDAttribute
}

enum AppleEventSenderPIDAttribute: Sendable {
    case missing
    case descriptorReadFailed
    case wrongType
    case signedInteger(Int64)
}

@MainActor
enum AppleEventSenderReader {
    /// Copies the sender PID while the Apple Event callback still owns its descriptor.
    static func copyCurrentSenderPID() -> Int32? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return nil
        }

        return copySenderPID(from: CurrentAppleEventDescriptor(event: event))
    }

    static func copySenderPID(from descriptor: some AppleEventSenderPIDDescriptorReading) -> Int32? {
        guard case let .signedInteger(value) = descriptor.senderPIDAttribute(),
              let senderPID = Int32(exactly: value),
              senderPID > 0
        else {
            return nil
        }

        return senderPID
    }
}

@MainActor
private struct CurrentAppleEventDescriptor: AppleEventSenderPIDDescriptorReading {
    let event: NSAppleEventDescriptor

    func senderPIDAttribute() -> AppleEventSenderPIDAttribute {
        guard let descriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else {
            return .missing
        }

        guard descriptor.descriptorType == DescType(typeSInt32) else {
            return .wrongType
        }

        return .signedInteger(Int64(descriptor.int32Value))
    }
}
