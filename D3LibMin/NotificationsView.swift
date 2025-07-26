//
//  NotificationsView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/27.
//

import SwiftUI

struct NotificationsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var notificationSettings = NotificationSettings()
    
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
                
                Text("Notifications")
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
                    // General Notifications
                    VStack(alignment: .leading, spacing: 16) {
                        Text("General")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            NotificationToggleRow(
                                title: "Push Notifications",
                                subtitle: "Receive notifications on your device",
                                icon: "bell.fill",
                                isOn: $notificationSettings.pushNotifications
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            NotificationToggleRow(
                                title: "Sound",
                                subtitle: "Play sound for notifications",
                                icon: "speaker.wave.2.fill",
                                isOn: $notificationSettings.sound
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            NotificationToggleRow(
                                title: "Vibration",
                                subtitle: "Vibrate for notifications",
                                icon: "iphone.radiowaves.left.and.right",
                                isOn: $notificationSettings.vibration
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // App Notifications
                    VStack(alignment: .leading, spacing: 16) {
                        Text("App Notifications")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            NotificationToggleRow(
                                title: "New Information",
                                subtitle: "When new information is added",
                                icon: "plus.circle.fill",
                                isOn: $notificationSettings.newInformation
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            NotificationToggleRow(
                                title: "Information Updates",
                                subtitle: "When existing information is updated",
                                icon: "arrow.clockwise.circle.fill",
                                isOn: $notificationSettings.informationUpdates
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            NotificationToggleRow(
                                title: "Expiration Reminders",
                                subtitle: "Before information expires",
                                icon: "clock.fill",
                                isOn: $notificationSettings.expirationReminders
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            NotificationToggleRow(
                                title: "Device Connection",
                                subtitle: "When devices connect or disconnect",
                                icon: "antenna.radiowaves.left.and.right",
                                isOn: $notificationSettings.deviceConnection
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Notification Schedule
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Notification Schedule")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            NotificationToggleRow(
                                title: "Quiet Hours",
                                subtitle: "Silence notifications during quiet hours",
                                icon: "moon.fill",
                                isOn: $notificationSettings.quietHours
                            )
                            
                            if notificationSettings.quietHours {
                                VStack(spacing: 12) {
                                    Divider()
                                        .padding(.leading, 44)
                                    
                                    HStack {
                                        Image(systemName: "clock.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.secondary)
                                            .frame(width: 20)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Quiet Hours")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.primary)
                                            
                                            Text("\(notificationSettings.quietStartTime) - \(notificationSettings.quietEndTime)")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            // Edit quiet hours
                                        }) {
                                                                                    Text("Edit")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Notification History
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Recent Notifications")
                                .font(.spaceGroteskMedium(size: 16))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                // View all notifications
                            }) {
                                Text("View All")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        VStack(spacing: 0) {
                            ForEach(notificationSettings.recentNotifications) { notification in
                                NotificationHistoryRow(notification: notification)
                                
                                if notification.id != notificationSettings.recentNotifications.last?.id {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
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
    }
}

struct NotificationToggleRow: View {
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

struct NotificationHistoryRow: View {
    let notification: NotificationItem
    
    var body: some View {
        HStack {
            Image(systemName: notification.icon)
                .font(.system(size: 16))
                .foregroundColor(notification.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(notification.message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(notification.timeAgo)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !notification.isRead {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct NotificationItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let icon: String
    let color: Color
    let timeAgo: String
    let isRead: Bool
}

struct NotificationSettings {
    var pushNotifications = true
    var sound = true
    var vibration = true
    var newInformation = true
    var informationUpdates = false
    var expirationReminders = true
    var deviceConnection = true
    var quietHours = false
    var quietStartTime = "10:00 PM"
    var quietEndTime = "8:00 AM"
    
    var recentNotifications: [NotificationItem] = [
        NotificationItem(
            title: "New Information Added",
            message: "Room 6836 information has been added to your library",
            icon: "plus.circle.fill",
            color: .green,
            timeAgo: "2 minutes ago",
            isRead: false
        ),
        NotificationItem(
            title: "Device Connected",
            message: "Rokid AR Pro is now connected",
            icon: "antenna.radiowaves.left.and.right",
            color: .blue,
            timeAgo: "1 hour ago",
            isRead: true
        ),
        NotificationItem(
            title: "Information Updated",
            message: "605-1-3064 information has been updated",
            icon: "arrow.clockwise.circle.fill",
            color: .orange,
            timeAgo: "3 hours ago",
            isRead: true
        ),
        NotificationItem(
            title: "Expiration Reminder",
            message: "Package pick up information expires in 2 days",
            icon: "clock.fill",
            color: .red,
            timeAgo: "1 day ago",
            isRead: true
        )
    ]
}

#Preview {
    NotificationsView()
} 