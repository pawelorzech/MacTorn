import SwiftUI

enum AppTab: String, CaseIterable {
    case status = "Status"
    case money = "Money"
    case attacks = "Attacks"
    case faction = "Faction"
    case watchlist = "Watchlist"
    
    var icon: String {
        switch self {
        case .status: return "chart.bar.fill"
        case .money: return "dollarsign.circle.fill"
        case .attacks: return "bolt.shield.fill"
        case .faction: return "person.3.fill"
        case .watchlist: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var currentTab: AppTab = .status
    
    var body: some View {

        ZStack {
            VStack(spacing: 0) {
                if appState.apiKey.isEmpty || showSettings {
                    SettingsView()
                        .environmentObject(appState)
                } else {
                    // Header with last updated
                    headerView
                    
                    // Tab bar
                    tabBar
                    
                    Divider()
                    
                    // Content based on selected tab
                    tabContent
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                // Footer buttons
                footerView
            }
            .disabled(appState.isLoading && appState.lastUpdated == nil) // Disable interaction if initial loading
            
            // Loading Overlay
            if appState.isLoading && appState.lastUpdated == nil {
                Color.black.opacity(0.4)
                    .background(.ultraThinMaterial)
                
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading Torn Data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 320)
        .onAppear {
            appState.startPolling()
        }
        .task {
            await NotificationManager.shared.requestPermission()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            if let lastUpdated = appState.lastUpdated {
                Text("Updated: \(lastUpdated, formatter: timeFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    currentTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.rawValue)
                            .font(.system(size: 8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(currentTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle()) // Make entire area clickable
                }
                .buttonStyle(.plain)
                .foregroundColor(currentTab == tab ? .accentColor : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    // MARK: - Tab Content
    @ViewBuilder
    private var tabContent: some View {
        switch currentTab {
        case .status:
            StatusView()
                .environmentObject(appState)
        case .money:
            MoneyView()
                .environmentObject(appState)
        case .attacks:
            AttacksView()
                .environmentObject(appState)
        case .faction:
            FactionView()
                .environmentObject(appState)
        case .watchlist:
            WatchlistView()
                .environmentObject(appState)
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            if !appState.apiKey.isEmpty {
                Button(showSettings ? "Back" : "Settings") {
                    showSettings.toggle()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}
