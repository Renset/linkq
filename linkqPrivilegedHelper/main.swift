//
//  main.swift
//  linkqPrivilegedHelper
//

import Foundation
import Security

final class PrivilegedHelper: NSObject, NSXPCListenerDelegate, LinkQPrivilegedHelperProtocol {
    private let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.label)

    override init() {
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.main.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isClientAllowed(connection) else {
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: LinkQPrivilegedHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func setWiFiTurboEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let result = linkq_set_wifi_turbo_watchdog_enabled(enabled ? 1 : 0, &errorBuffer, errorBuffer.count)
        guard result == 0 else {
            let message = String(cString: errorBuffer)
            reply(false, message.isEmpty ? "Could not change Wi-Fi turbo mode." : message)
            return
        }

        reply(true, nil)
    }

    private func isClientAllowed(_ connection: NSXPCConnection) -> Bool {
        let attributes = [
            kSecGuestAttributePid as String: connection.processIdentifier
        ] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            return false
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(PrivilegedHelperConstants.appSigningRequirement as CFString, [], &requirement) == errSecSuccess, let requirement else {
            return false
        }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}

PrivilegedHelper().run()
