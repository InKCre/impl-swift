//
//  Models.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import Foundation

// 信息类型枚举
enum InfoType: String, CaseIterable, Codable {
    case numbers = "Numbers"
    case profiles = "Profiles"
    case files = "Files"
    case phrases = "Phrases"
    
    var systemImage: String {
        switch self {
        case .numbers: return "number.circle"
        case .profiles: return "person.circle"
        case .files: return "doc.circle"
        case .phrases: return "quote.bubble"
        }
    }
}

// 信息项模型
struct InfoItem: Identifiable, Codable {
    let id = UUID()
    var title: String
    var subtitle: String
    var type: InfoType
    var details: [String] = []
    var createdAt: Date = Date()
    
    init(title: String, subtitle: String, type: InfoType, details: [String] = []) {
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.details = details
    }
}

// 用户设备模型
struct ConnectedDevice: Identifiable {
    let id = UUID()
    var name: String
    var isConnected: Bool
    var lastConnected: Date?
    var systemImage: String
}

// 用户模型
struct UserProfile {
    var name: String = "Jackson Guo"
    var username: String = "@jacksonguo"
    var avatar: String = "person.crop.circle.fill"
    var memoryUsed: Double = 2.4
    var memoryTotal: Double = 5.0
    var connectedDevices: [ConnectedDevice] = [
        ConnectedDevice(name: "Rokid AR Pro", isConnected: true, lastConnected: Date(), systemImage: "eyeglasses"),
        ConnectedDevice(name: "Even Realities G1", isConnected: false, lastConnected: Calendar.current.date(byAdding: .day, value: -3, to: Date()), systemImage: "eyeglasses")
    ]
    
    var memoryUsagePercentage: Double {
        return (memoryUsed / memoryTotal) * 100
    }
}