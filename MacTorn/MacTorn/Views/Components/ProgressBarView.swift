import SwiftUI

struct ProgressBarView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let label: String
    let current: Int
    let maximum: Int
    let color: Color
    let icon: String
    
    private var progress: Double {
        guard maximum > 0 else { return 0 }
        return min(1.0, Double(current) / Double(maximum))
    }
    
    private var isFull: Bool {
        current >= maximum
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption.bold())
                
                Text(label)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(current)/\(maximum)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(isFull ? color : .secondary)
                    .fontWeight(isFull ? .bold : .regular)
            }
            
            // Progress bar with visible styling
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(reduceTransparency ? 0.5 : 0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(color.opacity(reduceTransparency ? 0.5 : 0.3), lineWidth: 1)
                        )
                    
                    // Filled progress
                    if progress > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(reduceTransparency ? 0.9 : 0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geometry.size.width * progress))
                            .shadow(color: color.opacity(reduceTransparency ? 0.7 : 0.5), radius: 2, x: 0, y: 0)
                    }
                }
            }
            .frame(height: 10)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ProgressBarView(label: "Energy", current: 75, maximum: 100, color: .green, icon: "bolt.fill")
        ProgressBarView(label: "Nerve", current: 50, maximum: 50, color: .red, icon: "flame.fill")
        ProgressBarView(label: "Happy", current: 500, maximum: 1000, color: .yellow, icon: "face.smiling.fill")
        ProgressBarView(label: "Life", current: 0, maximum: 100, color: .blue, icon: "heart.fill")
    }
    .padding()
    .frame(width: 280)
    .background(Color(NSColor.windowBackgroundColor))
}
