//
//  PrivilegedHelperProtocol.swift
//  linkq
//

import Foundation

enum PrivilegedHelperConstants {
    static let label = "com.notfullin.linkqPrivilegedHelper"
    static let appSigningRequirement = #"identifier "com.notfullin.linkq" and anchor apple generic and certificate leaf[subject.OU] = "ZRB8WDV435""#
}

@objc(LinkQPrivilegedHelperProtocol)
protocol LinkQPrivilegedHelperProtocol {
    func setWiFiTurboEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
}
