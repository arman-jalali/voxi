// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import Combine
import ServiceManagement
import SwiftUI
import JotCore

/// The one app window — System Settings idiom: icon-tile sidebar, grouped detail.
/// Your data (History, Dictionary) on top; app configuration below.
@MainActor
final class MainWindowController: NSWindowController {
    private var hosting: NSHostingView<MainView>?
    private let model: MainWindowModel
    private var titleObserver: AnyCancellable?

    init(
        store: HistoryStore?,
        onRetry: @escaping (DictationRecord) -> Void,
        onDeleteAllHistory: @escaping () -> Void
    ) {
        model = MainWindowModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = model.selection.title
        window.titlebarAppearsTransparent = true
        window.center()
        super.init(window: window)
        // System Settings idiom: the titlebar names the selected pane (the app
        // name already anchors the sidebar header).
        titleObserver = model.$selection.sink { [weak window] section in
            window?.title = section.title
        }
        window.contentView = NSHostingView(rootView: MainView(
            model: model,
            store: store,
            onRetry: onRetry,
            onDeleteAllHistory: onDeleteAllHistory
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(section: MainSection) {
        model.selection = section
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum MainSection: String, CaseIterable, Identifiable {
    case history, dictionary
    case general, dictation, privacy, advanced
    case about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .dictionary: return "Dictionary"
        case .general: return "General"
        case .dictation: return "Dictation"
        case .privacy: return "Privacy & Storage"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed.fill"
        case .general: return "gearshape.fill"
        case .dictation: return "waveform"
        case .privacy: return "hand.raised.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tileColor: Color {
        switch self {
        case .history: return JotUI.Colors.gBlue
        case .dictionary: return Color(nsColor: .systemOrange)
        case .general: return Color(nsColor: .systemGray)
        case .dictation: return Color(nsColor: .systemTeal)
        case .privacy: return Color(nsColor: .systemGreen)
        case .advanced: return Color(nsColor: .systemIndigo)
        case .about: return Color(nsColor: .systemPink)
        }
    }

    static let dataSections: [MainSection] = [.history, .dictionary]
    static let settingsSections: [MainSection] = [.general, .dictation, .privacy, .advanced, .about]
}

@MainActor
final class MainWindowModel: ObservableObject {
    @Published var selection: MainSection = .history
}

private struct MainView: View {
    @ObservedObject var model: MainWindowModel
    let store: HistoryStore?
    let onRetry: (DictationRecord) -> Void
    let onDeleteAllHistory: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 880, minHeight: 580)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Voxi")
                .font(JotUI.TypeScale.title())
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 12)
            ForEach(MainSection.dataSections) { section in
                SidebarRow(section: section, selected: model.selection == section) {
                    model.selection = section
                }
            }
            Text("Settings")
                .font(JotUI.TypeScale.labelSmall())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 4)
            ForEach(MainSection.settingsSections) { section in
                SidebarRow(section: section, selected: model.selection == section) {
                    model.selection = section
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 210)
        .background(.thickMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch model.selection {
            case .history:
                if let store {
                    HistoryPane(store: store, onRetry: onRetry)
                } else {
                    ContentUnavailableView("History unavailable", systemImage: "clock.badge.exclamationmark")
                }
            case .dictionary:
                DictionaryView()
            case .general:
                GeneralPane().formStyle(.grouped)
            case .dictation:
                DictationPane().formStyle(.grouped)
            case .privacy:
                PrivacyPane(onDeleteAllHistory: onDeleteAllHistory).formStyle(.grouped)
            case .advanced:
                AdvancedPane().formStyle(.grouped)
            case .about:
                AboutPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarRow: View {
    let section: MainSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(section.tileColor))
                Text(section.title)
                    .font(JotUI.TypeScale.body())
                    .foregroundStyle(selected ? Color.white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: JotUI.Radius.small)
                    .fill(selected ? JotUI.Colors.primary
                          : hovering ? Color.primary.opacity(JotUI.StateLayer.hover)
                          : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - General

struct GeneralPane: View {
    private let settings = SettingsStore()

    @State private var hotkey = SettingsStore().hotkeyKey
    @State private var doubleTapLock = SettingsStore().doubleTapLockEnabled
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Dictation key", selection: $hotkey) {
                    ForEach(HotkeyKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .onChange(of: hotkey) { _, newKey in
                    settings.setHotkeyKey(newKey)
                }
                Toggle("Double-tap to lock hands-free", isOn: $doubleTapLock)
                    .onChange(of: doubleTapLock) { _, enabled in
                        settings.setDoubleTapLock(enabled)
                    }
            } footer: {
                Text("Hold to talk. Tap Space while holding to go hands-free. Esc cancels.")
            }

            Section {
                Toggle("Start Voxi at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        // The failure-path revert below re-enters onChange with the
                        // inverted value — this guard stops the bounce from calling
                        // into SMAppService a second time.
                        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            Log.ui.error("launch-at-login toggle failed: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        // Login-item state lives in macOS, not in our defaults, so it can change
        // with the app running — System Settings › General › Login Items turns it
        // off without telling us. A stale ON toggle is worse than cosmetic here:
        // the onChange guard above compares against the REAL status, so tapping
        // the stale toggle decides nothing changed and silently does nothing.
        // Re-reading on appear also covers reopening the window.
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            hotkey = settings.hotkeyKey
            doubleTapLock = settings.doubleTapLockEnabled
        }
        // The other panes guard the same way; these two can move under us from
        // the DEBUG jot://set driver.
        .onReceive(NotificationCenter.default.publisher(for: .gtSettingDidChange).receive(on: RunLoop.main)) { note in
            switch note.object as? String {
            case "hotkeyKey": hotkey = settings.hotkeyKey
            case "doubleTapLock": doubleTapLock = settings.doubleTapLockEnabled
            default: break
            }
        }
    }
}

// MARK: - Dictation

struct DictationPane: View {
    private let settings = SettingsStore()
    @State private var sounds = SettingsStore().soundsEnabled
    @State private var showIdleDot = SettingsStore().showIdleIndicator
    @State private var noiseHandling = SettingsStore().experimentalNoiseHandling

    var body: some View {
        Form {
            Section {
                Toggle("Sounds", isOn: $sounds)
                    .onChange(of: sounds) { _, enabled in settings.setSoundsEnabled(enabled) }
                Toggle("Show resting indicator", isOn: $showIdleDot)
                    .onChange(of: showIdleDot) { _, show in settings.setShowIdleIndicator(show) }
            } footer: {
                Text("The resting dot grows into a Dictate button on hover; click it for hands-free. Off = the pill appears only while dictating.")
            }

            Section {
                Toggle("Better hearing in loud rooms", isOn: $noiseHandling)
                    .onChange(of: noiseHandling) { _, enabled in
                        settings.setExperimentalNoiseHandling(enabled)
                    }
            } header: {
                Text("Experimental")
            } footer: {
                Text("Judges your voice against the actual room noise instead of a fixed level. Off by default.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gtSettingDidChange).receive(on: RunLoop.main)) { note in
            // jot://set drives this headlessly in DEBUG — the pane must not show
            // a stale toggle after the flag moved underneath it.
            if note.object as? String == "experimentalNoiseHandling" {
                noiseHandling = settings.experimentalNoiseHandling
            }
        }
    }
}

// MARK: - Privacy & Storage

struct PrivacyPane: View {
    let onDeleteAllHistory: () -> Void
    private let settings = SettingsStore()
    @State private var retentionDays = SettingsStore().audioRetentionDays
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section {
                Picker("Keep audio recordings", selection: $retentionDays) {
                    Text("Never (disables Retry)").tag(-1)
                    Text("24 hours").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Forever").tag(0)
                }
                .onChange(of: retentionDays) { _, days in
                    settings.setAudioRetentionDays(days)
                    // Off the main thread — the purge walks every recording folder
                    // and would hitch the pane with a large history (the 6h timer
                    // path already detaches).
                    Task.detached(priority: .utility) {
                        RetentionPolicy(audioRetentionDays: days).purgeExpiredAudio()
                    }
                }
            } footer: {
                Text("Transcripts stay in History until you delete them.")
            }

            Section {
                LabeledContent("Audio") { Text("Transcribed by Voxtral, running on this Mac") }
                LabeledContent("Transcript text") { Text("Never leaves this Mac") }
                LabeledContent("Everything else") { Text("Never leaves this Mac") }
            } header: {
                Text("What leaves your Mac")
            } footer: {
                Text("Nothing. The model runs locally — no cloud API, no account, no analytics, no keystroke logging.")
            }

            Section {
                Button("Delete All History…", role: .destructive) {
                    confirmingDelete = true
                }
                .confirmationDialog(
                    "Delete all dictation history? Audio and transcripts will be removed from this Mac.",
                    isPresented: $confirmingDelete
                ) {
                    Button("Delete Everything", role: .destructive) { onDeleteAllHistory() }
                }
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @State private var checking = true
    @State private var healthy = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Model") { Text(LocalTranscriptionService.modelID) }
                LabeledContent("Server") {
                    if checking {
                        ProgressView().controlSize(.small)
                    } else if healthy {
                        Label("Running", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(JotUI.Colors.success)
                    } else {
                        Label("Not running", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(JotUI.Colors.error)
                    }
                }
                HStack {
                    Button("Check Again") { check() }
                    Spacer()
                }
            } header: {
                Text("Local transcription")
            } footer: {
                Text(healthy || checking
                     ? "Voxtral runs entirely on this Mac. Nothing is sent to any cloud API."
                     : "Voxi starts the model server automatically at launch — the first start loads the model and can take a minute. If it stays down, run scripts/server.sh from the Voxi folder.")
            }
        }
        .onAppear { check() }
    }

    private func check() {
        checking = true
        Task {
            let ok = await VoxtralClient().isHealthy()
            healthy = ok
            checking = false
        }
    }
}


// MARK: - About

/// Who made this, what version it is, and where to go next. Deliberately a
/// plain page rather than a Form: it is a colophon, not settings.
struct AboutPane: View {
    /// Read from the bundle directly: NSApp.applicationIconImage is set at
    /// launch but the standard About panel ignores it for an LSUIElement app,
    /// which is exactly why this pane exists.
    static let appIcon: NSImage? = Bundle.main
        .url(forResource: "Jot", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "Version \(short) (\(Bundle.main.buildNumber))"
    }

    var body: some View {
        VStack(spacing: JotUI.Spacing.m) {
            Spacer()
            if let icon = AboutPane.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 4) {
                Text("Voxi")
                    .font(JotUI.TypeScale.display())
                    .foregroundStyle(JotUI.Colors.onSurface)
                Text(version)
                    .font(JotUI.TypeScale.body())
                    .foregroundStyle(JotUI.Colors.onSurfaceVariant)
            }
            HStack(spacing: 4) {
                Text("Local dictation with")
                    .foregroundStyle(JotUI.Colors.onSurfaceVariant)
                Link("Voxtral", destination: JotLinks.model)
                Text("· a fork of")
                    .foregroundStyle(JotUI.Colors.onSurfaceVariant)
                Link("Jot", destination: JotLinks.upstream)
                Text("by")
                    .foregroundStyle(JotUI.Colors.onSurfaceVariant)
                Link("Ammaar Reshi", destination: JotLinks.upstreamAuthor)
            }
            .font(JotUI.TypeScale.body())

            if let repo = JotLinks.repository, let privacy = JotLinks.privacy, let issues = JotLinks.issues {
                HStack(spacing: JotUI.Spacing.m) {
                    Link("Source", destination: repo)
                    Link("Privacy", destination: privacy)
                    Link("Report a bug", destination: issues)
                }
                .font(JotUI.TypeScale.body())
            }

            Text("Open source under the Apache License 2.0. Everything runs on this Mac.\nNot affiliated with Google or Mistral AI.")
                .font(JotUI.TypeScale.labelSmall())
                .foregroundStyle(JotUI.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.top, JotUI.Spacing.xs)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
