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
            Color.black.ignoresSafeArea()
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

/// All `AVCaptureSession` configuration and `startRunning` / `stopRunning` run on `sessionQueue` (not the main thread).
private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.ergora.ErgoraLiDAR.qrcapture", qos: .userInitiated)
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
        requestAccessAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in
                self?.configureSessionIfNeeded()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.sessionQueue.async {
                        self.configureSessionIfNeeded()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.onPermissionDenied?()
                    }
                }
            }
        default:
            onPermissionDenied?()
        }
    }

    /// Must run on `sessionQueue`. `commitConfiguration()` must finish before `startRunning()`.
    private func configureSessionIfNeeded() {
        if !session.inputs.isEmpty {
            if !session.isRunning {
                session.startRunning()
            }
            return
        }

        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.onPermissionDenied?()
            }
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.onPermissionDenied?()
            }
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: sessionQueue)
        output.metadataObjectTypes = [.qr]

        session.commitConfiguration()
        session.startRunning()
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

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.onCode?(value)
            }
        }
    }
}
