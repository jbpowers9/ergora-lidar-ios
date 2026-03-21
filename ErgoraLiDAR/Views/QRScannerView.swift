//
//  QRScannerView.swift
//  ErgoraLiDAR
//

import AVFoundation
import SwiftUI
import UIKit

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onParsed: (UUID, String) -> Void

    @State private var permissionDenied = false
    @State private var parseError: String?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            QRScannerRepresentable(
                onCode: { string in
                    handle(code: string)
                },
                onPermissionDenied: {
                    permissionDenied = true
                }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding()
                Spacer()
                if let parseError {
                    Text(parseError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Camera Access", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ergora LiDAR needs camera access to scan QR codes. Enable it in Settings.")
        }
    }

    private func handle(code: String) {
        parseError = nil
        guard let url = URL(string: code),
              url.scheme?.lowercased() == "ergora",
              url.host?.lowercased() == "scan"
        else {
            parseError = "Invalid QR code."
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            parseError = "Invalid QR code."
            return
        }
        let items = components.queryItems ?? []
        let reportString = items.first(where: { $0.name.lowercased() == "reportid" })?.value
        let token = items.first(where: { $0.name.lowercased() == "token" })?.value
        guard let reportString, let uuid = UUID(uuidString: reportString), let token, !token.isEmpty else {
            parseError = "Could not read report ID or token."
            return
        }
        onParsed(uuid, token)
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        controller.onPermissionDenied = onPermissionDenied
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { @MainActor in
            await configureSessionIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    @MainActor
    private func configureSessionIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.configureSessionIfNeeded()
                    } else {
                        self?.onPermissionDenied?()
                    }
                }
            }
            return
        default:
            onPermissionDenied?()
            return
        }

        guard session.inputs.isEmpty else {
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
            }
            return
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            onPermissionDenied?()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onPermissionDenied?()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue
        else { return }
        session.stopRunning()
        onCode?(value)
    }
}
