//
//  A1Event.swift
//  A1AppSDK
//

import Foundation

/// An analytics event, fanned out to every registered sink.
///
/// The event vocabulary stays in the host app — each app has its own large event enum —
/// and is passed here as a raw name. The SDK's job is dispatch, not naming.
public struct A1Event: ExpressibleByStringLiteral {
    public let name: String
    public let parameters: [String: Any]?

    public init(_ name: String, parameters: [String: Any]? = nil) {
        self.name = name
        self.parameters = parameters
    }

    public init(stringLiteral value: String) {
        self.name = value
        self.parameters = nil
    }

    /// Convenience for the parallel keys/values call style used across the apps today.
    public init(_ name: String, keys: [String], values: [String]) {
        self.name = name
        var params: [String: String] = [:]
        for (index, key) in keys.enumerated() where index < values.count {
            params[key] = values[index]
        }
        self.parameters = params.isEmpty ? nil : params
    }
}
