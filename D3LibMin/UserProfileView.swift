//
//  UserProfileView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI

struct UserProfileView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var userProfile = UserProfile()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Image("Profile")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                    
                    Text("Profile")
                        .font(.system(size: 24, weight: .medium, design: .default))
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
            
            ScrollView {
                VStack(spacing: 30) {
                    // User Info Section
                    VStack(spacing: 16) {
                        // Avatar
                        Image(systemName: userProfile.avatar)
                            .font(.system(size: 60))
                            .foregroundColor(.primary)
                            .frame(width: 80, height: 80)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                        
                        // Name and Username
                        VStack(spacing: 4) {
                            Text(userProfile.name)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text(userProfile.username)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Memory Usage Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            
                            Text("Memory Usage")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(userProfile.memoryUsed, specifier: "%.1f") GB / \(userProfile.memoryTotal, specifier: "%.1f") GB")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        
                        // Dot Matrix Progress Bar
                        VStack(alignment: .leading, spacing: 8) {
                            DotMatrixProgressView(progress: userProfile.memoryUsagePercentage / 100)
                            
                            Text("\(Int(userProfile.memoryUsagePercentage))% of storage used")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    
                    // Connected Devices Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            
                            Text("Connected Devices")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        ForEach(userProfile.connectedDevices) { device in
                            DeviceRow(device: device)
                        }
                        
                        // Add Device Button
                        Button(action: {
                            // Add device action
                        }) {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("Add Device")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    
                    // App Settings Section
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            
                            Text("App Settings")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.bottom, 16)
                        
                        VStack(spacing: 16) {
                            SettingsRow(title: "Notifications", hasChevron: true)
                            SettingsRow(title: "Privacy", hasChevron: true)
                            SettingsRow(title: "Help & Support", hasChevron: true)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
    }
}

struct DeviceRow: View {
    let device: ConnectedDevice
    
    private func formatLastConnected(_ date: Date?) -> String {
        guard let date = date else { return "Never" }
        
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today,' h:mm a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday,' h:mm a"
        } else {
            let daysDiff = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            if daysDiff <= 7 {
                return "\(daysDiff) days ago"
            } else {
                formatter.dateFormat = "MMM d, h:mm a"
            }
        }
        
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            Image(systemName: device.systemImage)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Last connected: \(formatLastConnected(device.lastConnected))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(device.isConnected ? Color.green : Color(.systemGray4))
                    .frame(width: 8, height: 8)
                
                Text(device.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(device.isConnected ? .green : .secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SettingsRow: View {
    let title: String
    let hasChevron: Bool
    
    var body: some View {
        Button(action: {
            // Settings action
        }) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if hasChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DotMatrixProgressView: View {
    let progress: Double
    let dotsPerRow = 25
    let totalRows = 4
    
    var totalDots: Int {
        return dotsPerRow * totalRows
    }
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(dotsPerRow - 1)
            let dotSize = (availableWidth - totalSpacing) / CGFloat(dotsPerRow)
            
            VStack(spacing: spacing) {
                ForEach(0..<totalRows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<dotsPerRow, id: \.self) { col in
                            let dotIndex = row * dotsPerRow + col
                            let shouldFill = Double(dotIndex) < (progress * Double(totalDots))
                            
                            Rectangle()
                                .fill(shouldFill ? Color.primary : Color(.systemGray5))
                                .frame(width: dotSize, height: dotSize)
                                .cornerRadius(1)
                        }
                    }
                }
            }
        }
        .aspectRatio(CGFloat(dotsPerRow) / CGFloat(totalRows), contentMode: .fit)
    }
}

#Preview {
    UserProfileView()
}