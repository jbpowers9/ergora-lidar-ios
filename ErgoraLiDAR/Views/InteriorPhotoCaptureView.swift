//
//  InteriorPhotoCaptureView.swift
//  ErgoraLiDAR
//

import AVFoundation
import SwiftUI
import UIKit

struct InteriorPhotoCaptureView: View {
    let reportId: UUID
    let token: String
    let onFinish: () -> Void

    @State private var showCamera = false
    @State private var stagedImage: UIImage?
    @State private var photosAdded = 0
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadErrorMessage = ""
    @State private var showUploadError = false
    @State private var showCameraUnavailable = false
    @State private var showCameraDenied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Close") {
                        onFinish()
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }

                Text("\(photosAdded) photos added")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                if let img = stagedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if isUploading {
                        VStack(spacing: 8) {
                            ProgressView(value: uploadProgress)
                                .tint(Color.ergoraTeal)
                            Text("Uploading… \(Int(uploadProgress * 100))%")
                                .foregroundStyle(.white.opacity(0.85))
                                .font(.subheadline)
                        }
                        .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 16) {
                            Button("Retake") {
                                stagedImage = nil
                                presentCameraIfAllowed()
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)

                            Button("Use Photo") {
                                Task { await uploadStaged() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ergoraTeal)
                        }
                    }
                } else {
                    Text("Take photos of interior spaces")
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

                if stagedImage == nil, !isUploading {
                    Button {
                        presentCameraIfAllowed()
                    } label: {
                        Text("Take Photo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.ergoraTeal)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onFinish()
                } label: {
                    Text("Done Adding Photos")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.18))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isUploading)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: $stagedImage, isPresented: $showCamera)
                .ignoresSafeArea()
        }
        .alert("Camera Unavailable", isPresented: $showCameraUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device cannot use the camera for photos.")
        }
        .alert("Camera Access Needed", isPresented: $showCameraDenied) {
            Button("Cancel", role: .cancel) {}
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Settings") {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Allow camera access in Settings to add interior photos.")
        }
        .alert("Upload Failed", isPresented: $showUploadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploadErrorMessage)
        }
    }

    private func presentCameraIfAllowed() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailable = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        showCameraDenied = true
                    }
                }
            }
        default:
            showCameraDenied = true
        }
    }

    @MainActor
    private func uploadStaged() async {
        guard let img = stagedImage, let data = img.jpegData(compressionQuality: 0.85) else { return }
        let tokenTrim = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tokenTrim.isEmpty else {
            uploadErrorMessage = "No session token. Please scan the QR code again."
            showUploadError = true
            return
        }
        isUploading = true
        uploadProgress = 0
        let result = await ErgoraAPIClient.uploadInteriorPhoto(
            reportId: reportId,
            token: tokenTrim,
            imageJPEGData: data,
            progress: { p in
                uploadProgress = p
            }
        )
        isUploading = false
        switch result {
        case .success:
            photosAdded += 1
            stagedImage = nil
        case .failure(let error):
            uploadErrorMessage = error.localizedDescription
            showUploadError = true
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}
