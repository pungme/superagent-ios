import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                Text("SuperAgent")
                    .font(.largeTitle.bold())
                Text("Your desktop agent, in your pocket.")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("SuperAgent")
        }
    }
}

#Preview {
    ContentView()
}
