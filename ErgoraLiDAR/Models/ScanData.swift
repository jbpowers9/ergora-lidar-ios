//
//  ScanData.swift
//  ErgoraLiDAR
//

import Foundation

struct RoomData: Codable, Hashable {
    var name: String
    let floor: Int
    let area: Double
    let dimensions: RoomDimensions
    let windows: [Opening]
    let doors: [Opening]
    let ceilingHeight: Double
    /// Set when scanning with floor "Garage" (-1); excluded from `SketchPayload.totalGLA`.
    var isGarage: Bool
    /// Set when scanning with floor "Other Area" (-2); excluded from `SketchPayload.totalGLA`.
    var isOtherArea: Bool
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
    var rooms: [RoomData]
    /// Gross leasable area (sq ft), excluding garage and other-area scans.
    let totalGLA: Double
    /// Sum of room areas marked as garage (`isGarage`).
    let garageAreaSqFt: Double
    /// Sum of room areas marked as other area (`isOtherArea`).
    let otherAreaSqFt: Double
    let totalWindowArea: Double
    let storiesCount: Int
    let scanId: String
}

struct FloorScan: Identifiable, Hashable {
    let id: UUID
    let floorName: String
    let floorNumber: Int
    let rooms: [RoomData]
    let totalArea: Double
    let scanId: String

    init(floorName: String, floorNumber: Int, rooms: [RoomData], totalArea: Double, scanId: String) {
        self.id = UUID()
        self.floorName = floorName
        self.floorNumber = floorNumber
        self.rooms = rooms
        self.totalArea = totalArea
        self.scanId = scanId
    }

    static func displayName(for floorNumber: Int) -> String {
        switch floorNumber {
        case 0: return "Basement"
        case 2: return "Second Floor"
        case 3: return "Third Floor"
        case -1: return "Garage"
        case -2: return "Other Area"
        default: return "First Floor"
        }
    }
}
