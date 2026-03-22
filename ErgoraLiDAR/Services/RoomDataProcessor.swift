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
    /// - Parameter selectedFloor: 0 = basement, 1–3 = floors, **-1** = garage, **-2** = other area (porches, sheds, etc.).
    static func sketchPayload(from room: CapturedRoom, selectedFloor: Int) -> SketchPayload {
        let scanId = UUID().uuidString

        let floorSurfaces = room.floors.filter { surface in
            if case .floor = surface.category { return true }
            return false
        }

        let totalFloorAreaM2 = totalFloorAreaM2(from: room, floorSurfaces: floorSurfaces)

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
        let (isGarageFloor, isOtherAreaFloor) = roomFlags(for: selectedFloor)

        let rooms: [RoomData]
        if sections.isEmpty {
            let areaFt2 = totalFloorAreaM2 * sqMetersToSqFeet
            let dims =
                dimensionsFromLargestFloorSurface(floorSurfaces)
                ?? dimensionsFromAreaM2(totalFloorAreaM2)
            let baseName = detectRoomType(from: room, index: 0, areaSqFt: areaFt2)
            rooms = [
                RoomData(
                    name: prefixedRoomName(base: baseName, selectedFloor: selectedFloor),
                    floor: selectedFloor,
                    area: areaFt2,
                    dimensions: dims,
                    windows: windowOpenings,
                    doors: doorOpenings,
                    ceilingHeight: ceilingHeightFt,
                    isGarage: isGarageFloor,
                    isOtherArea: isOtherAreaFloor
                )
            ]
        } else {
            let centers = sections.map(\.center)
            let windowAssignments = assign(openings: room.windows, toSections: centers)
            let doorAssignments = assign(openings: room.doors, toSections: centers)

            let sectionAreasM2 = sectionFloorAreasM2Normalized(
                room: room,
                sections: sections,
                totalFloorAreaM2: totalFloorAreaM2
            )
            let largestSection = sections.enumerated().max(by: { sectionAreasM2[$0.offset] < sectionAreasM2[$1.offset] })?.element
            let dimsFromLargestSection = largestSection.flatMap { dimensionsFromMirroredSection($0) }

            rooms = sections.enumerated().map { index, section in
                let areaM2 = index < sectionAreasM2.count ? sectionAreasM2[index] : totalFloorAreaM2 / Double(sections.count)
                let areaFt2 = areaM2 * sqMetersToSqFeet
                let windowsForRoom = windowAssignments[index].map { opening(from: $0) }
                let doorsForRoom = doorAssignments[index].map { opening(from: $0) }

                let dims =
                    dimensionsFromMirroredSection(section)
                    ?? dimsFromLargestSection
                    ?? dimensionsFromNearestFloorSurface(to: section.center, floors: floorSurfaces)
                    ?? dimensionsFromAreaM2(areaM2)

                let baseName = detectRoomType(from: room, index: index, areaSqFt: areaFt2)
                return RoomData(
                    name: prefixedRoomName(base: baseName, selectedFloor: selectedFloor),
                    floor: selectedFloor,
                    area: areaFt2,
                    dimensions: dims,
                    windows: windowsForRoom,
                    doors: doorsForRoom,
                    ceilingHeight: ceilingHeightFt,
                    isGarage: isGarageFloor,
                    isOtherArea: isOtherAreaFloor
                )
            }
        }

        let totalGLA = rooms.filter { !$0.isGarage && !$0.isOtherArea }.reduce(0) { $0 + $1.area }
        let garageAreaSqFt = rooms.filter(\.isGarage).reduce(0) { $0 + $1.area }
        let otherAreaSqFt = rooms.filter(\.isOtherArea).reduce(0) { $0 + $1.area }
        let floorLevels = Set(rooms.map(\.floor))

        return SketchPayload(
            rooms: rooms,
            totalGLA: totalGLA,
            garageAreaSqFt: garageAreaSqFt,
            otherAreaSqFt: otherAreaSqFt,
            totalWindowArea: totalWindowAreaSqFt,
            storiesCount: max(1, floorLevels.count),
            scanId: scanId
        )
    }

    private static func roomFlags(for selectedFloor: Int) -> (isGarage: Bool, isOtherArea: Bool) {
        (selectedFloor == -1, selectedFloor == -2)
    }

    private static func prefixedRoomName(base: String, selectedFloor: Int) -> String {
        switch selectedFloor {
        case -1: return "Garage \(base)"
        case -2: return "Other \(base)"
        default: return base
        }
    }

    // MARK: - Total floor area (priority order)

    /// PRIMARY: `CapturedRoom.sections` — sum `area` when exposed (public API or runtime fields via Mirror).
    /// FALLBACK 1: sum floor-surface areas (polygon / bounding face).
    /// FALLBACK 2: `wallFootprintAreaFromWallCentersM2`.
    /// FALLBACK 3: `wallBoundingFootprintAreaM2`.
    private static func totalFloorAreaM2(from room: CapturedRoom, floorSurfaces: [CapturedRoom.Surface]) -> Double {
        if !room.sections.isEmpty {
            let areas = room.sections.map { mirroredSectionAreaM2($0) }
            if !areas.contains(where: { $0 == nil }) {
                let sum = areas.compactMap { $0 }.reduce(0, +)
                if sum > 0 { return sum }
            }
        }

        if !floorSurfaces.isEmpty {
            let sum = floorSurfaces.reduce(0) { $0 + floorSurfaceAreaM2($1) }
            if sum > 0 { return sum }
        }

        let fromCenters = wallFootprintAreaFromWallCentersM2(walls: room.walls)
        if fromCenters > 0 { return fromCenters }

        return wallBoundingFootprintAreaM2(walls: room.walls)
    }

    /// Per-section floor areas (m²) summing to `totalFloorAreaM2`: full mirror set when available; else wall centers per section + remainder + normalization.
    private static func sectionFloorAreasM2Normalized(
        room: CapturedRoom,
        sections: [CapturedRoom.Section],
        totalFloorAreaM2: Double
    ) -> [Double] {
        let n = sections.count
        guard n > 0 else { return [] }
        guard totalFloorAreaM2 > 0 else { return Array(repeating: 0, count: n) }

        let mirrorCandidates: [Double?] = sections.map { section in
            if let a = mirroredSectionAreaM2(section), a > 0 { return a }
            if let a = areaM2FromMirroredXZDimensions(section), a > 0 { return a }
            return nil
        }
        if mirrorCandidates.allSatisfy({ $0 != nil }) {
            let mirVals = mirrorCandidates.compactMap { $0 }
            let sumMir = mirVals.reduce(0, +)
            if sumMir > 0 {
                return mirVals.map { totalFloorAreaM2 * $0 / sumMir }
            }
        }

        let centers = sections.map(\.center)
        let wallSurfaces = room.walls.filter { surface in
            if case .wall = surface.category { return true }
            return false
        }
        let wallBuckets = assign(openings: wallSurfaces, toSections: centers)
        let raw = wallBuckets.map { wallBoundingBoxPerSectionM2(walls: $0) }

        let sumRaw = raw.filter { $0 > 0 }.reduce(0, +)
        let unwalledIndices = raw.enumerated().filter { $0.element <= 0 }.map(\.offset)
        let walledIndices = raw.enumerated().filter { $0.element > 0 }.map(\.offset)

        var areas = Array(repeating: 0.0, count: n)

        if sumRaw <= 0 {
            let each = totalFloorAreaM2 / Double(n)
            areas = Array(repeating: each, count: n)
        } else if unwalledIndices.isEmpty {
            for i in 0..<n {
                areas[i] = totalFloorAreaM2 * raw[i] / sumRaw
            }
        } else {
            let rem = totalFloorAreaM2 - sumRaw
            if rem >= 0 {
                for i in walledIndices { areas[i] = raw[i] }
                let share = rem / Double(unwalledIndices.count)
                for i in unwalledIndices { areas[i] = share }
            } else {
                for i in walledIndices {
                    areas[i] = totalFloorAreaM2 * raw[i] / sumRaw
                }
            }
        }

        let sumA = areas.reduce(0, +)
        if sumA > 0 {
            areas = areas.map { $0 * totalFloorAreaM2 / sumA }
        }
        return areas
    }

    /// Min/max XZ footprint (m²) from wall centers for walls assigned to one section (same logic as `wallFootprintAreaFromWallCentersM2`).
    private static func wallBoundingBoxPerSectionM2(walls: [CapturedRoom.Surface]) -> Double {
        wallFootprintAreaFromWallCentersM2(walls: walls)
    }

    /// Reads stored area from `Section` if present (public API or runtime fields via Mirror).
    private static func mirroredSectionAreaM2(_ section: CapturedRoom.Section) -> Double? {
        let areaLabels = ["area", "storedArea", "_area"]
        for child in Mirror(reflecting: section).children {
            guard let label = child.label, areaLabels.contains(label) else { continue }
            if let d = child.value as? Double { return d }
            if let f = child.value as? Float { return Double(f) }
        }
        return nil
    }

    /// Floor footprint from mirrored `dimensions` x and z (m²).
    private static func areaM2FromMirroredXZDimensions(_ section: CapturedRoom.Section) -> Double? {
        for child in Mirror(reflecting: section).children {
            guard let label = child.label, label == "dimensions" else { continue }
            if let sim = child.value as? simd_float3 {
                let x = Double(sim.x)
                let z = Double(sim.z)
                let a = abs(x * z)
                return a > 0 ? a : nil
            }
        }
        return nil
    }

    /// Reads `dimensions` as `simd_float3` from `Section` if present; width/length use X and Z in meters.
    private static func dimensionsFromMirroredSection(_ section: CapturedRoom.Section) -> RoomDimensions? {
        for child in Mirror(reflecting: section).children {
            guard let label = child.label, label == "dimensions" else { continue }
            if let sim = child.value as? simd_float3 {
                let a = Double(sim.x)
                let b = Double(sim.z)
                let wM = max(a, b)
                let lM = min(a, b)
                return RoomDimensions(width: wM * metersToFeet, length: lM * metersToFeet)
            }
        }
        return nil
    }

    private static func dimensionsFromLargestFloorSurface(_ floors: [CapturedRoom.Surface]) -> RoomDimensions? {
        guard !floors.isEmpty else { return nil }
        let best = floors.max(by: { floorSurfaceAreaM2($0) < floorSurfaceAreaM2($1) })!
        let d = best.dimensions
        let a = Double(d.x)
        let b = Double(d.z)
        let wM = max(a, b)
        let lM = min(a, b)
        return RoomDimensions(width: wM * metersToFeet, length: lM * metersToFeet)
    }

    private static func dimensionsFromNearestFloorSurface(to center: simd_float3, floors: [CapturedRoom.Surface]) -> RoomDimensions? {
        guard !floors.isEmpty else { return nil }
        let cx = Double(center.x)
        let cz = Double(center.z)
        var best: CapturedRoom.Surface?
        var bestDist = Double.greatestFiniteMagnitude
        for f in floors {
            let t = f.transform.columns.3
            let dx = Double(t.x) - cx
            let dz = Double(t.z) - cz
            let dist = dx * dx + dz * dz
            if dist < bestDist {
                bestDist = dist
                best = f
            }
        }
        guard let surface = best else { return nil }
        let d = surface.dimensions
        let a = Double(d.x)
        let b = Double(d.z)
        let wM = max(a, b)
        let lM = min(a, b)
        return RoomDimensions(width: wM * metersToFeet, length: lM * metersToFeet)
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

    // MARK: - Room type from objects

    /// Uses `CapturedRoom.Object.Category` cases from the RoomPlan SDK (see `RoomPlan.swiftinterface`).
    /// Note: There is no `.shower` or `.diningTable`; bath uses `.bathtub`, dining uses `.table`.
    private static func detectRoomType(
        from room: CapturedRoom,
        index: Int,
        areaSqFt: Double
    ) -> String {
        let cats = room.objects.map(\.category)
        let hasToilet = cats.contains(.toilet)
        let hasBath = cats.contains(.bathtub)
        let hasBed = cats.contains(.bed)
        let hasKitchen = cats.contains(.refrigerator)
            || cats.contains(.stove)
            || cats.contains(.oven)
        let hasSofa = cats.contains(.sofa)
        let hasWasher = cats.contains(.washerDryer)
        let hasDining = cats.contains(.table)

        // Bathroom requires toilet AND small area
        // Large rooms with toilets are misdetections
        if hasToilet && hasBath && areaSqFt < 150 {
            return "Full Bath"
        }
        if hasToilet && areaSqFt < 80 {
            return "Half Bath"
        }
        if hasBed { return "Bedroom" }
        if hasKitchen { return "Kitchen" }
        if hasWasher { return "Laundry Room" }
        if hasSofa { return "Living Room" }
        if hasDining && areaSqFt < 300 { return "Dining Room" }
        return "Room \(index + 1)"
    }
}
