//
//  ContentView.swift
//  ErgoraLiDAR
//

import SwiftUI
import Combine

extension Color {
    static let ergoraTeal = Color(red: 13 / 255, green: 148 / 255, blue: 136 / 255)
}

@MainActor
final class ScanFlowModel: ObservableObject {
    @Published var reportId: UUID = UUID()
    @Published var token: String = ""
    @Published var sketchPayload: SketchPayload?
    @Published var scanSessionID = UUID()
}

enum AppRoute: Hashable {
    case qrScanner
    case roomScan
    case scanResult
    case success
}

struct ContentView: View {
    @StateObject private var flow = ScanFlowModel()
    @State private var path = NavigationPath()
    @State private var manualReportId: String = ""
    @State private var manualToken: String = ""
    @State private var manualError: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.white.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Ergora LiDAR")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            path.append(AppRoute.qrScanner)
                        } label: {
                            Text("Scan QR Code")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.ergoraTeal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Enter Report ID")
                                .font(.headline)
                            TextField("Report UUID", text: $manualReportId)
                                .textContentType(.none)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            SecureField("Token", text: $manualToken)
                                .textContentType(.password)
                                .padding(14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if let manualError {
                                Text(manualError)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            Button {
                                connectManually()
                            } label: {
                                Text("Connect")
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color.ergoraTeal)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .qrScanner:
                    QRScannerView(
                        onParsed: { reportId, token in
                            flow.reportId = reportId
                            flow.token = token
                            flow.scanSessionID = UUID()
                            path.removeLast()
                            path.append(AppRoute.roomScan)
                        }
                    )
                case .roomScan:
                    RoomScanView(path: $path)
                        .environmentObject(flow)
                        .id(flow.scanSessionID)
                case .scanResult:
                    ScanResultView(path: $path)
                        .environmentObject(flow)
                case .success:
                    SuccessView(path: $path)
                        .environmentObject(flow)
                }
            }
        }
        .environmentObject(flow)
        .tint(Color.ergoraTeal)
    }

    private func connectManually() {
        manualError = nil
        let trimmedId = manualReportId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: trimmedId) else {
            manualError = "Enter a valid report UUID."
            return
        }
        guard !trimmedToken.isEmpty else {
            manualError = "Token is required."
            return
        }
        flow.reportId = id
        flow.token = trimmedToken
        flow.scanSessionID = UUID()
        path.append(AppRoute.roomScan)
    }
}

#Preview {
    ContentView()
}
