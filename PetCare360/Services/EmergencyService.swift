import Foundation
import CoreImage
import UIKit

/// Builds the owner-controlled emergency QR payload. Only fields the owner
/// explicitly enabled on the EmergencyProfile are included; nothing else.
enum EmergencyService {
    static func payload(pet: Pet, profile: EmergencyProfile, medications: [Medication]) -> String {
        guard profile.isEnabled else { return "" }
        var parts: [String] = ["PETCARE360-EMERGENCY", "Name: \(pet.name)"]
        if profile.shares("allergies") && !pet.allergies.isEmpty { parts.append("Allergies: \(pet.allergies)") }
        if profile.shares("conditions") && !pet.medicalConditions.isEmpty { parts.append("Conditions: \(pet.medicalConditions)") }
        if profile.shares("medications") {
            let meds = medications.filter { $0.isActive }.map { "\($0.name) \($0.dosage)" }
            if !meds.isEmpty { parts.append("Medications: \(meds.joined(separator: "; "))") }
        }
        if profile.shares("microchip") && !pet.microchipNumber.isEmpty { parts.append("Microchip: \(pet.microchipNumber)") }
        if profile.shares("vet") && !pet.vetClinic.isEmpty { parts.append("Vet: \(pet.vetClinic) \(pet.vetPhone)") }
        if profile.shares("emergencyContact") && !pet.emergencyContactPhone.isEmpty {
            parts.append("Emergency contact: \(pet.emergencyContactName) \(pet.emergencyContactPhone)")
        }
        if profile.shares("insurance") && !pet.insuranceInfo.isEmpty { parts.append("Insurance: \(pet.insuranceInfo)") }
        if profile.shares("notes") && !pet.notes.isEmpty { parts.append("Notes: \(pet.notes)") }
        return parts.joined(separator: "\n")
    }

    static func qrImage(from payload: String) -> UIImage? {
        guard !payload.isEmpty, let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
