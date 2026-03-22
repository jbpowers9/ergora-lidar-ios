//
//  ContentView.swift
//  ErgoraLiDAR
//

import Combine
import SwiftUI

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

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.ergoraTeal.ignoresSafeArea()
                VStack {
                    Spacer(minLength: 0)
                    Button {
                        path.append(AppRoute.qrScanner)
                    } label: {
                        Text("Scan QR Code")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 28)
                            .background(Color.white)
                            .foregroundStyle(Color.ergoraTeal)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)
                    Spacer(minLength: 0)
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
}

#Preview {
    ContentView()
}
