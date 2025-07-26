//
//  CustomToastView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI

struct CustomToastView: View {
    let message: String
    @Binding var isShowing: Bool
    
    var body: some View {
        ZStack {
            // 半透明背景 - 只使用透明度变化
            Color.black.opacity(isShowing ? 0.3 : 0.0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isShowing = false
                    }
                }
            
            // Toast内容 - 使用透明度和轻微缩放
            VStack(spacing: 16) {
                // 云朵图标
                Image(systemName: "cloud.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.primary)
                
                // 文字
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
            .scaleEffect(isShowing ? 1.0 : 0.95)
            .opacity(isShowing ? 1.0 : 0.0)
        }
        .animation(.easeInOut(duration: 0.4), value: isShowing)
    }
}

#Preview {
    CustomToastView(message: "云端解析中", isShowing: .constant(true))
}