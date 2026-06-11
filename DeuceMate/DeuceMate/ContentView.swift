import SwiftUI

struct ContentView: View {
    var body: some View {
        PastMatchesView()
    }
}

#Preview {
    ContentView()
        .environmentObject(PhoneStatsStore())
        .environmentObject(PhoneMatchSyncService())
}
