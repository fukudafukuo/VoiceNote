import SwiftUI

/// VoiceNote - macOS メニューバー音声認識メモアプリ
@main
struct VoiceNoteApp: App {

    @State private var appState: AppState

    init() {
        let state = AppState()
        _appState = State(initialValue: state)

        // RunLoopが開始された後にセットアップ実行
        DispatchQueue.main.async {
            state.setupHotKey()
            state.setupShortcuts()
            state.preloadModel()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .background {
                    #if canImport(Translation)
                    if #available(macOS 15.0, *) {
                        TranslationSessionHost(translationService: appState.translationService)
                    } else {
                        TranslationSessionHostFallback(translationService: appState.translationService)
                    }
                    #else
                    TranslationSessionHostFallback(translationService: appState.translationService)
                    #endif
                }
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}
