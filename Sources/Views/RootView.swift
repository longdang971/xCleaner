import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $state.module)
                .frame(width: Metrics.sidebarWidth)

            Divider().overlay(Palette.hairline)

            ZStack {
                Palette.canvas.ignoresSafeArea()
                content
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity))
                    .id(state.module)
            }
            .animation(Motion.standard, value: state.module)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .xcSelectModule)) { note in
            guard let raw = note.object as? String,
                  let m = CleanModule(rawValue: raw) else { return }
            withAnimation(Motion.standard) { state.module = m }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(nil)
    }

    @ViewBuilder
    private var content: some View {
        switch state.module {
        case .smartScan, .systemJunk, .trashDownloads, .privacy:
            GroupedModuleView(store: state.scanStore(for: state.module))
        case .uninstaller:
            UninstallerView(store: state.uninstall)
        case .largeOld:
            LargeOldView(store: state.largeOld)
        case .duplicates:
            DuplicatesView(store: state.duplicates)
        }
    }
}
