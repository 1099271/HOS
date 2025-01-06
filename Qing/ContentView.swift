//
//  ContentView.swift
//  Qing
//
//  Created by Ryan on 2025/1/6.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var isShowingCamera = false
    
    var body: some View {
        VStack {
            Text("你好，这里是轻 App")
                .padding()
            
            Button(action: {
                // 检查相机权限并打开相机
                checkCameraPermissionAndOpen()
            }) {
                Text("打开相机")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraView()
        }
    }
    
    private func checkCameraPermissionAndOpen() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        isShowingCamera = true
                    }
                }
            }
        case .denied:
            print("相机访问被拒绝")
        case .restricted:
            print("相机访问受限")
        @unknown default:
            print("未知错误")
        }
    }
}

// 相机视图
struct CameraView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
            
            VStack {
                // 顶部返回按钮
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                }
                
                Spacer()
                
                // 底部切换相机按钮
                Button(action: {
                    camera.switchCamera()
                }) {
                    Image(systemName: "camera.rotate")
                        .font(.largeTitle)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            camera.checkAuthorization()
        }
    }
}

// 相机预览视图
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        
        DispatchQueue.main.async {
            view.layer.addSublayer(previewLayer)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
                previewLayer.frame = uiView.frame
            }
        }
    }
}

// 相机模型
class CameraModel: ObservableObject {
    @Published var isCameraReady = false
    let session = AVCaptureSession()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentDevice: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    
    init() {
        DispatchQueue.main.async {
            self.setupSession()
        }
    }
    
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { [weak self] in
                self?.setupSession()
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.session.startRunning()
                }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupSession()
                        DispatchQueue.global(qos: .userInitiated).async {
                            self?.session.startRunning()
                        }
                    }
                }
            }
        default:
            break
        }
    }
    
    private func setupSession() {
        // 确保在后台线程停止会话
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        
        session.beginConfiguration()
        
        // 移除现有的输入
        for input in session.inputs {
            session.removeInput(input)
        }
        
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: .back) else {
            session.commitConfiguration()
            return
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
            self.input = input
            self.currentDevice = device
        }
        
        session.commitConfiguration()
    }
    
    func switchCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                self.session.stopRunning()
            }
            
            DispatchQueue.main.async {
                guard let currentInput = self.input else { return }
                self.session.beginConfiguration()
                self.session.removeInput(currentInput)
                
                self.currentPosition = self.currentPosition == .back ? .front : .back
                
                guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: self.currentPosition) else {
                    self.session.commitConfiguration()
                    return
                }
                
                guard let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                    self.session.commitConfiguration()
                    return
                }
                
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.input = newInput
                    self.currentDevice = newDevice
                }
                
                self.session.commitConfiguration()
                
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.startRunning()
                }
            }
        }
    }
    
    deinit {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if self?.session.isRunning == true {
                self?.session.stopRunning()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
