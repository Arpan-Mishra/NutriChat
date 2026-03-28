import SwiftUI
import AVFoundation
import Vision
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "BarcodeScanner")

/// Barcode scanner using AVFoundation camera + Vision framework.
/// Supports EAN-13, UPC-A, and QR codes.
struct BarcodeScannerView: View {
    @Bindable var viewModel: FoodSearchViewModel
    var onFoodFound: (FoodSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scannedCode: String?
    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var showNotFoundAlert = false
    @State private var manualBarcode = ""
    @State private var showManualEntry = false

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(onBarcodeDetected: handleBarcodeDetected)
                .ignoresSafeArea()

            // Overlay UI
            VStack {
                Spacer()

                overlayContent
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding()
            }
        }
        .navigationTitle("Scan Barcode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Enter Manually") {
                    showManualEntry = true
                }
                .font(.subheadline)
            }
        }
        .alert("Food Not Found", isPresented: $showNotFoundAlert) {
            Button("Search Manually") {
                if let code = scannedCode {
                    viewModel.searchQuery = code
                }
                dismiss()
            }
            Button("Enter Barcode") {
                showManualEntry = true
            }
            Button("Cancel", role: .cancel) {
                scannedCode = nil
            }
        } message: {
            Text("No food found for barcode \(scannedCode ?? ""). Try searching manually or enter a different barcode.")
        }
        .alert("Enter Barcode", isPresented: $showManualEntry) {
            TextField("Barcode number", text: $manualBarcode)
                .keyboardType(.numberPad)
            Button("Look Up") {
                if !manualBarcode.isEmpty {
                    Task { await lookupBarcode(manualBarcode) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Overlay Content

    @ViewBuilder
    private var overlayContent: some View {
        if isLookingUp {
            HStack(spacing: 12) {
                ProgressView()
                Text("Looking up food...")
                    .font(.subheadline)
            }
            .padding(.vertical, 8)
        } else if let error = errorMessage {
            VStack(spacing: 8) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    errorMessage = nil
                    scannedCode = nil
                }
                .font(.caption)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                Text("Point camera at a barcode")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Barcode Handling

    private func handleBarcodeDetected(_ code: String) {
        guard scannedCode == nil && !isLookingUp else { return }
        scannedCode = code
        logger.info("Barcode detected: \(code, privacy: .public)")
        Task { await lookupBarcode(code) }
    }

    private func lookupBarcode(_ code: String) async {
        isLookingUp = true
        errorMessage = nil
        defer { isLookingUp = false }

        do {
            let food = try await FoodService.shared.fetchByBarcode(code: code)
            logger.info("Food found for barcode: \(food.foodName, privacy: .public)")
            onFoodFound(food)
        } catch let error as APIError {
            if case .notFound = error {
                showNotFoundAlert = true
            } else {
                errorMessage = error.localizedDescription
            }
            logger.warning("Barcode lookup failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Barcode lookup error: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Camera Preview (UIViewControllerRepresentable)

/// Wraps AVCaptureSession in a UIViewController for SwiftUI.
struct CameraPreviewView: UIViewControllerRepresentable {
    var onBarcodeDetected: (String) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onBarcodeDetected = onBarcodeDetected
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

/// UIViewController managing AVCaptureSession + Vision barcode detection.
final class CameraViewController: UIViewController {
    var onBarcodeDetected: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "app.nutrichat.camera.session")
    private let processingQueue = DispatchQueue(label: "app.nutrichat.camera.processing")
    private var hasDetected = false

    override func viewDidLoad() {
        super.viewDidLoad()
        checkPermissionAndSetup()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupCamera()
                }
            }
        case .denied, .restricted:
            logger.warning("Camera access denied")
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionDenied()
            }
        @unknown default:
            logger.warning("Unknown camera authorization status")
        }
    }

    private func showPermissionDenied() {
        let label = UILabel()
        label.text = "Camera access is required to scan barcodes.\n\nGo to Settings > NutriChat to enable it."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            captureSession.beginConfiguration()
            captureSession.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  captureSession.canAddInput(input) else {
                logger.error("Failed to setup camera input")
                captureSession.commitConfiguration()
                return
            }

            captureSession.addInput(input)

            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true

            guard captureSession.canAddOutput(videoOutput) else {
                logger.error("Failed to add video output")
                captureSession.commitConfiguration()
                return
            }

            captureSession.addOutput(videoOutput)
            captureSession.commitConfiguration()

            // Setup preview layer on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let layer = AVCaptureVideoPreviewLayer(session: captureSession)
                layer.videoGravity = .resizeAspectFill
                layer.frame = view.bounds
                view.layer.addSublayer(layer)
                previewLayer = layer
            }

            // Start running on background thread (Rule: never on MainActor)
            captureSession.startRunning()
            logger.debug("Camera session started")
        }
    }
}

// MARK: - Video Output Delegate + Vision Barcode Detection

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !hasDetected,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self, !hasDetected else { return }

            if let error {
                logger.error("Vision barcode error: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let results = request.results as? [VNBarcodeObservation],
                  let barcode = results.first,
                  let payload = barcode.payloadStringValue else { return }

            // Only accept supported formats
            let supportedFormats: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .qr]
            guard supportedFormats.contains(barcode.symbology) else { return }

            hasDetected = true
            DispatchQueue.main.async { [weak self] in
                self?.onBarcodeDetected?(payload)
            }
        }

        // Restrict to relevant barcode types
        request.symbologies = [.ean13, .ean8, .upce, .qr]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

#Preview {
    NavigationStack {
        BarcodeScannerView(viewModel: FoodSearchViewModel()) { _ in }
    }
}
