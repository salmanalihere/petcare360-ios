import Foundation
import UIKit

/// PDF export service (Phase 2 rewrite): proper word wrapping, margins,
/// multi-page pagination and page numbers. Long notes, clinic names and
/// addresses wrap inside the page instead of running off it.
/// Shared through the native iOS share sheet by the calling view.
enum PDFService {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 48
    private static var contentWidth: CGFloat { pageRect.width - margin * 2 }

    private struct Item {
        let text: String
        let font: UIFont
        let spacingAfter: CGFloat
        var height: CGFloat { font.lineHeight + 3 + spacingAfter }
    }

    /// Word-wraps one logical line to the content width. Words longer than
    /// a full line are hard-broken so nothing can overflow the page.
    private static func wrap(_ text: String, font: UIFont) -> [String] {
        guard !text.isEmpty else { return [""] }
        var lines: [String] = []
        var current = ""
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        for rawWord in text.split(separator: " ", omittingEmptySubsequences: false) {
            var word = String(rawWord)
            while width(word) > contentWidth && word.count > 1 {
                var count = word.count
                while count > 1 && width(String(word.prefix(count))) > contentWidth { count -= 1 }
                lines.append(String(word.prefix(count)))
                word = String(word.dropFirst(count))
            }
            let candidate = current.isEmpty ? word : current + " " + word
            if width(candidate) > contentWidth && !current.isEmpty {
                lines.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty || lines.isEmpty { lines.append(current) }
        return lines
    }

    private static func heading(_ text: String) -> Item { Item(text: text, font: .boldSystemFont(ofSize: 13), spacingAfter: 5) }
    private static func body(_ text: String) -> Item { Item(text: text, font: .systemFont(ofSize: 11), spacingAfter: 2) }
    private static func gap() -> Item { Item(text: "", font: .systemFont(ofSize: 11), spacingAfter: 6) }

    private static func render(title: String, items: [Item]) -> Data {
        // Expand wrapping first so pagination is exact.
        var expanded: [Item] = []
        for item in items {
            let wrapped = wrap(item.text, font: item.font)
            for (index, line) in wrapped.enumerated() {
                expanded.append(Item(text: line, font: item.font,
                                     spacingAfter: index == wrapped.count - 1 ? item.spacingAfter : 0))
            }
        }
        let titleHeight: CGFloat = 36
        let usable = pageRect.height - margin * 2 - 20
        var pages: [[Item]] = [[]]
        var used: CGFloat = titleHeight
        for item in expanded {
            if used + item.height > usable {
                pages.append([])
                used = 0
            }
            pages[pages.count - 1].append(item)
            used += item.height
        }
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            for (pageIndex, pageItems) in pages.enumerated() {
                context.beginPage()
                var y: CGFloat = margin
                if pageIndex == 0 {
                    title.draw(at: CGPoint(x: margin, y: y),
                               withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
                    y += titleHeight
                }
                for item in pageItems {
                    item.text.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: item.font])
                    y += item.height
                }
                let footer = "PetCare 360 \u{2022} Generated \(Date().formatted(date: .abbreviated, time: .omitted)) \u{2022} Page \(pageIndex + 1) of \(pages.count)"
                footer.draw(at: CGPoint(x: margin, y: pageRect.height - margin + 10),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray])
            }
        }
    }

    /// Medical Passport — only the record categories the owner selected.
    static func medicalPassport(pet: Pet, include: Set<MedicalCategory>) -> Data {
        var items: [Item] = []
        items.append(body("Tagline: \(AppConfig.tagline)"))
        items.append(gap())
        items.append(heading("PET PROFILE"))
        items.append(body("Name: \(pet.name)   Species: \(pet.species.label)   Breed: \(pet.breed)"))
        if let age = pet.ageDescription { items.append(body("Age: \(age)")) }
        items.append(body("Weight: \(pet.weightKg) kg   Color: \(pet.colorMarkings)   Microchip: \(pet.microchipNumber)"))
        items.append(gap())
        if include.contains(.allergy) || include.contains(.condition) {
            items.append(heading("IMPORTANT MEDICAL INFORMATION"))
            items.append(body("Allergies: \(pet.allergies)"))
            items.append(body("Conditions: \(pet.medicalConditions)"))
            items.append(gap())
        }
        if include.contains(.vaccination) {
            items.append(heading("VACCINATION HISTORY"))
            if pet.vaccinations.isEmpty { items.append(body("No vaccinations recorded.")) }
            for vax in pet.vaccinations.sorted(by: { $0.dateAdministered < $1.dateAdministered }) {
                let exp = vax.expirationDate.map { " (expires \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
                items.append(body("- \(vax.vaccineName) — \(vax.dateAdministered.formatted(date: .abbreviated, time: .omitted))\(exp) — \(vax.clinic)"))
            }
            items.append(gap())
        }
        items.append(heading("CURRENT MEDICATIONS"))
        let active = pet.medications.filter { $0.isActive }
        if active.isEmpty { items.append(body("No active medications.")) }
        for med in active {
            items.append(body("- \(med.name) \(med.dosage) — \(med.frequency.label) — \(med.instructions)"))
        }
        items.append(gap())
        let records = pet.medicalRecords.filter { include.contains($0.category) }
            .sorted { $0.date < $1.date }
        if !records.isEmpty {
            items.append(heading("MEDICAL RECORDS"))
            for record in records {
                items.append(body("- [\(record.category.label)] \(record.title) — \(record.date.formatted(date: .abbreviated, time: .omitted))"))
                if !record.details.isEmpty { items.append(body("  \(record.details)")) }
            }
            items.append(gap())
        }
        items.append(heading("VETERINARY CONTACT"))
        items.append(body("\(pet.vetClinic)  \(pet.vetPhone)"))
        items.append(gap())
        items.append(body(AppConfig.medicalDisclaimer))
        return render(title: "Medical Passport — \(pet.name)", items: items)
    }

    static func expenseReport(petName: String, expenses: [PetExpense]) -> Data {
        var items: [Item] = []
        items.append(body("Total: \(FinancialCalculationService.format(FinancialCalculationService.total(expenses)))"))
        items.append(body("This month: \(FinancialCalculationService.format(FinancialCalculationService.total(expenses, inMonthOf: Date())))"))
        items.append(body("This year: \(FinancialCalculationService.format(FinancialCalculationService.total(expenses, inYearOf: Date())))"))
        items.append(gap())
        items.append(heading("BY CATEGORY"))
        for (category, sum) in FinancialCalculationService.totalsByCategory(expenses) {
            items.append(body("- \(category.label): \(FinancialCalculationService.format(sum))"))
        }
        items.append(gap())
        items.append(heading("ENTRIES"))
        if expenses.isEmpty { items.append(body("No expenses recorded.")) }
        for expense in expenses.sorted(by: { $0.date < $1.date }) {
            items.append(body("- \(expense.date.formatted(date: .abbreviated, time: .omitted)) — \(expense.category.label) — \(FinancialCalculationService.format(expense.amount)) — \(expense.vendor) \(expense.notes)"))
        }
        return render(title: "Expense Report — \(petName)", items: items)
    }

    static func visitPreparation(pet: Pet, appointment: VetAppointment) -> Data {
        var items: [Item] = []
        items.append(body("Appointment: \(appointment.title) — \(appointment.date.formatted(date: .abbreviated, time: .shortened))"))
        items.append(body("Clinic: \(appointment.clinic)  Vet: \(appointment.vetName)"))
        if !appointment.notes.isEmpty { items.append(body("Notes: \(appointment.notes)")) }
        items.append(gap())
        items.append(heading("CURRENT MEDICATIONS"))
        let active = pet.medications.filter { $0.isActive }
        if active.isEmpty { items.append(body("No active medications.")) }
        for med in active {
            items.append(body("- \(med.name) \(med.dosage) — \(med.frequency.label) — \(med.instructions)"))
        }
        items.append(gap())
        items.append(heading("RECENT HEALTH OBSERVATIONS"))
        for obs in pet.observations.sorted(by: { $0.date > $1.date }).prefix(10) {
            items.append(body("- \(obs.date.formatted(date: .abbreviated, time: .omitted)) [\(obs.kind.label)] \(obs.valueText) \(obs.note)"))
        }
        items.append(gap())
        items.append(heading("WEIGHT HISTORY"))
        for obs in pet.observations.filter({ $0.kind == .weight }).sorted(by: { $0.date < $1.date }) {
            if let w = obs.weightKg { items.append(body("- \(obs.date.formatted(date: .abbreviated, time: .omitted)): \(w) kg")) }
        }
        items.append(gap())
        items.append(heading("QUESTIONS FOR THE VETERINARIAN"))
        if appointment.questionList.isEmpty { items.append(body("No questions recorded.")) }
        for question in appointment.questionList { items.append(body("- \(question)")) }
        items.append(gap())
        items.append(body(AppConfig.medicalDisclaimer))
        return render(title: "Visit Preparation — \(pet.name)", items: items)
    }

    /// Lost-pet poster. Only fields the owner approved on the profile are
    /// passed in by the caller; nothing extra is printed.
    static func lostPetPoster(pet: Pet, lastSeen: String, contactMethod: String, includeMicrochip: Bool) -> Data {
        var items: [Item] = []
        items.append(body("Species: \(pet.species.label)   Breed: \(pet.breed)"))
        items.append(body("Color / markings: \(pet.colorMarkings)"))
        if !lastSeen.isEmpty { items.append(body("Last seen: \(lastSeen)")) }
        if includeMicrochip && !pet.microchipNumber.isEmpty { items.append(body("Microchip: \(pet.microchipNumber)")) }
        if !contactMethod.isEmpty { items.append(body("If found, please contact: \(contactMethod)")) }
        return render(title: "LOST PET — \(pet.name)", items: items)
    }
}
