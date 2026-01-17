import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputKey: String = ""
    @State private var showShortcutsEditor = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("MacTorn")
                .font(.title2.bold())
            
            Text("Enter your Torn API Key")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // API Key input
            SecureField("API Key", text: $inputKey)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            Button("Save & Connect") {
                appState.apiKey = inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
                appState.refreshNow()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputKey.isEmpty)
            
            Link("Get API Key from Torn",
                 destination: URL(string: "https://www.torn.com/preferences.php#tab=api")!)
                .font(.caption)
            
            Divider()
                .padding(.vertical, 8)
            
            // Launch at Login
            Toggle(isOn: Binding(
                get: { appState.launchAtLogin.isEnabled },
                set: { _ in appState.launchAtLogin.toggle() }
            )) {
                Label("Launch at Login", systemImage: "power")
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            
            // Shortcuts Editor
            Button {
                showShortcutsEditor.toggle()
            } label: {
                Label("Edit Shortcuts", systemImage: "keyboard")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            
            if showShortcutsEditor {
                ShortcutsEditorView()
                    .environmentObject(appState)
            }
        }
        .padding()
        .onAppear {
            inputKey = appState.apiKey
        }
    }
}

// MARK: - Shortcuts Editor
struct ShortcutsEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingShortcut: KeyboardShortcut?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Links")
                    .font(.caption.bold())
                
                Spacer()
                
                Button("Reset") {
                    appState.shortcutsManager.resetToDefaults()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
            
            ForEach(appState.shortcutsManager.shortcuts) { shortcut in
                ShortcutRowView(shortcut: shortcut) { updated in
                    appState.shortcutsManager.updateShortcut(updated)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    let onUpdate: (KeyboardShortcut) -> Void
    
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedURL: String = ""
    @State private var editedKey: String = ""
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                if isEditing {
                    TextField("Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 60)
                    
                    TextField("URL", text: $editedURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                    
                    TextField("Key", text: $editedKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 30)
                    
                    Button("Save") {
                        var updated = shortcut
                        updated.name = editedName
                        updated.url = editedURL
                        updated.keyEquivalent = editedKey
                        onUpdate(updated)
                        isEditing = false
                    }
                    .font(.caption2)
                    .buttonStyle(.borderedProminent)
                } else {
                    Text(shortcut.name)
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    
                    Text(shortcut.url)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Text("⌘⇧\(shortcut.keyEquivalent.uppercased())")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                    
                    Button {
                        editedName = shortcut.name
                        editedURL = shortcut.url
                        editedKey = shortcut.keyEquivalent
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
