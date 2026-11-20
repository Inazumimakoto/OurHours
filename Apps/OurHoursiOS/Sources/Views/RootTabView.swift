import SwiftUI

struct RootTabView: View {
    @State private var appModel: AppModel

    init(appModel: AppModel) {
        _appModel = State(initialValue: appModel)
    }

    var body: some View {
        TabView {
            Tab("ホーム", systemImage: "house") { NavigationStack { HomeView() } }
            Tab("ログ", systemImage: "list.bullet.rectangle") { NavigationStack { LogsView() } }
            Tab("設定", systemImage: "gearshape") { NavigationStack { SettingsView() } }
        }
        .environment(appModel)
    }
}
