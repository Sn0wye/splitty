//
//  ExpenseCSV.swift
//  Splitty
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A group's expenses and settlements as a spreadsheet: one row per record, oldest first,
/// with one column per person holding their share.
struct ExpenseCSV: Transferable {
    let groupName: String
    let expenses: [Expense]

    var fileName: String {
        let name = groupName.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        return name.isEmpty ? "Splitty" : name
    }

    var text: String {
        let rows = expenses
            .map { (expense: $0, date: $0.effectiveDate) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let people = Dictionary(
            expenses.flatMap(\.splits).map { ($0.userId, $0.user.name) },
            uniquingKeysWith: { first, _ in first }
        )
        .sorted { ($0.value, $0.key) < ($1.value, $1.key) }

        let header = ["Date", "Description", "Category", "Paid by", "Amount"] + people.map(\.value)
        let lines = rows.map { row in
            let shares = Dictionary(row.expense.splits.map { ($0.userId, $0.amount) }, uniquingKeysWith: +)
            return [
                row.date.map { Self.dayFormatter.string(from: $0) } ?? "",
                row.expense.description,
                row.expense.category.name,
                row.expense.paidByUser.name,
                Self.amount(row.expense.amount),
            ] + people.map { shares[$0.key].map(Self.amount) ?? "" }
        }

        // The byte-order mark makes Excel read the file as UTF-8 instead of guessing.
        return "\u{FEFF}" + ([header] + lines)
            .map { $0.map(Self.field).joined(separator: ",") }
            .joined(separator: "\r\n")
    }

    // Exported as a file URL, not as CSV content: CSV conforms to plain text, so AirDrop
    // sends CSV content as a text snippet and a Mac saves it as `.txt`.
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { csv in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(csv.fileName).csv")
            try csv.text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    /// Always a `.` decimal separator, so the column stays numeric whatever the locale.
    private static func amount(_ value: Double) -> String {
        String(format: "%.2f", Money.amount(cents: Money.cents(from: value)))
    }

    /// Quotes a field when it needs it, and defuses text a spreadsheet would run as a
    /// formula: descriptions and names are typed by other members.
    static func field(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil {
            value = "'" + value
        }
        guard value.contains(where: { ",\"\r\n".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
