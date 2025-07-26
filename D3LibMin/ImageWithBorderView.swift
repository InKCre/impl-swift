//
//  ImageWithBorderView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI

struct ImageWithBorderView: View {
    let image: UIImage
    @Binding var showLatestImage: Bool
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var scale: CGFloat = 1
    
    private var maxWidth: CGFloat { UIScreen.main.bounds.width * 0.6 }
    private var maxHeight: CGFloat { UIScreen.main.bounds.height * 0.5 }
    
    private var imageAspectRatio: CGFloat { image.size.width / image.size.height }
    private var containerAspectRatio: CGFloat { maxWidth / maxHeight }
    
    private var actualSize: CGSize {
        if imageAspectRatio > containerAspectRatio {
            // 图片更宽，以宽度为准
            let width = maxWidth
            let height = maxWidth / imageAspectRatio
            return CGSize(width: width, height: height)
        } else {
            // 图片更高，以高度为准
            let height = maxHeight
            let width = maxHeight * imageAspectRatio
            return CGSize(width: width, height: height)
        }
    }
    
    var body: some View {
        VStack {
            ZStack {
                // 图片本体
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: actualSize.width, height: actualSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                // 边框 - 使用计算出的实际尺寸
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: actualSize.width, height: actualSize.height)
            }
            
            Spacer()
        }
        .offset(y: offsetY)
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            // 淡入动画
            opacity = 0
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 1
            }
            
            // 0.8秒后自动开始飞出动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.4)) {
                    offsetY = -400
                    opacity = 0
                    scale = 0.8
                }
            }
        }
    }
}

#Preview {
    ImageWithBorderView(
        image: UIImage(systemName: "photo") ?? UIImage(),
        showLatestImage: .constant(true)
    )
}