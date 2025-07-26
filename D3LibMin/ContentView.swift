//
//  ContentView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @State private var showLatestImage = false
    @State private var latestImage: UIImage?
    @State private var showPixelWave = false
    @State private var showCenterPixelWave = false
    @State private var showToast = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            TabView {
                HomeView()
                    .tabItem {
                        Image(systemName: "house")
                        Text("Library")
                    }
                
                NavigationView {
                    UserProfileView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "person")
                    Text("Profile")
                }
            }
            .accentColor(.primary)
            .animation(nil, value: UUID())
            .onAppear {
                checkClipboardAndShowImage()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    checkClipboardAndShowImage()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                checkClipboardAndShowImage()
            }
            
            // 中央波纹动画覆盖层
            if showCenterPixelWave {
                PixelWaveAnimationView(centerPosition: CGPoint(
                    x: UIScreen.main.bounds.width / 2,
                    y: UIScreen.main.bounds.height / 2
                ))
                .ignoresSafeArea()
            }
            
            // 图片显示覆盖层（只有旧图片会显示）
            if showLatestImage, let image = latestImage {
                ImageWithBorderView(image: image, showLatestImage: $showLatestImage)
                    .padding(.top, 100)
            }
            
            // 像素波纹动画覆盖层
            if showPixelWave {
                PixelWaveAnimationView()
                    .ignoresSafeArea()
                    .onAppear {
                        // 1秒后隐藏动画并显示Toast
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showPixelWave = false
                            }
                            
                            // 动画结束后显示Toast
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    showToast = true
                                }
                                
                                // 2秒后自动隐藏Toast
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        showToast = false
                                    }
                                }
                            }
                        }
                    }
            }
            
            // 自定义Toast覆盖层
            CustomToastView(message: "云端解析中", isShowing: $showToast)
                .opacity(showToast ? 1 : 0)
                .allowsHitTesting(showToast)
        }
    }
    
    private func checkClipboardAndShowImage() {
        let pasteboard = UIPasteboard.general
        
        if let clipboardString = pasteboard.string,
           clipboardString == "D3lib_addpic" {
            
            pasteboard.string = ""
            
            requestPhotoLibraryPermission { granted in
                if granted {
                    fetchLatestPhoto()
                }
            }
        }
    }
    
    private func requestPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    private func fetchLatestPhoto() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let latestAsset = fetchResult.firstObject else { return }
        
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        
        imageManager.requestImage(
            for: latestAsset,
            targetSize: CGSize(width: 1000, height: 1000),
            contentMode: .aspectFit,
            options: requestOptions
        ) { image, _ in
            DispatchQueue.main.async {
                if let image = image {
                    // 检查图片是否在5秒内创建
                    let now = Date()
                    let fiveSecondsAgo = now.addingTimeInterval(-5)
                    
                    if let creationDate = latestAsset.creationDate,
                       creationDate > fiveSecondsAgo {
                        // 图片是在5秒内创建的，播放像素波纹动画
                        withAnimation(.easeIn(duration: 0.2)) {
                            self.showPixelWave = true
                        }
                    } else {
                        // 图片不是最近创建的，显示较小图片并播放中央波纹动画
                        self.latestImage = image
                        
                        // 图片和波纹动画同时淡入
                        withAnimation(.easeIn(duration: 0.2)) {
                            self.showLatestImage = true
                            self.showCenterPixelWave = true
                        }
                        
                        // 0.8秒后开始飞出动画，但不立即隐藏view
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            // 先触发飞出动画，但保持showLatestImage为true
                            // 动画会在ImageWithBorderView内部处理
                        }
                        
                        // 1.2秒后才真正隐藏图片（给飞出动画0.4秒时间）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            self.showLatestImage = false
                        }
                        
                        // 1.5秒后波纹动画消失和显示Toast
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                self.showCenterPixelWave = false
                            }
                            
                            // 同时显示Toast
                            withAnimation(.easeInOut(duration: 0.4)) {
                                self.showToast = true
                            }
                            
                            // 2秒后自动隐藏Toast
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    self.showToast = false
                                }
                            }
                            
                            // 清理图片（在飞出动画完成后）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                self.latestImage = nil
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
