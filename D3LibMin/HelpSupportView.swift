//
//  HelpSupportView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/27.
//

import SwiftUI

struct HelpSupportView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""
    @State private var selectedCategory: HelpCategory = .gettingStarted
    @State private var showingContactSupport = false
    
    enum HelpCategory: String, CaseIterable {
        case gettingStarted = "Getting Started"
        case features = "Features"
        case troubleshooting = "Troubleshooting"
        case devices = "Devices"
        case account = "Account"
        
        var icon: String {
            switch self {
            case .gettingStarted: return "play.circle.fill"
            case .features: return "star.circle.fill"
            case .troubleshooting: return "wrench.and.screwdriver.fill"
            case .devices: return "iphone"
            case .account: return "person.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .gettingStarted: return .primary
            case .features: return .green
            case .troubleshooting: return .orange
            case .devices: return .purple
            case .account: return .red
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
                
                Text("Help & Support")
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
                    // Search
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How can we help?")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                            
                            TextField("Search for help...", text: $searchText)
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
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    
                    // Categories
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Help Categories")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            ForEach(HelpCategory.allCases, id: \.self) { category in
                                HelpCategoryCard(
                                    category: category,
                                    isSelected: selectedCategory == category,
                                    action: {
                                        selectedCategory = category
                                    }
                                )
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    
                    // Quick Actions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Actions")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            QuickActionRow(
                                title: "Contact Support",
                                subtitle: "Get help from our support team",
                                icon: "message.circle.fill",
                                color: .primary
                            ) {
                                showingContactSupport = true
                            }
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            QuickActionRow(
                                title: "Report a Bug",
                                subtitle: "Help us improve by reporting issues",
                                icon: "exclamationmark.triangle.fill",
                                color: .orange
                            ) {
                                // Report bug action
                            }
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            QuickActionRow(
                                title: "Feature Request",
                                subtitle: "Suggest new features",
                                icon: "lightbulb.fill",
                                color: .yellow
                            ) {
                                // Feature request action
                            }
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            QuickActionRow(
                                title: "User Guide",
                                subtitle: "Read the complete user guide",
                                icon: "book.fill",
                                color: .green
                            ) {
                                // User guide action
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // FAQ Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Frequently Asked Questions")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            ForEach(getFAQs(for: selectedCategory)) { faq in
                                FAQRow(faq: faq)
                                
                                if faq.id != getFAQs(for: selectedCategory).last?.id {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // App Information
                    VStack(alignment: .leading, spacing: 16) {
                        Text("App Information")
                            .font(.spaceGroteskMedium(size: 16))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 0) {
                            AppInfoRow(title: "Version", value: "1.0.0")
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            AppInfoRow(title: "Build", value: "2025.7.27")
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            AppInfoRow(title: "Last Updated", value: "July 27, 2025")
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
        .sheet(isPresented: $showingContactSupport) {
            ContactSupportView()
        }
    }
    
    private func getFAQs(for category: HelpCategory) -> [FAQItem] {
        switch category {
        case .gettingStarted:
            return [
                FAQItem(question: "How do I add my first information block?", answer: "Tap the + button on the home screen and select the type of information you want to add."),
                FAQItem(question: "What are the different information types?", answer: "There are 5 types: Numbers, Profiles, Files, Phrases, and Others. Each type has its own icon and organization."),
                FAQItem(question: "How do I edit information?", answer: "Tap on any information card to open the detail view, then tap the edit button to make changes.")
            ]
        case .features:
            return [
                FAQItem(question: "Can I sync data across devices?", answer: "Yes, enable sync in Privacy settings to keep your data synchronized across all your devices."),
                FAQItem(question: "How do I search for information?", answer: "Use the search bar at the top of the home screen to find specific information quickly."),
                FAQItem(question: "Can I export my data?", answer: "Yes, go to Privacy settings and tap 'Export Data' to download all your information.")
            ]
        case .troubleshooting:
            return [
                FAQItem(question: "The app is not responding", answer: "Try force-closing the app and reopening it. If the problem persists, restart your device."),
                FAQItem(question: "I can't add new information", answer: "Check your internet connection and ensure you have sufficient storage space on your device."),
                FAQItem(question: "Data is not syncing", answer: "Verify your internet connection and check the sync settings in Privacy preferences.")
            ]
        case .devices:
            return [
                FAQItem(question: "How do I connect AR glasses?", answer: "Go to Profile > Connected Devices > Add Device and follow the pairing instructions."),
                FAQItem(question: "My device won't connect", answer: "Ensure Bluetooth is enabled and the device is in pairing mode. Try restarting both devices."),
                FAQItem(question: "Can I use multiple devices?", answer: "Yes, you can connect multiple devices and switch between them in the device settings.")
            ]
        case .account:
            return [
                FAQItem(question: "How do I change my username?", answer: "Go to Profile settings and tap on your username to edit it."),
                FAQItem(question: "I forgot my password", answer: "Use the 'Forgot Password' option on the login screen to reset your password."),
                FAQItem(question: "How do I delete my account?", answer: "Go to Privacy settings and tap 'Delete All Data' to permanently remove your account.")
            ]
        }
    }
}

struct HelpCategoryCard: View {
    let category: HelpSupportView.HelpCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : category.color)
                
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? category.color : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QuickActionRow: View {
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

struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct FAQRow: View {
    let faq: FAQItem
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .frame(width: 20)
                    
                    Text(faq.question)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                HStack {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .frame(width: 20)
                    
                    Text(faq.answer)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.leading, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct AppInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ContactSupportView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var subject = ""
    @State private var message = ""
    @State private var selectedPriority: Priority = .medium
    @State private var includeSystemInfo = true
    
    enum Priority: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case urgent = "Urgent"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .primary
            case .high: return .orange
            case .urgent: return .red
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Priority Selection
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Priority")
                                .font(.spaceGroteskMedium(size: 16))
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                ForEach(Priority.allCases, id: \.self) { priority in
                                    PriorityButton(
                                        priority: priority,
                                        isSelected: selectedPriority == priority,
                                        action: {
                                            selectedPriority = priority
                                        }
                                    )
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                        
                        // Subject
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Subject")
                                .font(.spaceGroteskMedium(size: 16))
                                .foregroundColor(.primary)
                            
                            TextField("Brief description of your issue", text: $subject)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                        
                        // Message
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Message")
                                .font(.spaceGroteskMedium(size: 16))
                                .foregroundColor(.primary)
                            
                            TextEditor(text: $message)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                        
                        // Options
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Options")
                                .font(.spaceGroteskMedium(size: 16))
                                .foregroundColor(.primary)
                            
                            Toggle("Include system information", isOn: $includeSystemInfo)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                        
                        // Submit Button
                        Button(action: {
                            submitSupportRequest()
                        }) {
                            Text("Send Message")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(subject.isEmpty || message.isEmpty ? Color.gray : Color.primary)
                                .cornerRadius(8)
                        }
                        .disabled(subject.isEmpty || message.isEmpty)
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Contact Support")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func submitSupportRequest() {
        // Handle support request submission
        print("Support request submitted: \(subject)")
        presentationMode.wrappedValue.dismiss()
    }
}

struct PriorityButton: View {
    let priority: ContactSupportView.Priority
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(priority.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : priority.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? priority.color : priority.color.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    HelpSupportView()
} 