//
//  AddDeviceView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/27.
//

import SwiftUI

struct AddDeviceView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""
    @State private var selectedDeviceType: DeviceType = .ar
    @State private var isScanning = false
    @State private var discoveredDevices: [DiscoveredDevice] = []
    
    enum DeviceType: String, CaseIterable {
        case ar = "AR Glasses"
        case vr = "VR Headset"
        case mobile = "Mobile Device"
        case desktop = "Desktop Computer"
        
        var icon: String {
            switch self {
            case .ar: return "eyeglasses"
            case .vr: return "viewfinder"
            case .mobile: return "iphone"
            case .desktop: return "desktopcomputer"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("Add Device")
                    .font(.spaceGroteskMedium(size: 20))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Placeholder for balance
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Device Type Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Device Type")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            ForEach(DeviceType.allCases, id: \.self) { deviceType in
                                DeviceTypeCard(
                                    type: deviceType,
                                    isSelected: selectedDeviceType == deviceType,
                                    action: {
                                        selectedDeviceType = deviceType
                                    }
                                )
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    
                    // Search Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Search for Devices")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                            
                            TextField("Search for devices...", text: $searchText)
                                .font(.system(size: 16))
                            
                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        // Scan Button
                        Button(action: {
                            startScanning()
                        }) {
                            HStack {
                                if isScanning {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                
                                Text(isScanning ? "Scanning..." : "Scan for Devices")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isScanning ? Color.gray : Color.primary)
                            .cornerRadius(8)
                        }
                        .disabled(isScanning)
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    
                    // Discovered Devices
                    if !discoveredDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Available Devices")
                                .font(.spaceGroteskMedium(size: 16))
                                .foregroundColor(.primary)
                            
                            ForEach(discoveredDevices) { device in
                                DiscoveredDeviceRow(device: device) {
                                    connectToDevice(device)
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Manual Connection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Manual Connection")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        Text("If your device doesn't appear in the list above, you can manually enter the device information or use a QR code.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                // Manual entry action
                            }) {
                                HStack {
                                    Image(systemName: "keyboard")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Manual Entry")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            
                            Button(action: {
                                // QR code action
                            }) {
                                HStack {
                                    Image(systemName: "qrcode")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("QR Code")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
    }
    
    private func startScanning() {
        isScanning = true
        discoveredDevices = []
        
        // Simulate device discovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            discoveredDevices = [
                DiscoveredDevice(name: "Rokid AR Pro", type: .ar, signalStrength: 0.9, isPaired: false),
                DiscoveredDevice(name: "Even Realities G1", type: .ar, signalStrength: 0.7, isPaired: false),
                DiscoveredDevice(name: "Meta Quest 3", type: .vr, signalStrength: 0.8, isPaired: false),
                DiscoveredDevice(name: "iPhone 15 Pro", type: .mobile, signalStrength: 0.6, isPaired: true)
            ]
            isScanning = false
        }
    }
    
    private func connectToDevice(_ device: DiscoveredDevice) {
        // Handle device connection
        print("Connecting to \(device.name)")
    }
}

struct DeviceTypeCard: View {
    let type: AddDeviceView.DeviceType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(type.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
                                        .background(isSelected ? Color.primary : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let name: String
    let type: AddDeviceView.DeviceType
    let signalStrength: Double
    let isPaired: Bool
}

struct DiscoveredDeviceRow: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: device.type.icon)
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(device.type.rawValue)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    if device.isPaired {
                        Text("Paired")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Signal strength indicator
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(index < Int(device.signalStrength * 4) ? Color.green : Color(.systemGray4))
                            .frame(width: 3, height: CGFloat(index + 1) * 3)
                            .cornerRadius(1.5)
                    }
                }
                
                Button(action: onConnect) {
                    Text(device.isPaired ? "Reconnect" : "Connect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                                                    .background(Color.primary)
                        .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    AddDeviceView()
} 