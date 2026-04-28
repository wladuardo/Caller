import AVFoundation
import SwiftUI

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        private let onCodeScanned: (String) -> Void
        private let onFailure: (String) -> Void

        init(
            onCodeScanned: @escaping (String) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.onCodeScanned = onCodeScanned
            self.onFailure = onFailure
        }

        func scannerViewController(_ controller: ScannerViewController, didScan code: String) {
            onCodeScanned(code)
        }

        func scannerViewController(_ controller: ScannerViewController, didFailWith message: String) {
            onFailure(message)
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func scannerViewController(_ controller: ScannerViewController, didScan code: String)
    func scannerViewController(_ controller: ScannerViewController, didFailWith message: String)
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var didReportResult = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.stopRunning()
            }
        }
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.setupCaptureSession()
                    } else {
                        self.delegate?.scannerViewController(
                            self,
                            didFailWith: "Для сканирования QR-кода нужен доступ к камере."
                        )
                    }
                }
            }
        default:
            delegate?.scannerViewController(
                self,
                didFailWith: "Для сканирования QR-кода нужен доступ к камере."
            )
        }
    }

    private func setupCaptureSession() {
        guard previewLayer.superlayer == nil else { return }

        do {
            session.beginConfiguration()

            guard let device = AVCaptureDevice.default(for: .video) else {
                session.commitConfiguration()
                delegate?.scannerViewController(self, didFailWith: "Камера недоступна на этом устройстве.")
                return
            }

            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }

            session.commitConfiguration()

            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)

            let overlay = ScannerOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: view.topAnchor),
                overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } catch {
            session.commitConfiguration()
            delegate?.scannerViewController(self, didFailWith: "Не удалось настроить камеру.")
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didReportResult,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let code = object.stringValue else {
            return
        }

        didReportResult = true
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.stopRunning()
            }
        }
        delegate?.scannerViewController(self, didScan: code)
    }
}

private final class ScannerOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let cutoutSize = CGSize(width: 240, height: 240)
        let cutoutRect = CGRect(
            x: rect.midX - cutoutSize.width / 2,
            y: rect.midY - cutoutSize.height / 2,
            width: cutoutSize.width,
            height: cutoutSize.height
        )

        let overlayPath = UIBezierPath(rect: rect)
        let cutoutPath = UIBezierPath(roundedRect: cutoutRect, cornerRadius: 28)
        overlayPath.append(cutoutPath)
        overlayPath.usesEvenOddFillRule = true

        context.saveGState()
        overlayPath.addClip()
        UIColor.black.withAlphaComponent(0.48).setFill()
        overlayPath.fill()
        context.restoreGState()

        UIColor.white.withAlphaComponent(0.9).setStroke()
        cutoutPath.lineWidth = 3
        cutoutPath.stroke()
    }
}
