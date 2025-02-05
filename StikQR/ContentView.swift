//
//  ContentView.swift
//  StikQR
//
//  Created by Stephen on 2/4/25.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Vision
import PhotosUI

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ScannedCode: Identifiable, Codable {
    let id = UUID()
    let content: String
    let timestamp: Date
}

class QRScannerViewController: UIViewController {
    weak var delegate: QRScannerView.Coordinator?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCamera()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if captureSession?.isRunning == false {
            startCamera()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCamera()
    }
    
    private func startCamera() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    private func stopCamera() {
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
    
    private func setupCaptureSession() {
        let captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        delegate?.captureDevice = videoCaptureDevice
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        self.captureSession = captureSession
        self.previewLayer = previewLayer
        
        startCamera()
    }
    
    func toggleTorch(isOn: Bool) {
        guard let device = delegate?.captureDevice,
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = isOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be configured: \(error)")
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void
    @Binding var isTorchOn: Bool
    
    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerView
        var captureDevice: AVCaptureDevice?
        var viewController: QRScannerViewController?
        
        init(parent: QRScannerView) {
            self.parent = parent
            super.init()
        }
        
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let stringValue = metadataObject.stringValue {
                DispatchQueue.main.async {
                    self.parent.onCodeScanned(stringValue)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let viewController = QRScannerViewController()
        viewController.delegate = context.coordinator
        context.coordinator.viewController = viewController
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.toggleTorch(isOn: isTorchOn)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct HelpView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("How to Use")) {
                    Text("1. Point your camera at a QR code")
                    Text("2. Align the code within the blue frame")
                    Text("3. The app will automatically scan the code")
                    Text("4. Use the flashlight button if needed in low light")
                }
                
                Section(header: Text("Features")) {
                    Text("• Open scanned codes in a browser")
                    Text("• Export all codes as a text file")
                    Text("• Copy codes to clipboard")
                    Text("• Automatic duplicate prevention")
                }
                
                Section(header: Text("Tips")) {
                    Text("• Make sure the QR code is well-lit")
                    Text("• Keep your device steady while scanning")
                    Text("• Clean your camera lens for better results")
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"))")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Help")
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct GenerateQRView: View {
    @State private var text = ""
    @State private var qrImage: UIImage?
    @State private var showShareSheet = false
    @State private var showSaveConfirmation = false
    @State private var showingHelp = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
                    .frame(height: 300)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                            .padding()
                    )
                
                if let image = qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .background(Color.white)
                        .cornerRadius(10)
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 50))
                        .foregroundColor(.blue.opacity(0.3))
                }
            }
            
            TextField("Enter website URL or text", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .autocapitalization(.none)
            
            if !text.isEmpty {
                HStack {
                    Button(action: { showShareSheet = true }) {
                        Label("Share QR Code", systemImage: "square.and.arrow.up")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button(action: {
                        if let image = qrImage {
                            saveImageToCameraRoll(image: image)
                        }
                    }) {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .navigationBarItems(trailing: Button(action: { showingHelp = true }) {
            Image(systemName: "questionmark.circle")
        })
        .sheet(isPresented: $showingHelp) {
            GenerateQRHelpView(isPresented: $showingHelp)
        }
        .onChange(of: text) { _ in
            qrImage = generateQRCode(from: text)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = qrImage {
                ShareSheet(activityItems: [image])
            }
        }
        .alert(isPresented: $showSaveConfirmation) {
            Alert(title: Text("Saved"), message: Text("The QR code has been saved to your photos."), dismissButton: .default(Text("OK")))
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = UIScreen.main.scale
        let transformScale = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transformScale)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    private func saveImageToCameraRoll(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showSaveConfirmation = true
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct GenerateQRHelpView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("How to Generate")) {
                    Text("1. Enter text or URL in the input field")
                    Text("2. QR code generates automatically")
                    Text("3. Use share or save buttons to export")
                }
                
                Section(header: Text("What You Can Share")) {
                    Text("• Website URLs")
                    Text("• Plain text messages")
                    Text("• and much more!")
                }
                
                Section(header: Text("Tips")) {
                    Text("• Keep content concise for better scanning")
                    Text("• Test the QR code before sharing")
                    Text("• Save important codes to Photos")
                }
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"))")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("QR Generator Help")
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
        }
    }
}

struct ContentView: View {
    @AppStorage("scannedCodes") private var storedCodes: Data = Data()
    @State private var scannedCodes: [ScannedCode] = []
    @State private var exportFile: ExportFile?
    @State private var showClearAlert = false
    @State private var isTorchOn = false
    @State private var showingHelp = false
    @State private var showingPhotoPicker = false
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                VStack(spacing: 0) {
                    scannerSection
                    scannedCodesList
                    actionButtons
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Scan")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingHelp = true }) {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                }
            }
            .tabItem {
                Label("Scan", systemImage: "qrcode.viewfinder")
            }
            .tag(0)
            
            NavigationView {
                GenerateQRView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Generate")
                                .font(.headline)
                        }
                    }
            }
            .tabItem {
                Label("Generate", systemImage: "qrcode")
            }
            .tag(1)
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .sheet(isPresented: $showingHelp) {
            HelpView(isPresented: $showingHelp)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            ImagePicker(completion: handleSelectedImage)
        }
        .alert("Clear All Codes?", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                scannedCodes.removeAll()
                saveToStorage()
            }
        } message: {
            Text("This will remove all scanned QR codes. This action cannot be undone.")
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadFromStorage)
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var scannerSection: some View {
        ZStack {
            QRScannerView(onCodeScanned: handleScannedCode, isTorchOn: $isTorchOn)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                )
            
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 200, height: 200)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 50))
                            .foregroundColor(.blue.opacity(0.3))
                    )
                Spacer()
            }
            
            VStack {
                HStack {
                    Spacer()
                        .frame(width: 16)
                    
                    Button(action: { showingPhotoPicker = true }) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Button(action: { isTorchOn.toggle() }) {
                        Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(isTorchOn ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                        .frame(width: 16)
                }
                .padding(.top, 16)
                
                Spacer()
            }
            
            VStack {
                Spacer()
                Text("Align QR Code in Frame")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
            }
        }
    }
    
    private var scannedCodesList: some View {
        List {
            ForEach(scannedCodes.reversed()) { code in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(code.content)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(size: 16, weight: .medium))
                        
                        Spacer()
                    }
                    
                    Text(code.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .contextMenu {
                    Button(action: { openCode(code) }) {
                        Label("Open", systemImage: "safari")
                    }
                    
                    Button(action: { UIPasteboard.general.string = code.content }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: { exportSingleCode(code) }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(role: .destructive, action: { deleteCode(code) }) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxHeight: 300)
    }
    
    private var actionButtons: some View {
        HStack {
            Button(action: exportTextFile) {
                Label("Export All", systemImage: "square.and.arrow.up")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(scannedCodes.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(scannedCodes.isEmpty)
            
            Button(action: { showClearAlert = true }) {
                Label("Clear All", systemImage: "trash")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(scannedCodes.isEmpty ? Color.gray : Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(scannedCodes.isEmpty)
        }
        .padding()
    }
    
    private func handleScannedCode(_ code: String) {
        if !scannedCodes.contains(where: { $0.content == code }) {
            let newCode = ScannedCode(content: code, timestamp: Date())
            scannedCodes.append(newCode)
            saveToStorage()
        }
    }
    
    private func openCode(_ code: ScannedCode) {
        if let url = URL(string: code.content), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func exportSingleCode(_ code: ScannedCode) {
        let fileName = "ScannedQRCode_\(code.id).txt"
        var text = "StikQR Export\nDate: \(Date().formatted())\n\n"
        
        text += "Code: \(code.content)\n"
        text += "Scanned: \(code.timestamp.formatted())\n"
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportFile = ExportFile(url: url)
        } catch {
            print("Failed to save file: \(error)")
        }
    }
    
    private func deleteCode(_ code: ScannedCode) {
        scannedCodes.removeAll { $0.id == code.id }
        saveToStorage()
    }
    
    private func exportTextFile() {
        let fileName = "ScannedQRCodes.txt"
        var text = "StikQR Export\nDate: \(Date().formatted())\n\n"
        
        for code in scannedCodes {
            text += "Code: \(code.content)\n"
            text += "Scanned: \(code.timestamp.formatted())\n"
            text += "-------------------\n"
        }
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportFile = ExportFile(url: url)
        } catch {
            print("Failed to save file: \(error)")
        }
    }
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(scannedCodes) {
            storedCodes = encoded
        }
    }
    
    private func loadFromStorage() {
        if let decoded = try? JSONDecoder().decode([ScannedCode].self, from: storedCodes) {
            scannedCodes = decoded
        }
    }
    
    private func handleSelectedImage(_ image: UIImage?) {
        guard let image = image?.fixOrientation() else {
            print("No image selected or image is invalid")
            return
        }
        
        let targetSize = CGSize(width: 1024, height: 1024)
        guard let resizedImage = resizeImage(image, targetSize: targetSize),
              let cgImage = resizedImage.cgImage else {
            print("Failed to resize or convert UIImage to CGImage")
            return
        }
        
        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                print("Failed to detect barcodes: \(error.localizedDescription)")
                return
            }
            
            guard let results = request.results as? [VNBarcodeObservation],
                  let qrCode = results.first?.payloadStringValue else {
                print("No QR code detected in the image")
                return
            }
            
            DispatchQueue.main.async {
                self.handleScannedCode(qrCode)
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("Failed to process image: \(error.localizedDescription)")
        }
    }
    
    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        let newSize = CGSize(
            width: size.width * min(widthRatio, heightRatio),
            height: size.height * min(widthRatio, heightRatio)
        )
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (UIImage?) -> Void
        
        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else {
                completion(nil)
                return
            }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        self.completion(image as? UIImage)
                    }
                }
            }
        }
    }
}

extension UIImage {
    func fixOrientation() -> UIImage {
        if self.imageOrientation == .up {
            return self
        }
        
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }
}
