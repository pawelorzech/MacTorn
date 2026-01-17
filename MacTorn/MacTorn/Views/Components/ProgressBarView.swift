import SwiftUI

struct ProgressBarView: View {
    let label: String
    let current: Int
    let maximum: Int
    let color: Color
    let icon: String
    
    private var progress: Double {
        guard maximum > 0 else { return 0 }
        return Double(current) / Double(maximum)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                
                Text(label)
                    .font(.caption.bold())
                
                Spacer()
                
                Text("\(current)/\(maximum)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                    
                    // Foreground
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ProgressBarView(label: "Energy", current: 75, maximum: 100, color: .green, icon: "bolt.fill")
        ProgressBarView(label: "Nerve", current: 25, maximum: 50, color: .red, icon: "flame.fill")
        ProgressBarView(label: "Happy", current: 1000, maximum: 1000, color: .yellow, icon: "face.smiling.fill")
    }
    .padding()
    .frame(width: 280)
}
