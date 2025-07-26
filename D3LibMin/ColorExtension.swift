//
//  ColorExtension.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/27.
//

import SwiftUI

extension Color {
    // 定义纯黑色作为primary color
    static let customPrimary = Color.black
    
    // 定义深灰色作为secondary color
    static let customSecondary = Color(red: 0.4, green: 0.4, blue: 0.4)
    
    // 定义浅灰色作为背景色
    static let customBackground = Color(red: 0.95, green: 0.95, blue: 0.95)
    
    // 定义白色作为卡片背景
    static let customCardBackground = Color.white
}

// 扩展Color以支持自定义primary color
extension Color {
    static var primary: Color {
        return .customPrimary
    }
} 