//
//  RoomScanView.swift
//  ErgoraLiDAR
//

import ARKit
import Combine
import RoomPlan
import SwiftUI
import UIKit

private struct FloorOption: Hashable {
    let title: String
    let floorNumber: Int
}

/// Hosts `RoomCaptureView` and bridges RoomPlan callbacks. Session delegate conformance is implemented by
/// `RoomScanCaptureCoordinator` (`RoomCaptureSessionDelegate`).
struct RoomScanView: View {
    @EnvironmentObject private var flow: ScanFlowModel
    @Binding var path: NavigationPath

    @StateObject private var driver = RoomCaptureDriver()
    @State private var showLiDARAlert = false
    @State private var showProcessError = false
    @State private var processErrorMessage = ""
    @State private var isProcessing = false
    @State private var hasStartedScan = false
    @State private var selectedFloorOption: FloorOption = FloorOption(title: "First Floor", floorNumber: 1)

    private static let floorOptions: [FloorOption] = [
        FloorOption(title: "First Floor", floorNumber: 1),
        FloorOption(title: "Second Floor", floorNumber: 2),
        FloorOption(title: "Third Floor", floorNumber: 3),
        FloorOption(title: "Basement", floorNumber: 0),
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if hasStartedScan {
                RoomCaptureRepresentable(
                    driver: driver,
                    onCapturedRoom: { room in
                        isProcessing = false
                        flow.lastCapturedRoom = room
                        let payload = RoomDataProcessor.sketchPayload(from: room, selectedFloor: flow.selectedScanFloor)
                        flow.sketchPayload = payload
                        if path.count > 0 {
                            path.removeLast()
                        }
                        path.append(AppRoute.scanResult)
                    },
                    onError: { error in
                        isProcessing = false
                        processErrorMessage = error.localizedDescription
                        showProcessError = true
                    },
                    onProcessingChange: { isProcessing = $0 }
                )
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button("Cancel") {
                        path = NavigationPath()
                    }
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding()
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    if !hasStartedScan {
                        Text("Which floor are you scanning?")
                            .font(.headline)
                        Picker("Floor", selection: $selectedFloorOption) {
                            ForEach(Self.floorOptions, id: \.self) { opt in
                                Text(opt.title).tag(opt)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .onChange(of: selectedFloorOption) { _, newValue in
                            flow.selectedScanFloor = newValue.floorNumber
                        }

                        Text(
                            "Scan one floor at a time. Walk slowly through each room on this floor, then tap Done. Scan each floor separately."
                        )
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            flow.selectedScanFloor = selectedFloorOption.floorNumber
                            hasStartedScan = true
                        } label: {
                            Text("Start scanning")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.ergoraTeal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(
                            "Scan one floor at a time. Walk slowly through each room on this floor, then tap Done. Scan each floor separately."
                        )
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            isProcessing = true
                            driver.stopCapture()
                        } label: {
                            Text("Done Scanning")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.ergoraTeal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                    }
                }
                .padding(24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                showLiDARAlert = true
            }
            flow.selectedScanFloor = selectedFloorOption.floorNumber
        }
        .alert("LiDAR Required", isPresented: $showLiDARAlert) {
            Button("OK", role: .cancel) {
                path = NavigationPath()
            }
        } message: {
            Text("This feature requires iPhone 12 Pro or later with LiDAR")
        }
        .alert("Scan Error", isPresented: $showProcessError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(processErrorMessage)
        }
    }
}

@MainActor
final class RoomCaptureDriver: ObservableObject {
    weak var captureView: RoomCaptureView?

    func stopCapture() {
        captureView?.captureSession.stop()
    }
}

private struct RoomCaptureRepresentable: UIViewRepresentable {
    @ObservedObject var driver: RoomCaptureDriver
    let onCapturedRoom: (CapturedRoom) -> Void
    let onError: (Error) -> Void
    let onProcessingChange: (Bool) -> Void

    func makeCoordinator() -> RoomScanCaptureCoordinator {
        RoomScanCaptureCoordinator(
            onCapturedRoom: onCapturedRoom,
            onError: onError,
            onProcessingChange: onProcessingChange
        )
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        context.coordinator.captureView = view
        driver.captureView = view
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

final class RoomScanCaptureCoordinator: NSObject, RoomCaptureSessionDelegate {
    var captureView: RoomCaptureView?
    let onCapturedRoom: (CapturedRoom) -> Void
    let onError: (Error) -> Void
    let onProcessingChange: (Bool) -> Void

    init(
        onCapturedRoom: @escaping (CapturedRoom) -> Void,
        onError: @escaping (Error) -> Void,
        onProcessingChange: @escaping (Bool) -> Void
    ) {
        self.onCapturedRoom = onCapturedRoom
        self.onError = onError
        self.onProcessingChange = onProcessingChange
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if let error {
            Task { @MainActor in
                self.onProcessingChange(false)
                self.onError(error)
            }
            return
        }
        Task {
            do {
                let room = try await RoomBuilder(options: []).capturedRoom(from: data)
                await MainActor.run {
                    self.onProcessingChange(false)
                    self.onCapturedRoom(room)
                }
            } catch {
                await MainActor.run {
                    self.onProcessingChange(false)
                    self.onError(error)
                }
            }
        }
    }
}
