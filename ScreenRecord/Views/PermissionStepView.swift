//
//  PermissionStepView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/26/25.
//

import SwiftUI

// Step view for permission step
struct PermissionStepView<Content: View>: View {
    let number: Int
    let isActive: Bool
    let title: String
    let description: String
    let content: Content
    
    init(number: Int, isActive: Bool, title: String, description: String, @ViewBuilder content: () -> Content) {
        self.number = number
        self.isActive = isActive
        self.title = title
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                StepNumberView(number: number, isActive: isActive)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(isActive ? .primary : .gray)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(isActive ? .secondary : .gray.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            if isActive {
                content
                    .padding(.leading, 50)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.05) : Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
}


struct StepNumberView: View {
    let number: Int
    let isActive: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 36, height: 36)
            
            Text("\(number)")
                .font(.headline)
                .foregroundColor(isActive ? .white : .gray)
        }
    }
}
