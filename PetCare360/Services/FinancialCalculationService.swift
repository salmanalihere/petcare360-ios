import Foundation

/// The single definition of expense totals, used by the UI and PDF reports.
enum FinancialCalculationService {
    static func total(_ expenses: [PetExpense]) -> Decimal {
        expenses.reduce(Decimal(0)) { $0 + $1.amount }
    }
    static func total(_ expenses: [PetExpense], inMonthOf date: Date, calendar: Calendar = .current) -> Decimal {
        total(expenses.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) })
    }
    static func total(_ expenses: [PetExpense], inYearOf date: Date, calendar: Calendar = .current) -> Decimal {
        total(expenses.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .year) })
    }
    static func totalsByCategory(_ expenses: [PetExpense]) -> [(ExpenseCategory, Decimal)] {
        ExpenseCategory.allCases.compactMap { category in
            let sum = total(expenses.filter { $0.category == category })
            return sum == 0 ? nil : (category, sum)
        }.sorted { $0.1 > $1.1 }
    }
    static func totalsByPet(_ expenses: [PetExpense]) -> [(String, Decimal)] {
        var map: [String: Decimal] = [:]
        for expense in expenses {
            let key = expense.pet?.name ?? "Unassigned"
            map[key, default: 0] += expense.amount
        }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
    static func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}
