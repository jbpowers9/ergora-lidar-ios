//
//  ScanResultView.swift
//  ErgoraLiDAR
//

import SwiftUI

struct ScanResultView: View {
    @EnvironmentObject private var flow: ScanFlowModel
    @Binding var path: NavigationPath

    @State private var isSubmitting = false
    @State private var showAPIError = false
    @State private var apiErrorMessage = ""
    @State private var showNetworkError = false
    @State private var networkErrorMessage = ""

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
                        ForEach(Array(payload.rooms.enumerated()), id: \.offset) { _, room in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(room.name)
                                    .font(.title3.weight(.semibold))
                                Text(String(format: "%.0f sq ft", room.area))
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

                        summaryRow(title: "Total GLA", value: String(format: "%.0f sq ft", payload.totalGLA))
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
        .alert("Could Not Submit", isPresented: $showAPIError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(apiErrorMessage)
        }
        .alert("Network Error", isPresented: $showNetworkError) {
            Button("Retry") {
                Task { await submit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(networkErrorMessage)
        }
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
        guard let payload = flow.sketchPayload else { return }
        isSubmitting = true
        let result = await ErgoraAPIClient.submitSketch(
            reportId: flow.reportId,
            token: flow.token,
            payload: payload
        )
        isSubmitting = false
        switch result {
        case .success:
            path.append(AppRoute.success)
        case .failure(let error):
            switch error {
            case .transport(let underlying):
                networkErrorMessage = underlying.localizedDescription
                showNetworkError = true
            case .httpStatus(_, let message):
                apiErrorMessage = message ?? error.localizedDescription
                showAPIError = true
            case .invalidURL, .decodingFailed:
                apiErrorMessage = error.localizedDescription ?? "Unknown error"
                showAPIError = true
            }
        }
    }

    private func rescan() {
        flow.scanSessionID = UUID()
        flow.sketchPayload = nil
        path = NavigationPath()
        path.append(AppRoute.roomScan)
    }
}
