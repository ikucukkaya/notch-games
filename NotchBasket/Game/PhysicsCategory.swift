import Foundation

enum PhysicsCategory {
    static let none: UInt32 = 0
    static let ball: UInt32 = 1 << 0
    static let rim: UInt32 = 1 << 1
    static let backboard: UInt32 = 1 << 2
    static let boundary: UInt32 = 1 << 3
    static let upperScoreSensor: UInt32 = 1 << 4
    static let lowerScoreSensor: UInt32 = 1 << 5
}
