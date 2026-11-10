import SwiftUI
import UIKit

/// The fixed set of bundled app icons (2026-11-06). Users choose
/// ONLY from these pre-designed icons — there is no photo upload or
/// custom icon creation. The primary icon (Dog and Cat) ships as the
/// asset catalog's AppIcon; the rest are alternate app icons wired
/// through ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS, which
/// makes Xcode generate the CFBundleAlternateIcons entries — the
/// only supported route to changing the Home Screen icon.
struct AppIconOption: Identifiable, Equatable {
    let id: String
    let label: String
    /// nil = the primary icon.
    let alternateName: String?
    let previewImageName: String

    /// The primary icon (the asset catalog's AppIcon): the only
    /// option whose alternateName is nil, and the fallback the
    /// pickers display when the stored selection names an icon
    /// this build no longer ships.
    static let primary = AppIconOption(id: "dogcat", label: "Dog and Cat", alternateName: nil, previewImageName: "IconPreviewDogCat")

    static let all: [AppIconOption] = [
        primary,
        AppIconOption(id: "dog", label: "Dog", alternateName: "AppIconDog", previewImageName: "IconPreviewDog"),
        AppIconOption(id: "cat", label: "Cat", alternateName: "AppIconCat", previewImageName: "IconPreviewCat"),
        AppIconOption(id: "bird", label: "Bird", alternateName: "AppIconBird", previewImageName: "IconPreviewBird"),
        AppIconOption(id: "rabbit", label: "Rabbit", alternateName: "AppIconRabbit", previewImageName: "IconPreviewRabbit"),
        AppIconOption(id: "turtle", label: "Turtle", alternateName: "AppIconTurtle", previewImageName: "IconPreviewTurtle"),
        AppIconOption(id: "horse", label: "Horses", alternateName: "AppIconHorse", previewImageName: "IconPreviewHorse"),
        AppIconOption(id: "other", label: "Other Pets", alternateName: "AppIconOther", previewImageName: "IconPreviewOther"),
    ]
}

enum AppIconService {
    static var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }
    static var currentAlternateName: String? { UIApplication.shared.alternateIconName }

    /// Resolves a STORED alternate-icon name to the option the
    /// pickers should treat as current: the matching option when
    /// the name is still supported by this build, and the PRIMARY
    /// option when there is no stored name or the stored name is
    /// unknown — e.g. "AppIconReptile", retired in favour of
    /// "AppIconTurtle". iOS persists selections by name across app
    /// updates and itself falls back to displaying the primary
    /// icon when the stored name no longer exists in the bundle;
    /// the pickers mirror that fallback so exactly one option
    /// — the primary — shows as Current instead of none.
    /// Pure and side-effect free: resolving NEVER changes the
    /// actual icon; the stored name is left exactly as iOS holds
    /// it until the user explicitly picks an icon (see setIcon).
    static func resolvedCurrentOption(forStoredName storedName: String?) -> AppIconOption {
        guard let storedName else { return .primary }
        return AppIconOption.all.first { $0.alternateName == storedName } ?? .primary
    }

    /// The alternate-icon name the pickers display as current:
    /// `resolvedCurrentOption` applied to the live stored name.
    /// Both pickers read this (never the raw stored name), so the
    /// Settings and onboarding pickers can never disagree.
    static var displayAlternateName: String? {
        resolvedCurrentOption(forStoredName: currentAlternateName).alternateName
    }

    /// Applies the icon through the real system API. iOS shows its
    /// own confirmation alert for icon changes — that is expected
    /// system behaviour, not an app error. The selection persists
    /// across launches because iOS itself stores it
    /// (UIApplication.alternateIconName), which this screen reads.
    static func setIcon(_ option: AppIconOption, completion: @escaping (String?) -> Void) {
        guard supportsAlternateIcons else {
            completion("This device does not support alternate app icons.")
            return
        }
        let target = option.alternateName
        // Same-name re-application fix (2026-11-10): when the
        // requested icon is ALREADY the current alternate, setting
        // the same name again gives iOS no name change, and it can
        // keep serving artwork cached under that name from a
        // previous bundle. Reset to the primary icon first, then
        // set the target name in the completion — a genuine name
        // change (nil → target) forces iOS to re-render the Home
        // Screen icon from the current bundle. Only the supported
        // public API is used, in both steps. (This is also why the
        // old "AppIconReptile" set was retired in favour of the
        // new "AppIconTurtle" set: a name that has never shipped
        // before cannot carry artwork cached under it.)
        if let target, target == currentAlternateName {
            UIApplication.shared.setAlternateIconName(nil) { _ in
                UIApplication.shared.setAlternateIconName(target) { error in
                    DispatchQueue.main.async {
                        completion(error?.localizedDescription)
                    }
                }
            }
            return
        }
        UIApplication.shared.setAlternateIconName(target) { error in
            DispatchQueue.main.async {
                completion(error?.localizedDescription)
            }
        }
    }
}

/// Settings → Choose Your App Icon: the bundled icons in a grid,
/// with the current one marked.
struct AppIconPickerSection: View {
    @State private var currentName: String? = nil
    @State private var loaded = false
    @State private var errorMessage = ""

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        Section("Choose Your App Icon") {
            if !AppIconService.supportsAlternateIcons {
                Text("Alternate app icons are not supported on this device.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppIconOption.all) { option in
                        Button { select(option) } label: {
                            VStack(spacing: 6) {
                                Image(option.previewImageName)
                                    .resizable().scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected(option) ? PCColor.freshGreen : Color.clear, lineWidth: 3))
                                Text(option.label).font(.caption).foregroundStyle(PCColor.charcoal)
                                if isSelected(option) {
                                    Label("Current", systemImage: "checkmark.circle.fill")
                                        .font(.caption2.bold()).foregroundStyle(PCColor.freshGreen)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.label) icon\(isSelected(option) ? ", currently selected" : "")")
                    }
                }
                .padding(.vertical, 4)
                Text("Dog and Cat is the default icon. iOS shows its own confirmation when the icon changes. If the Home Screen icon looks out of date after an app update, tap the current icon again to refresh it.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            currentName = AppIconService.displayAlternateName
        }
        .alert("Couldn't change icon", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage) }
    }

    private func isSelected(_ option: AppIconOption) -> Bool {
        option.alternateName == currentName
    }

    private func select(_ option: AppIconOption) {
        // Deliberately NO "already selected" early return
        // (bug fix, 2026-11-08; strengthened 2026-11-10): iOS
        // persists an alternate-icon selection BY NAME across app
        // updates, and the Home Screen can keep rendering the
        // artwork the name pointed to in the PREVIOUS bundle —
        // e.g. the old generated gecko after the owner's turtle
        // artwork replaced it. AppIconService.setIcon now resets
        // to the primary icon before re-setting the same name,
        // which is what actually forces iOS to re-render; tapping
        // the current icon must reach it, not be swallowed.
        AppIconService.setIcon(option) { error in
            if let error {
                errorMessage = error
            } else {
                currentName = AppIconService.displayAlternateName
            }
        }
    }
}
