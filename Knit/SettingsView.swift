import SwiftUI

// Available accent themes
enum AppTheme: String, CaseIterable, Identifiable {
    case teal, blue, indigo, purple, pink, red, orange, yellow, green, mint
    var id: String { self.rawValue }
    
    // Map each theme to a display color
    var color: Color {
        switch self {
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return Color(red: 1.0, green: 0.70, blue: 0.76)
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        }
    }
}

// App-wide appearance settings
struct SettingsView: View {
    // Persist the selected app theme
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .teal
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Appearance")) {
                    // Theme picker
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))], spacing: 15) {
                        ForEach(AppTheme.allCases) { theme in
                            Circle()
                                .fill(theme.color)
                                .frame(width: 45, height: 45)
                                .overlay(
                                    // Mark the current theme
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                        .opacity(selectedTheme == theme ? 1 : 0)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        selectedTheme = theme
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 10)
                }
                
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// Preview the settings sheet
#Preview {
    SettingsView()
}
