//
//  FloorScanListView.swift
//  ErgoraLiDAR
//

import AVFoundation
import SwiftUI
import UIKit

struct FloorScanListView: View {
    @EnvironmentObject private var flow: ScanFlowModel
    @Binding var path: NavigationPath

    @State private var isSubmitting = false
    @State private var showAddPhotosPrompt = false
    @State private var showInteriorPhotoCapture = false
    @State private var showPhotoCaptureDenied = false
    @State private var showPhotoCaptureUnavailable = false
    @State private var showAPIError = false
    @State private var apiErrorMessage = ""
    @State private var showUnauthorizedReturnStart = false
    @State private var showNetworkError = false
    @State private var networkErrorMessage = ""

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Floors Scanned")
                        .font(.largeTitle.weight(.semibold))

                    if flow.floorScans.isEmpty {
                        Text("No floors saved yet. Go back and complete a floor scan.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(flow.floorScans) { scan in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(scan.floorName)
                                        .font(.headline)
                                    Text("\(scan.rooms.count) rooms — \(Int(scan.totalArea)) sq ft")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    VStack(spacing: 16) {
                        Button {
                            scanAnotherFloor()
                        } label: {
                            Text("Scan Another Floor")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.ergoraTeal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await submitAll() }
                        } label: {
                            Text("Submit All to Ergora")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.ergoraTeal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(flow.floorScans.isEmpty || isSubmitting)

                        Button {
                            startOver()
                        } label: {
                            Text("Start Over")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .alert("Add Photos?", isPresented: $showAddPhotosPrompt) {
            Button("Add Photos") {
                beginInteriorPhotoCapture()
            }
            Button("Skip", role: .cancel) {
                path = NavigationPath()
                path.append(AppRoute.success)
            }
        } message: {
            Text("Would you like to add interior photos now?")
        }
        .alert("Could Not Submit", isPresented: $showAPIError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(apiErrorMessage)
        }
        .alert("Session Expired", isPresented: $showUnauthorizedReturnStart) {
            Button("Return to Start") {
                path = NavigationPath()
            }
        } message: {
            Text("Your session token is no longer valid. Scan the QR code again from the home screen.")
        }
        .alert("Network Error", isPresented: $showNetworkError) {
            Button("Retry") {
                Task { await submitAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(networkErrorMessage)
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
                    path = NavigationPath()
                    path.append(AppRoute.success)
                }
            )
        }
        .tint(Color.ergoraTeal)
    }

    private func scanAnotherFloor() {
        flow.sketchPayload = nil
        flow.lastCapturedRoom = nil
        flow.scanSessionID = UUID()
        if path.count >= 2 {
            path.removeLast(2)
        } else {
            path.removeLast(path.count)
        }
    }

    private func startOver() {
        flow.floorScans = []
        flow.sketchPayload = nil
        flow.lastCapturedRoom = nil
        flow.scanSessionID = UUID()
        path = NavigationPath()
    }

    private static func combinedPayload(from floorScans: [FloorScan]) -> SketchPayload {
        let allRooms = floorScans.flatMap(\.rooms)
        let totalGLA = allRooms.filter { !$0.isGarage && !$0.isOtherArea }.reduce(0) { $0 + $1.area }
        let garageAreaSqFt = allRooms.filter(\.isGarage).reduce(0) { $0 + $1.area }
        let otherAreaSqFt = allRooms.filter(\.isOtherArea).reduce(0) { $0 + $1.area }
        let totalWindowArea = allRooms.reduce(0) { partial, room in
            partial + room.windows.reduce(0) { $0 + $1.width * $1.height }
        }
        let storyFloors = Set(floorScans.map(\.floorNumber).filter { $0 >= 1 })
        let storiesCount = max(1, storyFloors.count)
        let scanId = UUID().uuidString
        return SketchPayload(
            rooms: allRooms,
            totalGLA: totalGLA,
            garageAreaSqFt: garageAreaSqFt,
            otherAreaSqFt: otherAreaSqFt,
            totalWindowArea: totalWindowArea,
            storiesCount: storiesCount,
            scanId: scanId
        )
    }

    private func submitAll() async {
        let token = flow.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            apiErrorMessage = "No session token. Please scan the QR code again."
            showAPIError = true
            return
        }
        guard !flow.floorScans.isEmpty else { return }
        let payload = Self.combinedPayload(from: flow.floorScans)
        isSubmitting = true
        let result = await ErgoraAPIClient.submitSketch(
            reportId: flow.reportId,
            token: token,
            payload: payload
        )
        isSubmitting = false
        switch result {
        case .success:
            showAddPhotosPrompt = true
        case .failure(let error):
            switch error {
            case .transport(let underlying):
                networkErrorMessage = underlying.localizedDescription
                showNetworkError = true
            case .httpStatus(let code, let message):
                if code == 401 {
                    showUnauthorizedReturnStart = true
                } else {
                    apiErrorMessage = message ?? error.localizedDescription
                    showAPIError = true
                }
            case .invalidURL, .decodingFailed:
                apiErrorMessage = error.localizedDescription
                showAPIError = true
            }
        }
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
}
