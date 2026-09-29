import AppKit
import Carbon

@MainActor
protocol AppleEventSenderPIDDescriptorReading {
    func senderPIDAttribute() -> AppleEventSenderPIDAttribute
}

enum AppleEventSenderPIDAttribute: Equatable, Sendable {
    case missing
    case descriptorReadFailed
    case wrongType
    case signedInteger(Int64)
}

@MainActor
enum AppleEventSenderReader {
    /// Copies the sender PID while the Apple Event callback still owns its descriptor.
    static func copyCurrentSenderPID() -> Int32? {
        copySenderPID(
            nsEvent: NSAppleEventManager.shared().currentAppleEvent,
            carbonPID: CarbonAppleEventSender.currentSenderPID()
        )
    }

    static func copySenderPID(nsEvent: NSAppleEventDescriptor?, carbonPID: Int32?) -> Int32? {
        if let nsEvent, let pid = copySenderPID(from: nsEvent) {
            return pid
        }
        guard let carbonPID, carbonPID > 0 else { return nil }
        return carbonPID
    }

    static func copySenderPID(from event: NSAppleEventDescriptor) -> Int32? {
        if let attribute = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)),
           let pid = pid(from: attribute) {
            return pid
        }
        return copySenderPID(from: CurrentAppleEventDescriptor(event: event))
    }

    /// Real `GURL` events report `keySenderPIDAttr` as `typeUInt32`. Coercion matches that value;
    /// reading the raw bytes first can invent a PID that hides the real process.
    static func pid(from attribute: NSAppleEventDescriptor) -> Int32? {
        if let coerced = attribute.coerce(toDescriptorType: DescType(typeSInt32)),
           coerced.int32Value > 0 {
            return coerced.int32Value
        }
        guard case let .signedInteger(value) = AppleEventSenderPIDDecoder.attribute(
            descriptorType: attribute.descriptorType,
            int32Value: attribute.int32Value,
            data: attribute.data
        ), let pid = Int32(exactly: value), pid > 0 else {
            return nil
        }
        return pid
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

        return AppleEventSenderPIDDecoder.attribute(
            descriptorType: descriptor.descriptorType,
            int32Value: descriptor.int32Value,
            data: descriptor.data
        )
    }
}

enum AppleEventSenderPIDDecoder {
    static func attribute(
        descriptorType: DescType,
        int32Value: Int32,
        data: Data? = nil
    ) -> AppleEventSenderPIDAttribute {
        if descriptorType == DescType(typeUInt32),
           let data,
           data.count == MemoryLayout<UInt32>.size {
            let value = data.withUnsafeBytes { raw in
                raw.load(as: UInt32.self)
            }
            guard value > 0, value <= UInt32(Int32.max) else { return .wrongType }
            return .signedInteger(Int64(value))
        }
        if descriptorType == DescType(typeKernelProcessID),
           let data,
           data.count == MemoryLayout<UInt32>.size {
            let value = data.withUnsafeBytes { raw in
                UInt32(bigEndian: raw.load(as: UInt32.self))
            }
            guard value > 0, value <= UInt32(Int32.max) else { return .wrongType }
            return .signedInteger(Int64(value))
        }
        let isProcessID = descriptorType == DescType(typeSInt32)
            || descriptorType == DescType(typeKernelProcessID)
            || descriptorType == DescType(typeUInt32)
        guard isProcessID else { return .wrongType }
        return .signedInteger(Int64(int32Value))
    }
}

enum CarbonAppleEventSender {
    static func currentSenderPID() -> Int32? {
        var event = AppleEvent(descriptorType: typeNull, dataHandle: nil)
        guard AEGetTheCurrentEvent(&event) == noErr else { return nil }
        defer { AEDisposeDesc(&event) }

        var pid: Int32 = 0
        var actualType: DescType = 0
        var actualSize = 0
        let status = AEGetAttributePtr(
            &event,
            AEKeyword(keySenderPIDAttr),
            DescType(typeSInt32),
            &actualType,
            &pid,
            MemoryLayout<Int32>.size,
            &actualSize
        )
        guard status == noErr, pid > 0 else { return nil }
        return pid
    }
}

enum GetURLEvent {
    static func urls(in event: NSAppleEventDescriptor) -> [URL] {
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else { return [] }
        if direct.numberOfItems > 0 {
            return (1...direct.numberOfItems).compactMap { index in
                url(from: direct.atIndex(index))
            }
        }
        return [url(from: direct)].compactMap { $0 }
    }

    private static func url(from descriptor: NSAppleEventDescriptor?) -> URL? {
        if descriptor?.descriptorType == DescType(typeFileURL), let fileURL = descriptor?.fileURLValue {
            return fileURL
        }
        guard let string = descriptor?.stringValue, let url = URL(string: string) else { return nil }
        return url
    }
}
