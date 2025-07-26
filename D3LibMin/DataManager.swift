//
//  DataManager.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import Foundation
import Combine

class DataManager: ObservableObject {
    @Published var infoBlocks: [InfoBlock] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadInitialData()
    }
    
    // MARK: - Data Loading
    
    private func loadInitialData() {
        // 加载初始示例数据
        infoBlocks = [
            InfoBlock(
                title: "Room 6836",
                subtitle: "Meikai Hotel",
                type: .numbers,
                needs: [
                    UsageNeed(name: "Hotel Check-in", description: "For hotel registration"),
                    UsageNeed(name: "Room Access", description: "For room key card")
                ],
                infos: [
                    InfoContent(name: "Room Number", content: "6836"),
                    InfoContent(name: "Hotel Name", content: "Meikai Hotel"),
                    InfoContent(name: "Check-in Date", content: "2025-01-15"),
                    InfoContent(name: "Check-out Date", content: "2025-01-18")
                ]
            ),
            InfoBlock(
                title: "605-1-3064",
                subtitle: "Package pick up",
                type: .numbers,
                needs: [
                    UsageNeed(name: "Package Pickup", description: "For collecting packages")
                ],
                infos: [
                    InfoContent(name: "Pickup Code", content: "605-1-3064"),
                    InfoContent(name: "Location", content: "Main Post Office"),
                    InfoContent(name: "Expiry Date", content: "2025-01-20")
                ]
            ),
            InfoBlock(
                title: "Moonlight",
                subtitle: "Piano scores",
                type: .files,
                needs: [
                    UsageNeed(name: "Music Practice", description: "For piano practice sessions")
                ],
                infos: [
                    InfoContent(name: "File Name", content: "Moonlight_Sonata.pdf", type: .file),
                    InfoContent(name: "Composer", content: "Ludwig van Beethoven"),
                    InfoContent(name: "Difficulty", content: "Advanced"),
                    InfoContent(name: "File Size", content: "2.4 MB")
                ]
            ),
            InfoBlock(
                title: "Lanzhi Jiang",
                subtitle: "New contact",
                type: .profiles,
                needs: [
                    UsageNeed(name: "Contact Management", description: "For contact information"),
                    UsageNeed(name: "Communication", description: "For messaging and calls")
                ],
                infos: [
                    InfoContent(name: "Full Name", content: "Lanzhi Jiang"),
                    InfoContent(name: "Phone", content: "+86 138-1234-5678"),
                    InfoContent(name: "Email", content: "lanzhi.jiang@example.com"),
                    InfoContent(name: "Company", content: "Tech Solutions Inc."),
                    InfoContent(name: "Position", content: "Senior Developer")
                ]
            ),
            InfoBlock(
                title: "InkCre README.md",
                subtitle: "API definitions",
                type: .files,
                needs: [
                    UsageNeed(name: "Development", description: "For API development reference")
                ],
                infos: [
                    InfoContent(name: "File Name", content: "README.md", type: .file),
                    InfoContent(name: "Project", content: "InkCre"),
                    InfoContent(name: "Type", content: "API Documentation"),
                    InfoContent(name: "Last Updated", content: "2025-01-10")
                ]
            ),
            InfoBlock(
                title: "Meeting Notes",
                subtitle: "Weekly team sync",
                type: .phrases,
                needs: [
                    UsageNeed(name: "Team Communication", description: "For team meetings"),
                    UsageNeed(name: "Project Management", description: "For project tracking")
                ],
                infos: [
                    InfoContent(name: "Meeting Type", content: "Weekly Team Sync"),
                    InfoContent(name: "Date", content: "2025-01-14"),
                    InfoContent(name: "Duration", content: "1 hour"),
                    InfoContent(name: "Key Points", content: "Project milestones, resource allocation, next steps"),
                    InfoContent(name: "Action Items", content: "Follow up on client feedback, prepare demo for next week")
                ]
            )
        ]
    }
    
    // MARK: - CRUD Operations
    
    func addInfoBlock(_ infoBlock: InfoBlock) {
        infoBlocks.append(infoBlock)
        // TODO: 调用API保存到服务器
        saveToAPI(infoBlock)
    }
    
    func updateInfoBlock(_ infoBlock: InfoBlock) {
        if let index = infoBlocks.firstIndex(where: { $0.id == infoBlock.id }) {
            infoBlocks[index] = infoBlock
            // TODO: 调用API更新到服务器
            updateInAPI(infoBlock)
        }
    }
    
    func deleteInfoBlock(_ infoBlock: InfoBlock) {
        infoBlocks.removeAll { $0.id == infoBlock.id }
        // TODO: 调用API从服务器删除
        deleteFromAPI(infoBlock)
    }
    
    func getInfoBlock(by id: UUID) -> InfoBlock? {
        return infoBlocks.first { $0.id == id }
    }
    
    func getInfoBlocks(by type: InfoType) -> [InfoBlock] {
        return infoBlocks.filter { $0.type == type }
    }
    
    func getInfoBlocks(by need: String) -> [InfoBlock] {
        return infoBlocks.filter { infoBlock in
            infoBlock.needs.contains { $0.name.localizedCaseInsensitiveContains(need) }
        }
    }
    
    // MARK: - API Integration (Future Implementation)
    
    private func saveToAPI(_ infoBlock: InfoBlock) {
        // TODO: 实现API保存逻辑
        print("Saving info block to API: \(infoBlock.title)")
    }
    
    private func updateInAPI(_ infoBlock: InfoBlock) {
        // TODO: 实现API更新逻辑
        print("Updating info block in API: \(infoBlock.title)")
    }
    
    private func deleteFromAPI(_ infoBlock: InfoBlock) {
        // TODO: 实现API删除逻辑
        print("Deleting info block from API: \(infoBlock.title)")
    }
    
    func refreshFromAPI() {
        isLoading = true
        errorMessage = nil
        
        // TODO: 实现从API获取数据的逻辑
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isLoading = false
            // 模拟API调用完成
        }
    }
    
    // MARK: - Search and Filter
    
    func searchInfoBlocks(query: String) -> [InfoBlock] {
        guard !query.isEmpty else { return infoBlocks }
        
        return infoBlocks.filter { infoBlock in
            infoBlock.title.localizedCaseInsensitiveContains(query) ||
            infoBlock.subtitle.localizedCaseInsensitiveContains(query) ||
            infoBlock.infos.contains { info in
                info.name.localizedCaseInsensitiveContains(query) ||
                info.content.localizedCaseInsensitiveContains(query)
            } ||
            infoBlock.needs.contains { need in
                need.name.localizedCaseInsensitiveContains(query) ||
                (need.description?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
    }
    
    func getExpiredInfoBlocks() -> [InfoBlock] {
        let now = Date()
        return infoBlocks.filter { infoBlock in
            if let expiresAt = infoBlock.expiresAt {
                return expiresAt < now
            }
            return false
        }
    }
    
    func getExpiringSoonInfoBlocks(within days: Int = 7) -> [InfoBlock] {
        let now = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        
        return infoBlocks.filter { infoBlock in
            if let expiresAt = infoBlock.expiresAt {
                return expiresAt > now && expiresAt <= futureDate
            }
            return false
        }
    }
} 