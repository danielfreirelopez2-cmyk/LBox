import SwiftUI

struct AppDetailView: View {
    let app: AppItem
    @ObservedObject var viewModel: AppStoreViewModel
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var showSetupNeeded = false

    private var versionHistory: [AppItem] {
        return viewModel.getVersions(for: app)
    }

    var body: some View {
        ZStack {
            // Fondo degradado sutil para potenciar el efecto glass
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)
                        .padding(.horizontal)
                        .padding(.top)

                    if !app.screenshotURLs.isEmpty {
                        screenshotsSection
                            .padding(.vertical, 8)
                    }

                    aboutSection
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                        .padding(.horizontal)

                    versionsSection
                        .padding(.bottom, 48)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Setup Required", isPresented: $showSetupNeeded) {
            Button("Open LiveContainer") {
                if let name = downloadManager.getInstalledAppName(bundleID: app.bundleIdentifier),
                   let url = URL(string: "livecontainer://livecontainer-launch?bundle-name=\(name)") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This app has not been configured yet. Please open LiveContainer, run this app once to generate its configuration.")
        }
    }

    // MARK: - Header
    var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.quaternary)
                        .overlay(Image(systemName: "app").foregroundStyle(.tertiary).font(.largeTitle))
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.quaternary)
                        .overlay(ProgressView())
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(app.name)
                    .font(.title2.weight(.bold))

                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("v\(app.version)")
                    if let size = app.size {
                        Text("Â·")
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let repo = app.sourceRepoName {
                    Text(repo)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12))
                        .foregroundStyle(.tint)
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    DownloadButton(app: app)

                    if downloadManager.isAppInstalled(bundleID: app.bundleIdentifier) {
                        Button {
                            launchApp(bundleID: app.bundleIdentifier)
                        } label: {
                            Text("OPEN")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 7)
                                .background(.tint)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Screenshots
    var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline.weight(.semibold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.screenshotURLs, id: \.self) { urlString in
                        AsyncImage(url: URL(string: urlString)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fit)
                            } else {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.regularMaterial)
                                    .frame(width: 200, height: 350)
                                    .overlay(ProgressView())
                            }
                        }
                        .frame(height: 350)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - About
    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("About", systemImage: "info.circle")
                .font(.headline.weight(.semibold))
            Text(app.localizedDescription ?? "No description available.")
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Versions
    var versionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Version History", systemImage: "clock.arrow.circlepath")
                .font(.headline.weight(.semibold))
                .padding(.horizontal)

            ForEach(versionHistory) { versionApp in
                VersionRow(app: versionApp)
            }
        }
    }

    func launchApp(bundleID: String) {
        if let installedApp = downloadManager.installedApps.first(where: { $0.bundleID == bundleID }) {
            if downloadManager.hasLCAppInfo(bundleID: bundleID) {
                let folderName = installedApp.url.lastPathComponent
                if let url = URL(string: "livecontainer://livecontainer-launch?bundle-name=\(folderName)") {
                    UIApplication.shared.open(url)
                }
            } else {
                showSetupNeeded = true
            }
        }
    }
}

// MARK: - Version Row

struct VersionRow: View {
    let app: AppItem
    @EnvironmentObject var downloadManager: DownloadManager

    var isInstalledVersion: Bool {
        guard let current = downloadManager.getInstalledVersion(bundleID: app.bundleIdentifier) else { return false }
        return current == app.version
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Version \(app.version)")
                        .font(.subheadline.weight(.semibold))

                    if let repo = app.sourceRepoName {
                        Text(repo)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if isInstalledVersion {
                        Text("Installed")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Text(app.versionDate ?? "Unknown Date")
                    if let size = app.size {
                        Text("Â·")
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            DownloadButton(app: app, compact: true)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Share Sheet

struct FileShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Download Button

struct DownloadButton: View {
    let app: AppItem
    var compact: Bool = false
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var showShareSheet = false

    var body: some View {
        let downloadURL = URL(string: app.downloadURL)

        Group {
            if let url = downloadURL, let localURL = downloadManager.getLocalFile(for: url) {
                Button { showShareSheet = true } label: {
                    if compact {
                        Image(systemName: "doc.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    } else {
                        Label("Share IPA", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    FileShareSheet(activityItems: [localURL])
                }

            } else if let task = downloadURL.flatMap({ downloadManager.activeDownloads[$0] }) {
                // En progreso
                HStack(spacing: 6) {
                    ProgressView(value: task.progress)
                        .progressViewStyle(.circular)
                        .scaleEffect(compact ? 0.7 : 0.9)
                    if !compact {
                        Text("\(Int(task.progress * 100))%")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Button { downloadManager.cancelDownload(url: downloadURL!) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, compact ? 4 : 10)

            } else {
                Button {
                    if let url = downloadURL { downloadManager.startDownload(app: app, url: url) }
                } label: {
                    if compact {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    } else {
                        Label("GET", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 7)
                            .background(.tint)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
