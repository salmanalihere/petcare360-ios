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

    static let all: [AppIconOption] = [
        AppIconOption(id: "dogcat", label: "Dog and Cat", alternateName: nil, previewImageName: "IconPreviewDogCat"),
        AppIconOption(id: "dog", label: "Dog", alternateName: "AppIconDog", previewImageName: "IconPreviewDog"),
        AppIconOption(id: "cat", label: "Cat", alternateName: "AppIconCat", previewImageName: "IconPreviewCat"),
        AppIconOption(id: "bird", label: "Bird", alternateName: "AppIconBird", previewImageName: "IconPreviewBird"),
        AppIconOption(id: "rabbit", label: "Rabbit", alternateName: "AppIconRabbit", previewImageName: "IconPreviewRabbit"),
        AppIconOption(id: "reptile", label: "Reptiles", alternateName: "AppIconReptile", previewImageName: "IconPreviewReptile"),
        AppIconOption(id: "horse", label: "Horses", alternateName: "AppIconHorse", previewImageName: "IconPreviewHorse"),
        AppIconOption(id: "other", label: "Other Pets", alternateName: "AppIconOther", previewImageName: "IconPreviewOther"),
    ]
}

enum AppIconService {
    static var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }
    static var currentAlternateName: String? { UIApplication.shared.alternateIconName }

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
        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
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
                Text("Dog and Cat is the default icon. iOS shows its own confirmation when the icon changes.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            currentName = AppIconService.currentAlternateName
        }
        .alert("Couldn't change icon", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage) }
    }

    private func isSelected(_ option: AppIconOption) -> Bool {
        option.alternateName == currentName
    }

    private func select(_ option: AppIconOption) {
        guard !isSelected(option) else { return }
        AppIconService.setIcon(option) { error in
            if let error {
                errorMessage = error
            } else {
                currentName = AppIconService.currentAlternateName
            }
        }
    }
}
