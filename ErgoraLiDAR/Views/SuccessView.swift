//
//  SuccessView.swift
//  ErgoraLiDAR
//

import SwiftUI

struct SuccessView: View {
    @EnvironmentObject private var flow: ScanFlowModel
    @Binding var path: NavigationPath

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 24) {
                if let payload = flow.sketchPayload {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.ergoraTeal)
                        .padding(.bottom, 8)

                    Text("Submitted")
                        .font(.largeTitle.weight(.semibold))

                    Text("Your sketch was sent to Ergora.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        row(title: "GLA", value: String(format: "%.0f sq ft", payload.totalGLA))
                        row(title: "Window area", value: String(format: "%.0f sq ft", payload.totalWindowArea))
                        row(title: "Rooms scanned", value: "\(payload.rooms.count)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Text("No scan data.")
                }

                Button {
                    path = NavigationPath()
                } label: {
                    Text("Done")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.ergoraTeal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.body)
    }
}
