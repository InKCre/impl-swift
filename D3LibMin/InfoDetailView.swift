//
//  InfoDetailView.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI

struct InfoDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var item: InfoItem
    @State private var showingDeleteAlert = false
    @State private var editingDetails: [String] = []
    @State private var newDetailText = ""
    @State private var isEditing = false
    @FocusState private var isTextFieldFocused: Bool
    
    private func addNewDetail() {
        if !newDetailText.isEmpty {
            editingDetails.append(newDetailText)
            newDetailText = ""
            // 重新聚焦到输入框，方便连续添加
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
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
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text(item.type.rawValue)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Menu button
                Menu {
                    Button(action: {
                        isEditing.toggle()
                        if isEditing {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 30)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Main Info Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: item.type.systemImage)
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if isEditing {
                                Button(action: {
                                    showingDeleteAlert = true
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Text(item.title)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(item.subtitle)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    
                    // Details Section
                    if !item.details.isEmpty || isEditing {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Essential Information")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                            ForEach(Array(editingDetails.enumerated()), id: \.offset) { index, detail in
                                DetailRow(
                                    text: detail,
                                    isEditing: isEditing,
                                    onDelete: {
                                        editingDetails.remove(at: index)
                                    },
                                    onMove: { from, to in
                                        editingDetails.move(fromOffsets: IndexSet([from]), toOffset: to)
                                    }
                                )
                            }
                            
                            if isEditing {
                                // Add new detail
                                HStack {
                                    TextField("Add new information...", text: $newDetailText)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .focused($isTextFieldFocused)
                                        .onSubmit {
                                            addNewDetail()
                                        }
                                    
                                    Button(action: {
                                        addNewDetail()
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    // Save/Cancel buttons when editing
                    if isEditing {
                        HStack(spacing: 12) {
                            Button(action: {
                                // Cancel editing
                                editingDetails = item.details
                                newDetailText = ""
                                isEditing = false
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                // Save changes
                                item.details = editingDetails
                                isEditing = false
                            }) {
                                Text("Save")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.primary)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Floating Add Button (when not editing)
            if !isEditing {
                HStack {
                    Spacer()
                    
                    Button(action: {
                        isEditing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isTextFieldFocused = true
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.primary)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .onAppear {
            editingDetails = item.details
        }
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this item? This action cannot be undone.")
        }
    }
}

struct DetailRow: View {
    let text: String
    let isEditing: Bool
    let onDelete: () -> Void
    let onMove: (Int, Int) -> Void
    
    var body: some View {
        HStack {
            if isEditing {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            HStack {
                if text.contains("@") {
                    // Email indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 8, height: 8)
                }
                
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
            }
        }
    }
}

#Preview {
    InfoDetailView(item: InfoItem(
        title: "605-1-3064",
        subtitle: "Package pick up",
        type: .numbers,
        details: ["Complete project proposal", "Schedule team meeting", "Review quarterly reports", "Email client updates"]
    ))
}