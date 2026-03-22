//
//  ScanResultView.swift
//  ErgoraLiDAR
//

import AVFoundation
import SwiftUI
import UIKit

struct ScanResultView: View {
    @EnvironmentObject private var flow: ScanFlowModel
    @Binding var path: NavigationPath

    @State private var isSubmitting = false
    @State private var showAPIError = false
    @State private var apiErrorTitle = "Could Not Submit"
    @State private var apiErrorMessage = ""
    @State private var showUnauthorizedReturnStart = false
    @State private var showNetworkError = false
    @State private var networkErrorMessage = ""

    @State private var editingRoomIndex: Int?
    @State private var draftRoomName: String = ""

    @State private var showFloorSubmittedPrompt = false
    @State private var showInteriorPhotoCapture = false
    @State private var showPhotoCaptureDenied = false
    @State private var showPhotoCaptureUnavailable = false

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
                                Task { await submit() }
                            } label: {
                                Text("Submit to Ergora")
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color.ergoraTeal)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isSubmitting || flow.sketchPayload == nil)

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
        .alert(apiErrorTitle, isPresented: $showAPIError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(apiErrorMessage)
        }
        .alert("Session Expired", isPresented: $showUnauthorizedReturnStart) {
            Button("Return to Start") {
                path = NavigationPath()
            }
        } message: {
            Text(
                "Your session token is no longer valid. Tap Return to Start to scan a new QR code. Your scan results on this screen stay in memory until you submit or rescan."
            )
        }
        .alert("Network Error", isPresented: $showNetworkError) {
            Button("Retry") {
                Task { await submit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(networkErrorMessage)
        }
        .alert("Floor Submitted", isPresented: $showFloorSubmittedPrompt) {
            Button("Scan Another Floor") {
                flow.scanSessionID = UUID()
                flow.sketchPayload = nil
                flow.lastCapturedRoom = nil
                path.removeLast()
            }
            Button("Add Photos") {
                beginInteriorPhotoCapture()
            }
            Button("Done") {
                path.append(AppRoute.success)
            }
        } message: {
            Text("Scan another floor or finish?")
        }
        .alert("Camera Access Needed", isPresented: $showPhotoCaptureDenied) {
            Button("Cancel", role: .cancel) {}
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Settings") {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Allow camera access in Settings to add interior photos.")
        }
        .alert("Camera Unavailable", isPresented: $showPhotoCaptureUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device cannot capture photos.")
        }
        .fullScreenCover(isPresented: $showInteriorPhotoCapture) {
            InteriorPhotoCaptureView(
                reportId: flow.reportId,
                token: flow.token.trimmingCharacters(in: .whitespacesAndNewlines),
                onFinish: {
                    showInteriorPhotoCapture = false
                    path.append(AppRoute.success)
                }
            )
        }
        .tint(Color.ergoraTeal)
    }

    private func beginInteriorPhotoCapture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showPhotoCaptureUnavailable = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showInteriorPhotoCapture = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showInteriorPhotoCapture = true
                    } else {
                        showPhotoCaptureDenied = true
                    }
                }
            }
        default:
            showPhotoCaptureDenied = true
        }
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

    private func submit() async {
        let token = flow.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            apiErrorTitle = "No Session"
            apiErrorMessage = "No session token. Please scan the QR code again."
            showAPIError = true
            return
        }
        guard let payload = flow.sketchPayload else { return }
        isSubmitting = true
        let result = await ErgoraAPIClient.submitSketch(
            reportId: flow.reportId,
            token: token,
            payload: payload
        )
        isSubmitting = false
        switch result {
        case .success:
            showFloorSubmittedPrompt = true
        case .failure(let error):
            switch error {
            case .transport(let underlying):
                networkErrorMessage = underlying.localizedDescription
                showNetworkError = true
            case .httpStatus(let code, let message):
                if code == 401 {
                    // No server refresh token for scan sessions; user rescans QR from home (see ErgoraAPIClient header).
                    showUnauthorizedReturnStart = true
                } else {
                    apiErrorTitle = "Could Not Submit"
                    apiErrorMessage = message ?? error.localizedDescription
                    showAPIError = true
                }
            case .invalidURL, .decodingFailed:
                apiErrorTitle = "Could Not Submit"
                apiErrorMessage = error.localizedDescription
                showAPIError = true
            }
        }
    }

    private func rescan() {
        flow.scanSessionID = UUID()
        flow.sketchPayload = nil
        flow.lastCapturedRoom = nil
        path = NavigationPath()
        path.append(AppRoute.roomScan)
    }
}
