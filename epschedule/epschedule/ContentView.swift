
import SwiftUI

struct ContentView: View {
    @StateObject private var api = EPScheduleAPI.shared
    
    var body: some View {
        Group {
            if api.isAuthenticated {
                ScheduleView()
            } else {
                NavigationView {
                    LoginView()
                }
            }
        }
        .onAppear {
            _ = api.hasAuthenticationCookies()
        }
        .onChange(of: api.isAuthenticated) { _ in
        }
    }
}

