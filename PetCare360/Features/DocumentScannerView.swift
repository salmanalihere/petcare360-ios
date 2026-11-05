import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Document scanner: pick or photograph a document, run on-device Vision
/// OCR, then REVIEW the extracted candidates. Saving only happens when
/// the user taps Save on the review form.
struct DocumentScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var allPets: [Pet]
    let pet: Pet
    private let scanner: DocumentScanning = VisionDocumentScanner()

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var imageData: Data? = nil
    @State private var pageDatas: [Data] = []
    @State private var showCamera = false
    @State private var isScanning = false
    @State private var candidate: ScannedDocumentCandidate? = nil
    @State private var pageTexts: [String] = []
    @State private var title = ""
    @State private var category: MedicalCategory = .note

    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose document photo", systemImage: "photo")
                    }
                    if DocumentCameraView.isSupported {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Scan with camera", systemImage: "doc.viewfinder")
                        }
                    } else {
                        Text("The document camera is not available on this device; use the photo library instead.")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                    if pageDatas.count > 1 {
                        Text("\(pageDatas.count) pages captured. OCR runs on every page; saving stores each page as its own document so no original is lost.")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 180)
                        Button(isScanning ? "Scanning…" : "Extract text (on-device)") { Task { await scan() } }
                            .disabled(isScanning)
                    }
                }
                if let candidate {
                    Section("Review extracted details — edit before saving") {
                        TextField("Document title", text: $title)
                        Picker("Category", selection: $category) {
                            ForEach(MedicalCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        if !candidate.clinic.isEmpty { LabeledContent("Clinic (detected)", value: candidate.clinic) }
                        if !candidate.medicationName.isEmpty { LabeledContent("Medication (detected)", value: candidate.medicationName) }
                        if !candidate.vaccinationName.isEmpty { LabeledContent("Vaccination (detected)", value: candidate.vaccinationName) }
                        if let amount = candidate.invoiceAmount {
                            LabeledContent("Invoice amount (detected)", value: FinancialCalculationService.format(amount))
                        }
                        if let date = candidate.documentDate {
                            LabeledContent("Date (detected)", value: date.formatted(date: .abbreviated, time: .omitted))
                        }
                        Text(candidate.fullText).font(.caption).foregroundStyle(PCColor.secondaryText)
                        Text("The original photo is preserved unchanged. Nothing was saved yet.")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                    Section {
                        Button("Save Document") { save() }
                            .disabled(title.isEmpty)
                    }
                }
            }
            .navigationTitle("Scan Document")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        imageData = data
                        pageDatas = [data]
                        candidate = nil
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                DocumentCameraView { images in
                    showCamera = false
                    let datas = images.compactMap { $0.jpegData(compressionQuality: 0.9) }
                    if let first = datas.first {
                        pageDatas = datas
                        imageData = first
                        candidate = nil
                    }
                } onCancel: {
                    showCamera = false
                }
            }
        }
    }

    private func scan() async {
        let pages = pageDatas.isEmpty ? (imageData.map { [$0] } ?? []) : pageDatas
        guard !pages.isEmpty else { return }
        var texts: [String] = []
        for data in pages {
            if let image = UIImage(data: data), let text = try? await scanner.recognizeText(in: image) {
                texts.append(text)
            }
        }
        pageTexts = pages.indices.map { $0 < texts.count ? texts[$0] : "" }
        let parsed = DocumentTextParser.parse(texts.joined(separator: "\n"), knownPetNames: allPets.map { $0.name })
        candidate = parsed
        category = parsed.category
        title = parsed.vaccinationName.isEmpty ? "Scanned document" : parsed.vaccinationName
    }

    private func save() {
        guard let candidate else { return }
        let pages = pageDatas.isEmpty ? (imageData.map { [$0] } ?? []) : pageDatas
        guard !pages.isEmpty else { return }
        // One document per page: every original page is preserved unchanged.
        for (index, data) in pages.enumerated() {
            let document = MedicalDocument(title: pages.count > 1 ? "\(title) — page \(index + 1)" : title)
            document.categoryRaw = category.rawValue
            document.originalData = data
            // Each page keeps ITS OWN extracted text (v1.2.4); the
            // combined text is only the fallback when a page's OCR
            // produced nothing.
            document.extractedText = pageTexts.indices.contains(index) && !pageTexts[index].isEmpty
                ? pageTexts[index] : candidate.fullText
            document.pet = pet
            context.insert(document)
        }
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        dismiss()
    }
}
