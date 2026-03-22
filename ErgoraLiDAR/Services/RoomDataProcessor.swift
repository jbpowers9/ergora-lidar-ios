//
//  RoomDataProcessor.swift
//  ErgoraLiDAR
//

import Foundation
import RoomPlan
import simd

enum RoomDataProcessor {
    private static let metersToFeet = 3.28084
    /// Square meters → square feet (exact conversion factor).
    private static let sqMetersToSqFeet = 10.7639

    /// Converts RoomPlan `CapturedRoom` into a `SketchPayload` for Ergora.
    /// - Parameter selectedFloor: User-selected floor for this scan (0 = basement, 1–3 = above-grade floors).
    static func sketchPayload(from room: CapturedRoom, selectedFloor: Int) -> SketchPayload {
        let scanId = UUID().uuidString

        let floorSurfaces = room.floors.filter { surface in
            if case .floor = surface.category { return true }
            return false
        }

        let totalFloorAreaM2: Double = {
            if floorSurfaces.isEmpty {
                let fromCenters = wallFootprintAreaFromWallCentersM2(walls: room.walls)
                if fromCenters > 0 {
                    return fromCenters
                }
                return wallBoundingFootprintAreaM2(walls: room.walls)
            }
            return floorSurfaces.reduce(0) { partial, surface in
                partial + floorSurfaceAreaM2(surface)
            }
        }()

        let wallHeightsM = room.walls.compactMap { surface -> Double? in
            guard case .wall = surface.category else { return nil }
            return Double(surface.dimensions.y)
        }
        let avgWallHeightM = wallHeightsM.isEmpty
            ? 2.5
            : wallHeightsM.reduce(0, +) / Double(wallHeightsM.count)
        let ceilingHeightFt = avgWallHeightM * metersToFeet

        let windowOpenings = room.windows.map { opening(from: $0) }
        let doorOpenings = room.doors.map { opening(from: $0) }

        let totalWindowAreaSqFt = windowOpenings.reduce(0) { $0 + $1.width * $1.height }

        let sections = room.sections

        let rooms: [RoomData]
        if sections.isEmpty {
            let areaFt2 = totalFloorAreaM2 * sqMetersToSqFeet
            let dims = dimensionsFromAreaM2(totalFloorAreaM2)
            rooms = [
                RoomData(
                    name: "Room 1",
                    floor: selectedFloor,
                    area: areaFt2,
                    dimensions: dims,
                    windows: windowOpenings,
                    doors: doorOpenings,
                    ceilingHeight: ceilingHeightFt
                )
            ]
        } else {
            let count = sections.count
            let areaPerRoomM2 = totalFloorAreaM2 / Double(count)
            let areaPerRoomFt2 = areaPerRoomM2 * sqMetersToSqFeet
            let dims = dimensionsFromAreaM2(areaPerRoomM2)

            let centers = sections.map(\.center)
            let windowAssignments = assign(openings: room.windows, toSections: centers)
            let doorAssignments = assign(openings: room.doors, toSections: centers)

            rooms = sections.enumerated().map { index, _ in
                let windowsForRoom = windowAssignments[index].map { opening(from: $0) }
                let doorsForRoom = doorAssignments[index].map { opening(from: $0) }
                return RoomData(
                    name: "Room \(index + 1)",
                    floor: selectedFloor,
                    area: areaPerRoomFt2,
                    dimensions: dims,
                    windows: windowsForRoom,
                    doors: doorsForRoom,
                    ceilingHeight: ceilingHeightFt
                )
            }
        }

        let totalGLA = rooms.reduce(0) { $0 + $1.area }
        let floorLevels = Set(rooms.map(\.floor))

        return SketchPayload(
            rooms: rooms,
            totalGLA: totalGLA,
            totalWindowArea: totalWindowAreaSqFt,
            storiesCount: max(1, floorLevels.count),
            scanId: scanId
        )
    }

    private static func opening(from surface: CapturedRoom.Surface) -> Opening {
        let w = Double(surface.dimensions.x) * metersToFeet
        let h = Double(surface.dimensions.y) * metersToFeet
        return Opening(width: w, height: h)
    }

    private static func floorSurfaceAreaM2(_ surface: CapturedRoom.Surface) -> Double {
        let corners = surface.polygonCorners
        if corners.count >= 3 {
            return polygonAreaM2(corners: corners)
        }
        let d = surface.dimensions
        let a = Double(d.x * d.y)
        let b = Double(d.x * d.z)
        let c = Double(d.y * d.z)
        return max(a, b, c)
    }

    private static func polygonAreaM2(corners: [simd_float3]) -> Double {
        guard corners.count >= 3 else { return 0 }
        var sum = Double.zero
        let n = corners.count
        for i in 0..<n {
            let j = (i + 1) % n
            let xi = Double(corners[i].x)
            let zi = Double(corners[i].z)
            let xj = Double(corners[j].x)
            let zj = Double(corners[j].z)
            sum += xi * zj - xj * zi
        }
        return abs(sum) * 0.5
    }

    private static func wallBoundingFootprintAreaM2(walls: [CapturedRoom.Surface]) -> Double {
        guard !walls.isEmpty else { return 0 }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude
        for wall in walls {
            let t = wall.transform
            let p = SIMD3<Double>(Double(t.columns.3.x), Double(t.columns.3.y), Double(t.columns.3.z))
            let halfX = Double(wall.dimensions.x) * 0.5
            let halfZ = Double(wall.dimensions.z) * 0.5
            minX = min(minX, p.x - halfX)
            maxX = max(maxX, p.x + halfX)
            minZ = min(minZ, p.z - halfZ)
            maxZ = max(maxZ, p.z + halfZ)
        }
        let w = max(0, maxX - minX)
        let d = max(0, maxZ - minZ)
        return w * d
    }

    private static func dimensionsFromAreaM2(_ areaM2: Double) -> RoomDimensions {
        guard areaM2 > 0 else {
            return RoomDimensions(width: 0, length: 0)
        }
        let areaFt2 = areaM2 * sqMetersToSqFeet
        let sideFt = sqrt(areaFt2)
        return RoomDimensions(width: sideFt, length: sideFt)
    }

    /// Fallback footprint when no floor surfaces: axis-aligned box from wall **center** positions (XZ only).
    private static func wallFootprintAreaFromWallCentersM2(walls: [CapturedRoom.Surface]) -> Double {
        let centers: [simd_float3] = walls.compactMap { wall in
            guard case .wall = wall.category else { return nil }
            let t = wall.transform.columns.3
            return simd_float3(t.x, t.y, t.z)
        }
        guard !centers.isEmpty else { return 0 }
        let xs = centers.map { Double($0.x) }
        let zs = centers.map { Double($0.z) }
        guard let minX = xs.min(), let maxX = xs.max(), let minZ = zs.min(), let maxZ = zs.max() else {
            return 0
        }
        let w = max(0, maxX - minX)
        let d = max(0, maxZ - minZ)
        return w * d
    }

    /// Assigns each opening surface to the section index whose center is closest in the XZ plane.
    private static func assign(
        openings: [CapturedRoom.Surface],
        toSections centers: [simd_float3]
    ) -> [[CapturedRoom.Surface]] {
        guard !centers.isEmpty else { return [] }
        var buckets = Array(repeating: [CapturedRoom.Surface](), count: centers.count)
        for opening in openings {
            let o = opening.transform.columns.3
            let ox = Double(o.x)
            let oz = Double(o.z)
            var best = 0
            var bestDist = Double.greatestFiniteMagnitude
            for (idx, c) in centers.enumerated() {
                let dx = ox - Double(c.x)
                let dz = oz - Double(c.z)
                let dist = dx * dx + dz * dz
                if dist < bestDist {
                    bestDist = dist
                    best = idx
                }
            }
            buckets[best].append(opening)
        }
        return buckets
    }
}
