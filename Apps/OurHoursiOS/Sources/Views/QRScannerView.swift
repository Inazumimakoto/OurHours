import AVFoundation
import SwiftUI

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraError: String?
    let onScan: @MainActor @Sendable (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let cameraError {
                    ContentUnavailableView("カメラを使用できません", systemImage: "camera", description: Text(cameraError))
                } else if authorization == .authorized {
                    if scenePhase == .active {
                        ScannerPreview(onScan: onScan, onError: { cameraError = $0 })
                            .accessibilityLabel("相手のQRコードをカメラに向けてください")
                    }
                } else if authorization == .notDetermined {
                    ProgressView("カメラの許可を待っています")
                } else {
                    ContentUnavailableView {
                        Label("カメラへのアクセスが必要です", systemImage: "camera")
                    } description: {
                        Text("設定でカメラを許可するか、前の画面で招待URLを貼り付けてください。")
                    } actions: {
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
            }
            .navigationTitle("QRコードを読み取る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { dismiss() }.font(FoamFont.bold(16)) }
            .task {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                authorization = AVCaptureDevice.authorizationStatus(for: .video)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { authorization = AVCaptureDevice.authorizationStatus(for: .video) }
            }
        }
        .font(FoamFont.medium(16))
    }
}

private struct ScannerPreview: UIViewRepresentable {
    let onScan: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void

    @MainActor
    final class Coordinator {
        var isPresented = true
        let capture: CaptureWorker
        init(capture: CaptureWorker) { self.capture = capture }
    }

    func makeCoordinator() -> Coordinator { Coordinator(capture: CaptureWorker()) }

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        let coordinator = context.coordinator
        coordinator.capture.attach(to: view.preview)
        coordinator.capture.start { [weak coordinator] result in
            guard coordinator?.isPresented == true else { return }
            switch result {
            case .success(let text): onScan(text)
            case .failure: onError("カメラでQRコードを読み取れません。招待URLを貼り付けてください。")
            }
        }
        return view
    }

    func updateUIView(_ uiView: CameraView, context: Context) {}

    static func dismantleUIView(_ uiView: CameraView, coordinator: Coordinator) {
        coordinator.isPresented = false
        coordinator.capture.stop()
    }
}

private final class CameraView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// The preview attaches before start. All capture operations and metadata callbacks use one serial queue.
private final class CaptureWorker: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    enum Failure: Error { case unavailable }
    typealias Completion = @MainActor @Sendable (Result<String, Failure>) -> Void
    private let queue = DispatchQueue(label: "OurHours.QRCapture")
    private let session = AVCaptureSession()
    private var completion: Completion?

    @MainActor func attach(to layer: AVCaptureVideoPreviewLayer) {
        layer.videoGravity = .resizeAspectFill
        layer.session = session
    }

    func start(completion: @escaping Completion) {
        queue.async { [self] in
            self.completion = completion
            guard let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else { finish(.failure(.unavailable)); return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { finish(.failure(.unavailable)); return }
            session.addOutput(output)
            guard output.availableMetadataObjectTypes.contains(.qr) else { finish(.failure(.unavailable)); return }
            output.setMetadataObjectsDelegate(self, queue: queue)
            output.metadataObjectTypes = [.qr]
            session.startRunning()
            if !session.isRunning { finish(.failure(.unavailable)) }
        }
    }

    func stop() {
        queue.async { [self] in
            completion = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for case let code as AVMetadataMachineReadableCodeObject in objects {
            if let value = code.stringValue { finish(.success(value)); return }
        }
    }

    private func finish(_ result: Result<String, Failure>) {
        guard let handler = completion else { return }
        completion = nil
        if session.isRunning { session.stopRunning() }
        Task { @MainActor in handler(result) }
    }
}
