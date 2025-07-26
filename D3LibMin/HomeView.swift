//
//  HomeView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI

struct HomeView: View {
    @State private var selectedFilter: InfoType? = nil
    @State private var showingAddOptions = false
    @State private var infoItems: [InfoItem] = [
        InfoItem(title: "605-1-3064", subtitle: "Package pick up", type: .numbers),
        InfoItem(title: "Moonlight", subtitle: "Piano scores", type: .files),
        InfoItem(title: "Lanzhi Jiang", subtitle: "New contact", type: .profiles),
        InfoItem(title: "InkCre README.md", subtitle: "API definitions", type: .files),
        InfoItem(title: "Meeting Notes", subtitle: "Weekly team sync", type: .phrases)
    ]
    
    var filteredItems: [InfoItem] {
        if let selectedFilter = selectedFilter {
            return infoItems.filter { $0.type == selectedFilter }
        }
        return infoItems
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Bottom layer: Main content
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        HStack(spacing: 12) {
                            Image("Library")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            
                            Text("Library")
                                .font(.system(size: 24, weight: .medium, design: .default))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            // TODO: Add refresh functionality
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    
                    // Filter Buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(InfoType.allCases, id: \.self) { type in
                                FilterButton(
                                    title: type.rawValue,
                                    icon: type.systemImage,
                                    isSelected: selectedFilter == type,
                                    action: {
                                        if selectedFilter == type {
                                            selectedFilter = nil
                                        } else {
                                            selectedFilter = type
                                        }
                                    }
                                )
                            }
                            
                            // Add custom filter button
                            FilterButton(
                                title: "",
                                icon: "plus",
                                isSelected: false,
                                isAddButton: true,
                                action: {
                                    // TODO: Handle add custom filter
                                }
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                    
                    // Info Cards List
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredItems) { item in
                                NavigationLink(destination: InfoDetailView(item: item)) {
                                    InfoCard(item: item)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                }
                .background(Color(.systemGroupedBackground))
                
                // Middle layer: Dark overlay when options are shown
                if showingAddOptions {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingAddOptions = false
                            }
                        }
                }
                
                // Top layer: Add Button and Options
                VStack {
                    Spacer()
                    
                    VStack {
                        // Add Options (shown when showingAddOptions is true)
                        if showingAddOptions {
                            HStack(spacing: 20) {
                                AddOptionButton(icon: "textformat", title: "Text") {
                                    // TODO: Handle text option
                                    showingAddOptions = false
                                }
                                
                                AddOptionButton(icon: "photo", title: "Image") {
                                    // TODO: Handle image option
                                    showingAddOptions = false
                                }
                                
                                AddOptionButton(icon: "doc", title: "File") {
                                    // TODO: Handle file option
                                    showingAddOptions = false
                                }
                            }
                            .padding(.bottom, 20)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        
                        // Main Add Button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingAddOptions.toggle()
                            }
                        }) {
                            Image(systemName: showingAddOptions ? "xmark" : "plus")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 68, height: 68)
                                .background(Color.primary)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                                .rotationEffect(.degrees(showingAddOptions ? 45 : 0))
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
        }
    }
}

struct AddOptionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }
}

struct FilterButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let isAddButton: Bool
    let action: () -> Void
    
    init(title: String, icon: String = "", isSelected: Bool, isAddButton: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isAddButton = isAddButton
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 80, height: 80)
                .background(
                    Circle()
                        .fill(isSelected ? Color.primary : Color.white)
                )
        }
        .disabled(isAddButton) // 暂时禁用添加按钮
        .opacity(isAddButton ? 0.6 : 1.0) // 添加按钮显示为半透明
    }
}

struct InfoCard: View {
    let item: InfoItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Text(item.subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white)
        .cornerRadius(8)
    }
}

#Preview {
    HomeView()
}