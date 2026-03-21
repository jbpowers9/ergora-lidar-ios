//
//  ScanData.swift
//  ErgoraLiDAR
//

import Foundation

struct RoomData: Codable, Hashable {
    let name: String
    let floor: Int
    let area: Double
    let dimensions: RoomDimensions
    let windows: [Opening]
    let doors: [Opening]
    let ceilingHeight: Double
}

struct RoomDimensions: Codable, Hashable {
    let width: Double
    let length: Double
}

struct Opening: Codable, Hashable {
    let width: Double
    let height: Double
}

struct SketchPayload: Codable, Hashable {
    let rooms: [RoomData]
    let totalGLA: Double
    let totalWindowArea: Double
    let storiesCount: Int
    let scanId: String
}
