//
//  PrivacyView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/27.
//

import SwiftUI

struct PrivacyView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var privacySettings = PrivacySettings()
    @State private var showingDataExport = false
    @State private var showingDeleteAccount = false
    
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
                
                Text("Privacy")
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
                    // Data Collection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Data Collection")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            PrivacyToggleRow(
                                title: "Analytics",
                                subtitle: "Help improve the app by sharing usage data",
                                icon: "chart.bar.fill",
                                isOn: $privacySettings.analytics
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyToggleRow(
                                title: "Crash Reports",
                                subtitle: "Send crash reports to help fix issues",
                                icon: "exclamationmark.triangle.fill",
                                isOn: $privacySettings.crashReports
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyToggleRow(
                                title: "Device Information",
                                subtitle: "Share device type and OS version",
                                icon: "iphone",
                                isOn: $privacySettings.deviceInformation
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Data Sharing
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Data Sharing")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            PrivacyToggleRow(
                                title: "Sync Across Devices",
                                subtitle: "Keep your data synchronized",
                                icon: "icloud.fill",
                                isOn: $privacySettings.syncAcrossDevices
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyToggleRow(
                                title: "Backup to Cloud",
                                subtitle: "Automatically backup your data",
                                icon: "externaldrive.fill",
                                isOn: $privacySettings.backupToCloud
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyToggleRow(
                                title: "Share Usage Data",
                                subtitle: "Share anonymous usage statistics",
                                icon: "chart.pie.fill",
                                isOn: $privacySettings.shareUsageData
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Security
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Security")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            PrivacyToggleRow(
                                title: "Biometric Authentication",
                                subtitle: "Use Face ID or Touch ID to unlock",
                                icon: "faceid",
                                isOn: $privacySettings.biometricAuthentication
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyToggleRow(
                                title: "Auto-Lock",
                                subtitle: "Lock app when not in use",
                                icon: "lock.fill",
                                isOn: $privacySettings.autoLock
                            )
                            
                            if privacySettings.autoLock {
                                Divider()
                                    .padding(.leading, 44)
                                
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Auto-Lock Timeout")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)
                                        
                                        Text("\(privacySettings.autoLockTimeout) minutes")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        // Edit timeout
                                    }) {
                                        Text("Edit")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyToggleRow(
                                title: "Encrypt Local Data",
                                subtitle: "Encrypt data stored on your device",
                                icon: "lock.shield.fill",
                                isOn: $privacySettings.encryptLocalData
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Data Management
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Data Management")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 12) {
                            DataManagementRow(
                                title: "Export Data",
                                subtitle: "Download all your data",
                                icon: "square.and.arrow.up.fill",
                                color: .primary
                            ) {
                                showingDataExport = true
                            }
                            
                            DataManagementRow(
                                title: "Clear Cache",
                                subtitle: "Free up storage space",
                                icon: "trash.fill",
                                color: .orange
                            ) {
                                // Clear cache action
                            }
                            
                            DataManagementRow(
                                title: "Delete All Data",
                                subtitle: "Permanently delete all your data",
                                icon: "trash.circle.fill",
                                color: .red
                            ) {
                                showingDeleteAccount = true
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Privacy Policy
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Legal")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            PrivacyLinkRow(
                                title: "Privacy Policy",
                                subtitle: "Read our privacy policy",
                                icon: "doc.text.fill"
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyLinkRow(
                                title: "Terms of Service",
                                subtitle: "Read our terms of service",
                                icon: "doc.plaintext.fill"
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            PrivacyLinkRow(
                                title: "Data Processing",
                                subtitle: "Learn how we process your data",
                                icon: "gear.circle.fill"
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .sheet(isPresented: $showingDataExport) {
            DataExportView()
        }
        .alert("Delete All Data", isPresented: $showingDeleteAccount) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                // Delete account action
            }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
    }
}

struct PrivacyToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .primary))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct DataManagementRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PrivacyLinkRow: View {
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        Button(action: {
            // Open privacy policy
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DataExportView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var exportProgress = 0.0
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.primary)
                
                Text("Export Your Data")
                    .font(.spaceGroteskMedium(size: 24))
                    .foregroundColor(.primary)
                
                Text("This will create a file containing all your information blocks, settings, and preferences.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                if isExporting {
                    VStack(spacing: 16) {
                        ProgressView(value: exportProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .primary))
                        
                        Text("\(Int(exportProgress * 100))% Complete")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                }
                
                Button(action: {
                    startExport()
                }) {
                    Text(isExporting ? "Exporting..." : "Export Data")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isExporting ? Color.gray : Color.primary)
                        .cornerRadius(8)
                }
                .disabled(isExporting)
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func startExport() {
        isExporting = true
        exportProgress = 0.0
        
        // Simulate export progress
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            exportProgress += 0.01
            if exportProgress >= 1.0 {
                timer.invalidate()
                isExporting = false
                // Handle export completion
            }
        }
    }
}

struct PrivacySettings {
    var analytics = true
    var crashReports = true
    var deviceInformation = true
    var syncAcrossDevices = true
    var backupToCloud = true
    var shareUsageData = false
    var biometricAuthentication = true
    var autoLock = true
    var autoLockTimeout = 5
    var encryptLocalData = true
}

#Preview {
    PrivacyView()
} 