//
//  ScanResultView.swift
//  ErgoraLiDAR
//

import SwiftUI

struct ScanResultView: View {
    @EnvironmentObject private var flow: ScanFlowModel
    @Binding var path: NavigationPath

    @State private var editingRoomIndex: Int?
    @State private var draftRoomName: String = ""

    private static let quickLabels = [
        "Living Room", "Kitchen", "Primary Bedroom", "Bedroom", "Bathroom",
        "Half Bath", "Dining Room", "Office", "Garage", "Basement", "Other",
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let payload = flow.sketchPayload {
                        Text("Scan Results")
                            .font(.largeTitle.weight(.semibold))

                        Text("Rooms")
                            .font(.headline)
                        ForEach(Array(payload.rooms.enumerated()), id: \.offset) { index, room in
                            roomRow(index: index, room: room)
                        }

                        summaryRow(title: "Total GLA", value: glaLabel(total: payload.totalGLA))
                        if payload.garageAreaSqFt > 0 {
                            summaryRow(title: "Garage area", value: glaLabel(total: payload.garageAreaSqFt))
                        }
                        if payload.otherAreaSqFt > 0 {
                            summaryRow(title: "Other area", value: glaLabel(total: payload.otherAreaSqFt))
                        }
                        summaryRow(title: "Total window area", value: String(format: "%.0f sq ft", payload.totalWindowArea))
                        summaryRow(title: "Stories", value: "\(payload.storiesCount)")

                        HStack(spacing: 16) {
                            Button {
                                saveFloorAndContinue()
                            } label: {
                                Text("Save Floor & Continue")
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color.ergoraTeal)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(flow.sketchPayload == nil)

                            Button {
                                rescan()
                            } label: {
                                Text("Rescan")
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color(.secondarySystemBackground))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("No scan data.")
                            .font(.body)
                    }
                }
                .padding(24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .tint(Color.ergoraTeal)
    }

    private func saveFloorAndContinue() {
        guard let payload = flow.sketchPayload else { return }
        let totalArea = payload.rooms.reduce(0) { $0 + $1.area }
        let updated = FloorScan(
            floorName: FloorScan.displayName(for: flow.selectedScanFloor),
            floorNumber: flow.selectedScanFloor,
            rooms: payload.rooms,
            totalArea: totalArea,
            scanId: payload.scanId
        )
        if let idx = flow.floorScans.firstIndex(where: { $0.scanId == updated.scanId }) {
            flow.floorScans[idx] = updated
        } else {
            flow.floorScans.append(updated)
        }
        path.append(AppRoute.floorScanList)
    }

    @ViewBuilder
    private func roomRow(index: Int, room: RoomData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if editingRoomIndex == index {
                TextField("Room name", text: $draftRoomName)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        applyRoomName(at: index)
                    }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(Self.quickLabels, id: \.self) { label in
                        Button {
                            draftRoomName = label
                            applyRoomName(at: index)
                        } label: {
                            Text(label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color(.tertiarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Button("Cancel") {
                        editingRoomIndex = nil
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        applyRoomName(at: index)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.ergoraTeal)
                }
            } else {
                Button {
                    editingRoomIndex = index
                    draftRoomName = room.name
                } label: {
                    Text(room.name)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            Text(roomAreaLabel(area: room.area))
                .font(.body)
            Text(
                String(
                    format: "≈ %.1f × %.1f ft",
                    room.dimensions.width,
                    room.dimensions.length
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func applyRoomName(at index: Int) {
        let trimmed = draftRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var payload = flow.sketchPayload, index < payload.rooms.count else {
            editingRoomIndex = nil
            return
        }
        payload.rooms[index].name = trimmed
        flow.sketchPayload = payload
        editingRoomIndex = nil
    }

    private func roomAreaLabel(area: Double) -> String {
        if area <= 0 {
            return "— sq ft"
        }
        return String(format: "%.0f sq ft", area)
    }

    private func glaLabel(total: Double) -> String {
        if total <= 0 {
            return "— sq ft"
        }
        return String(format: "%.0f sq ft", total)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.body)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rescan() {
        if let id = flow.sketchPayload?.scanId {
            flow.floorScans.removeAll { $0.scanId == id }
        }
        flow.scanSessionID = UUID()
        flow.sketchPayload = nil
        flow.lastCapturedRoom = nil
        path = NavigationPath()
        path.append(AppRoute.roomScan)
    }
}
