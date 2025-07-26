//
//  PixelWaveAnimationView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI

struct PixelWaveAnimationView: View {
    @State private var waveRadius: CGFloat = 30
    @State private var isAnimating = false
    @State private var animationTimer: Timer?
    
    let squareSize: CGFloat = 20
    let originX: CGFloat
    let originY: CGFloat
    let maxRadius: CGFloat
    
    init(centerPosition: CGPoint? = nil) {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        let originX: CGFloat
        let originY: CGFloat
        
        if let centerPosition = centerPosition {
            // 使用自定义位置
            originX = centerPosition.x
            originY = centerPosition.y
        } else {
            // 默认位置：距左边缘约2.5个单位，距下边缘约4个单位
            originX = 2.5 * squareSize
            originY = screenHeight - 4 * squareSize
        }
        
        self.originX = originX
        self.originY = originY
        
        // 计算到屏幕边缘的最大距离
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: screenWidth, y: 0),
            CGPoint(x: 0, y: screenHeight),
            CGPoint(x: screenWidth, y: screenHeight)
        ]
        
        let distances = corners.map { corner in
            sqrt(pow(corner.x - originX, 2) + pow(corner.y - originY, 2))
        }
        
        // 增加20%的安全边距，确保波纹完全覆盖屏幕
        self.maxRadius = (distances.max() ?? 1000) * 1.2
        
        print("波纹起始点: (\(originX), \(originY))")
        print("最大半径: \(self.maxRadius)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let cols = Int(ceil(screenWidth / squareSize))
            let rows = Int(ceil(screenHeight / squareSize))
            
            ZStack {
                Color.clear
                    .ignoresSafeArea()
                
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<cols, id: \.self) { col in
                        let centerX = CGFloat(col) * squareSize + squareSize/2
                        let centerY = CGFloat(row) * squareSize + squareSize/2
                        let distance = sqrt(pow(centerX - originX, 2) + pow(centerY - originY, 2))
                        
                        let opacity = squareOpacity(for: distance)
                        
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: squareSize - 1, height: squareSize - 1)
                            .opacity(opacity)
                            .scaleEffect(squareScale(for: distance))
                            .position(x: centerX, y: centerY)
                    }
                }
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }
    
    private func squareOpacity(for distance: CGFloat) -> Double {
        let waveWidth: CGFloat = 100 // 波纹环的宽度（像素）
        let distanceFromWave = abs(distance - waveRadius)
        
        // 移除调试信息以减少控制台输出
        
        if distanceFromWave <= waveWidth/2 {
            // 在波纹环范围内
            let normalizedDistance = distanceFromWave / (waveWidth/2)
            let intensity = max(0.1, 1.0 - normalizedDistance) // 简化的线性衰减
            return intensity * 0.8
        }
        
        return 0
    }
    
    private func squareScale(for distance: CGFloat) -> Double {
        let waveWidth: CGFloat = 100
        let distanceFromWave = abs(distance - waveRadius)
        
        if distanceFromWave <= waveWidth/2 {
            let normalizedDistance = distanceFromWave / (waveWidth/2)
            let intensity = max(0.1, 1.0 - normalizedDistance)
            return 0.6 + intensity * 0.4
        }
        
        return 0.6
    }
    
    private func startAnimation() {
        isAnimating = true
        print("开始像素波纹动画，最大半径: \(maxRadius)")
        print("初始波纹半径: \(waveRadius)")
        
        let animationDuration: TimeInterval = 1.25
        let frameRate: TimeInterval = 1.0/60.0 // 60 FPS
        let totalFrames = Int(animationDuration / frameRate)
        let radiusIncrement = (maxRadius - 30) / CGFloat(totalFrames)
        
        var currentFrame = 0
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true) { timer in
            currentFrame += 1
            self.waveRadius = 30 + CGFloat(currentFrame) * radiusIncrement
            
            // 每30帧打印一次调试信息
            if currentFrame % 30 == 0 {
                print("动画进度: \(currentFrame)/\(totalFrames), 当前半径: \(self.waveRadius)")
            }
            
            if currentFrame >= totalFrames {
                timer.invalidate()
                self.animationTimer = nil
                self.isAnimating = false
                print("像素波纹动画结束，最终半径: \(self.waveRadius)")
            }
        }
    }
}

#Preview {
    PixelWaveAnimationView()
        .background(Color.black)
}