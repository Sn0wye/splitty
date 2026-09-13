import SwiftUI

enum ExpenseCategoryHeading: CaseIterable, Identifiable {
    case uncategorized
    case entertainment
    case foodAndDrink
    case home
    case life
    case transportation
    case utilities

    var id: Self { self }

    var title: String {
        switch self {
        case .uncategorized: L10n.CategoryHeading.uncategorized
        case .entertainment: L10n.CategoryHeading.entertainment
        case .foodAndDrink: L10n.CategoryHeading.foodAndDrink
        case .home: L10n.CategoryHeading.home
        case .life: L10n.CategoryHeading.life
        case .transportation: L10n.CategoryHeading.transportation
        case .utilities: L10n.CategoryHeading.utilities
        }
    }

    var categories: [ExpenseCategory] {
        ExpenseCategory.selectableCases.filter { $0.heading == self }
    }
}

/// The server's closed category list. Raw values are the wire tokens and display text is
/// resolved separately, so changing a translation never changes stored data.
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case general
    case games, movies, music, sports
    case entertainmentOther = "entertainment_other"
    case diningOut = "dining_out"
    case groceries, liquor
    case foodOther = "food_other"
    case electronics, furniture
    case householdSupplies = "household_supplies"
    case maintenance, mortgage, pets, rent, services
    case homeOther = "home_other"
    case childcare, clothing, education, gifts, insurance, medical, taxes
    case lifeOther = "life_other"
    case bicycle
    case busTrain = "bus_train"
    case car
    case gasFuel = "gas_fuel"
    case hotel, parking, plane, taxi
    case transportationOther = "transportation_other"
    case cleaning, electricity
    case heatGas = "heat_gas"
    case trash
    case tvPhoneInternet = "tv_phone_internet"
    case water
    case utilitiesOther = "utilities_other"
    case payment

    var id: Self { self }

    var heading: ExpenseCategoryHeading? {
        switch self {
        case .general:
            .uncategorized
        case .games, .movies, .music, .sports, .entertainmentOther:
            .entertainment
        case .diningOut, .groceries, .liquor, .foodOther:
            .foodAndDrink
        case .electronics, .furniture, .householdSupplies, .maintenance, .mortgage,
             .pets, .rent, .services, .homeOther:
            .home
        case .childcare, .clothing, .education, .gifts, .insurance, .medical, .taxes, .lifeOther:
            .life
        case .bicycle, .busTrain, .car, .gasFuel, .hotel, .parking, .plane, .taxi,
             .transportationOther:
            .transportation
        case .cleaning, .electricity, .heatGas, .trash, .tvPhoneInternet, .water, .utilitiesOther:
            .utilities
        case .payment:
            nil
        }
    }

    var glyph: String {
        switch self {
        case .general: "dollarsign.circle.fill"
        case .games: "gamecontroller.fill"
        case .movies: "film.fill"
        case .music: "music.note"
        case .sports: "sportscourt.fill"
        case .entertainmentOther: "ticket.fill"
        case .diningOut: "fork.knife"
        case .groceries: "cart.fill"
        case .liquor: "wineglass.fill"
        case .foodOther: "cup.and.saucer.fill"
        case .electronics: "desktopcomputer"
        case .furniture: "chair.lounge.fill"
        case .householdSupplies: "basket.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .mortgage: "house.and.flag.fill"
        case .pets: "pawprint.fill"
        case .rent: "key.fill"
        case .services: "person.2.fill"
        case .homeOther: "house.fill"
        case .childcare: "stroller.fill"
        case .clothing: "tshirt.fill"
        case .education: "graduationcap.fill"
        case .gifts: "gift.fill"
        case .insurance: "shield.fill"
        case .medical: "cross.case.fill"
        case .taxes: "doc.text.fill"
        case .lifeOther: "heart.fill"
        case .bicycle: "bicycle"
        case .busTrain: "tram.fill"
        case .car: "car.fill"
        case .gasFuel: "fuelpump.fill"
        case .hotel: "bed.double.fill"
        case .parking: "parkingsign.circle.fill"
        case .plane: "airplane"
        case .taxi: "car.side.fill"
        case .transportationOther: "arrow.triangle.swap"
        case .cleaning: "sparkles"
        case .electricity: "bolt.fill"
        case .heatGas: "flame.fill"
        case .trash: "trash.fill"
        case .tvPhoneInternet: "wifi"
        case .water: "drop.fill"
        case .utilitiesOther: "wrench.adjustable.fill"
        case .payment: "arrow.left.arrow.right"
        }
    }

    var tint: Color {
        switch self {
        case .general:
            Color("category-uncategorized")
        case .games, .movies, .music, .sports, .entertainmentOther:
            Color("category-entertainment")
        case .diningOut, .groceries, .liquor, .foodOther:
            Color("category-food")
        case .electronics, .furniture, .householdSupplies, .maintenance, .mortgage,
             .pets, .rent, .services, .homeOther:
            Color("category-home")
        case .childcare, .clothing, .education, .gifts, .insurance, .medical, .taxes, .lifeOther:
            Color("category-life")
        case .bicycle, .busTrain, .car, .gasFuel, .hotel, .parking, .plane, .taxi,
             .transportationOther:
            Color("category-transportation")
        case .cleaning, .electricity, .heatGas, .trash, .tvPhoneInternet, .water, .utilitiesOther:
            Color("category-utilities")
        case .payment:
            .green
        }
    }

    var name: String {
        switch self {
        case .general: L10n.Category.general
        case .games: L10n.Category.games
        case .movies: L10n.Category.movies
        case .music: L10n.Category.music
        case .sports: L10n.Category.sports
        case .entertainmentOther: L10n.Category.entertainmentOther
        case .diningOut: L10n.Category.diningOut
        case .groceries: L10n.Category.groceries
        case .liquor: L10n.Category.liquor
        case .foodOther: L10n.Category.foodOther
        case .electronics: L10n.Category.electronics
        case .furniture: L10n.Category.furniture
        case .householdSupplies: L10n.Category.householdSupplies
        case .maintenance: L10n.Category.maintenance
        case .mortgage: L10n.Category.mortgage
        case .pets: L10n.Category.pets
        case .rent: L10n.Category.rent
        case .services: L10n.Category.services
        case .homeOther: L10n.Category.homeOther
        case .childcare: L10n.Category.childcare
        case .clothing: L10n.Category.clothing
        case .education: L10n.Category.education
        case .gifts: L10n.Category.gifts
        case .insurance: L10n.Category.insurance
        case .medical: L10n.Category.medical
        case .taxes: L10n.Category.taxes
        case .lifeOther: L10n.Category.lifeOther
        case .bicycle: L10n.Category.bicycle
        case .busTrain: L10n.Category.busTrain
        case .car: L10n.Category.car
        case .gasFuel: L10n.Category.gasFuel
        case .hotel: L10n.Category.hotel
        case .parking: L10n.Category.parking
        case .plane: L10n.Category.plane
        case .taxi: L10n.Category.taxi
        case .transportationOther: L10n.Category.transportationOther
        case .cleaning: L10n.Category.cleaning
        case .electricity: L10n.Category.electricity
        case .heatGas: L10n.Category.heatGas
        case .trash: L10n.Category.trash
        case .tvPhoneInternet: L10n.Category.tvPhoneInternet
        case .water: L10n.Category.water
        case .utilitiesOther: L10n.Category.utilitiesOther
        case .payment: L10n.Settlement.title
        }
    }

    static let selectableCases = allCases.filter { $0 != .payment }

    private static let defaultChipOrder: [ExpenseCategory] = [
        .groceries, .diningOut, .gasFuel, .taxi, .entertainmentOther
    ]

    /// Five quick picks based only on the timeline snapshot the client already has.
    static func chipSuggestions(
        from expenses: [Expense],
        selected: ExpenseCategory
    ) -> [ExpenseCategory] {
        let fixedOrder = allCases.filter { $0 != .general && $0 != .payment }
        let rank = Dictionary(uniqueKeysWithValues: fixedOrder.enumerated().map { ($0.element, $0.offset) })
        let counts = Dictionary(grouping: expenses.map(\.category).filter {
            $0 != .general && $0 != .payment
        }, by: { $0 }).mapValues(\.count)

        var suggestions = counts.keys.sorted {
            let firstCount = counts[$0, default: 0]
            let secondCount = counts[$1, default: 0]
            if firstCount != secondCount { return firstCount > secondCount }
            return rank[$0, default: .max] < rank[$1, default: .max]
        }

        for category in defaultChipOrder + fixedOrder where suggestions.count < 5 {
            if !suggestions.contains(category) { suggestions.append(category) }
        }
        suggestions = Array(suggestions.prefix(5))

        guard selected != .general, selected != .payment, !suggestions.contains(selected) else {
            return suggestions
        }
        return [selected] + suggestions.prefix(4)
    }
}
