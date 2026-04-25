import SwiftUI
import UniformTypeIdentifiers

// MARK: - Liquid Glass Helpers
// Requiere iOS 26 / Xcode 26 Beta

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var viewModel = AppStoreViewModel()
    @StateObject private var downloadManager = DownloadManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Int = 0
    @State private var showSetupAlert = false
    @State private var showSetupPicker = false
    @State private var showFilePickerHelp = false
    @AppStorage("kHasAskedForLiveContainerSetup") private var hasAskedForSetup = false

    @State private var verificationBackup: AppBackup? = nil
    @State private var showConflictAlert = false

    var body: some View {
        ZStack {
            mainTabView
                .environmentObject(downloadManager)
            InAppNotificationView()
        }
        .task { await performInitialSetup() }
        .onChange(of: viewModel.displayApps.count) { _ in viewModel.checkForUpdates(installedApps: downloadManager.installedApps) }
        .onChange(of: downloadManager.installedApps) { newApps in viewModel.checkForUpdates(installedApps: newApps) }
        .onChange(of: showSetupPicker) { isPresented in checkForPickerFailure(isPresented: isPresented) }
        .onChange(of: scenePhase) { phase in handleScenePhase(phase) }
        .onChange(of: downloadManager.pendingInstallation?.id) { newID in
            if newID != nil {
                showConflictAlert = true
            } else {
                showConflictAlert = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let backup = downloadManager.pendingBackups.last {
                        if !downloadManager.checkUpdateStatus(for: backup) {
                            verificationBackup = backup
                        }
                    }
                }
            }
        }
        .alert("Complete Update", isPresented: updateAlertBinding, presenting: verificationBackup) { backup in
            Button("Open LiveContainer") {
                let folderName = backup.originalInstallPath
                if let url = URL(string: "livecontainer://livecontainer-launch?bundle-name=\(folderName)") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel Update (Restore)") { downloadManager.restoreBackup(backup) }
            Button("Delete Backup", role: .destructive) { downloadManager.discardBackup(backup, deleteContainers: true) }
        } message: { backup in
            Text("Please run '\(backup.appName)' in LiveContainer to finalize the update, then return to LBox.")
        }
        .alert("Setup LiveContainer", isPresented: $showSetupAlert) {
            Button("Select Folder") { hasAskedForSetup = true; showSetupPicker = true }
            Button("Trouble Selecting?", role: .none) { showFilePickerHelp = true }
            Button("Later", role: .cancel) { hasAskedForSetup = true }
        } message: {
            Text("To enable auto-installation and launching, please select your LiveContainer storage directory.")
        }
        .fileImporter(isPresented: $showSetupPicker, allowedContentTypes: [.folder]) { res in
            if case .success(let url) = res { downloadManager.setCustomFolder(url, forApps: true) }
        }
        .alert("Have trouble selecting?", isPresented: $showFilePickerHelp) {
            Button("Open LiveContainer") {
                if let url = URL(string: "livecontainer://install") { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Open LiveContainer â My Apps â LBox â Settings â Enable Fix File Picker, then try again.")
        }
        .alert("App Conflict", isPresented: $showConflictAlert, presenting: downloadManager.pendingInstallation) { pending in
            Button("Update Existing") { downloadManager.finalizeInstallation(action: .updateExisting) }
            Button("Install as Separate App") { downloadManager.finalizeInstallation(action: .installSeparate) }
            Button("Cancel", role: .cancel) { downloadManager.finalizeInstallation(action: .cancel) }
        } message: { pending in
            Text("'\(pending.appName)' (Bundle ID: \(pending.bundleID)) is already installed. Update it or install separately?")
        }
    }

    // MARK: - Tab View con Liquid Glass (iOS 26)
    var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Store", systemImage: "bag", value: 0) {
                StoreView(viewModel: viewModel)
            }
            Tab("Apps", systemImage: "square.grid.2x2", value: 1) {
                InstalledAppsView(selectedTab: $selectedTab, viewModel: viewModel)
            }
            Tab("Download", systemImage: "arrow.down.circle", value: 2) {
                DirectDownloadView(viewModel: viewModel)
            }
            Tab("Settings", systemImage: "gear", value: 3) {
                SettingsView(viewModel: viewModel)
            }
        }
        // Liquid Glass: barra de tabs translĂşcida nativa iOS 26
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    var updateAlertBinding: Binding<Bool> {
        Binding(get: { verificationBackup != nil }, set: { if !$0 { verificationBackup = nil } })
    }

    func performInitialSetup() async {
        if viewModel.displayApps.isEmpty { await viewModel.fetchAllRepos() }
        downloadManager.refreshFileList()
        downloadManager.refreshInstalledApps()
        try? await Task.sleep(nanoseconds: 500_000_000)
        viewModel.checkForUpdates(installedApps: downloadManager.installedApps)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if !hasAskedForSetup && downloadManager.customLiveContainerFolder == nil {
            showSetupAlert = true
        }
    }

    func checkForPickerFailure(isPresented: Bool) {
        if !isPresented {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if downloadManager.customLiveContainerFolder == nil && hasAskedForSetup {
                    showFilePickerHelp = true
                }
            }
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        NotificationManager.shared.isAppInForeground = (phase == .active)
        if phase == .active {
            let backupToCheck = verificationBackup ?? downloadManager.pendingBackups.last
            if let backup = backupToCheck {
                if downloadManager.checkUpdateStatus(for: backup) {
                    verificationBackup = nil
                } else {
                    verificationBackup = backup
                }
            }
        }
    }
}

// MARK: - Store View

struct StoreView: View {
    @ObservedObject var viewModel: AppStoreViewModel

    var body: some View {
        NavigationStack {
            List {
                // Progress de carga con fondo de cristal
                if viewModel.isLoading && viewModel.fetchTotal > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Updating RepositoriesâŚ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(viewModel.fetchProgress), total: Double(viewModel.fetchTotal))
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        HStack {
                            Spacer()
                            Text("\(viewModel.fetchProgress)/\(viewModel.fetchTotal)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if !viewModel.savedRepos.isEmpty {
                    Picker("Source", selection: $viewModel.selectedRepoID) {
                        Text("All Sources").tag(String?.none)
                        ForEach(viewModel.getEnabledLeafRepos()) { repo in
                            Text(repo.name).tag(repo.name as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .listRowBackground(Color.clear)
                    .padding(.bottom, 5)
                }

                ForEach(viewModel.filteredApps) { app in
                    NavigationLink(destination: AppDetailView(app: app, viewModel: viewModel)) {
                        AppRowView(app: app, viewModel: viewModel)
                    }
                    // Liquid Glass: fila con material translĂşcido
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Fondo con gradiente sutil para que el glass tenga algo que reflejar
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.accentColor.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.fetchAllRepos() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    // Liquid Glass: botĂłn con estilo glass nativo
                    .buttonStyle(.glass)
                }
            }
            .refreshable { await viewModel.fetchAllRepos() }
            .overlay {
                if viewModel.filteredApps.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Apps Found",
                        systemImage: "tray",
                        description: Text("Try adding more repositories in Settings.")
                    )
                }
            }
        }
    }
}

// MARK: - App Row

struct AppRowView: View {
    let app: AppItem
    @ObservedObject var viewModel: AppStoreViewModel

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary)
                        .overlay(Image(systemName: "app").foregroundStyle(.tertiary))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(app.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if viewModel.hasUpdate(for: app) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.tint)
                            .font(.caption)
                    }
                }
                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("v\(app.version)")
                    if let size = app.size {
                        Text("Âˇ")
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}
