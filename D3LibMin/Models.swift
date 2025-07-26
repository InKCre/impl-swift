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
    case others = "Others"
    
    var systemImage: String {
        switch self {
        case .numbers: return "number.circle"
        case .profiles: return "person.circle"
        case .files: return "doc.circle"
        case .phrases: return "quote.bubble"
        case .others: return "ellipsis.circle"
        }
    }
}

// 内容类型枚举
enum ContentType: String, CaseIterable, Codable {
    case text = "text"
    case file = "file"
}

// 信息内容项
struct InfoContent: Identifiable, Codable {
    let id = UUID()
    var name: String
    var content: String
    var type: ContentType
    
    init(name: String, content: String, type: ContentType = .text) {
        self.name = name
        self.content = content
        self.type = type
    }
}

// 使用场景
struct UsageNeed: Identifiable, Codable {
    let id = UUID()
    var name: String
    var description: String?
    
    init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

// 信息块模型 - 主要数据结构
struct InfoBlock: Identifiable, Codable {
    let id = UUID()
    var title: String
    var subtitle: String
    var type: InfoType
    var createdAt: Date
    var expiresAt: Date?
    var needs: [UsageNeed]
    var infos: [InfoContent]
    
    init(title: String, subtitle: String, type: InfoType, createdAt: Date = Date(), expiresAt: Date? = nil, needs: [UsageNeed] = [], infos: [InfoContent] = []) {
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.needs = needs
        self.infos = infos
    }
}

// 兼容性模型 - 用于过渡期间
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
    
    // 从InfoBlock创建InfoItem的便利构造器
    init(from infoBlock: InfoBlock) {
        self.title = infoBlock.title
        self.subtitle = infoBlock.subtitle
        self.type = infoBlock.type
        self.createdAt = infoBlock.createdAt
        // 将InfoContent转换为details字符串数组
        self.details = infoBlock.infos.map { "\($0.name): \($0.content)" }
    }
    
    // 转换为InfoBlock的方法
    func toInfoBlock() -> InfoBlock {
        let infos = details.map { detail in
            let components = detail.split(separator: ":", maxSplits: 1).map(String.init)
            if components.count == 2 {
                return InfoContent(name: components[0].trimmingCharacters(in: .whitespaces), 
                                 content: components[1].trimmingCharacters(in: .whitespaces))
            } else {
                return InfoContent(name: "Info", content: detail)
            }
        }
        
        return InfoBlock(
            title: title,
            subtitle: subtitle,
            type: type,
            createdAt: createdAt,
            needs: [],
            infos: infos
        )
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