//
//  PlansViewModel.swift
//  Splitty
//

import Foundation

struct PlansDataSource {
    var recurringPlans: (Int) async throws -> [RecurringPlan]

    static let live = PlansDataSource(
        recurringPlans: { try await GroupService.shared.getRecurringPlans(groupId: $0) }
    )
}

/// Backs the Plans screen for one group. Each section loads on its own; Installments, the
/// group's active recurring expenses, is the first.
@MainActor
final class PlansViewModel: ObservableObject {
    enum InstallmentsState: Equatable {
        case loading
        case loaded([RecurringPlan])
        case empty
        case failed(String)
    }

    let groupId: Int

    @Published private(set) var installments: InstallmentsState = .loading

    private let dataSource: PlansDataSource
    /// A load that is no longer the newest publishes nothing.
    private var loadGeneration = 0

    init(groupId: Int, dataSource: PlansDataSource = .live) {
        self.groupId = groupId
        self.dataSource = dataSource
    }

    /// Loaded plans stay on screen while a reload is in flight, so a pull to refresh does
    /// not blank the list.
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        if case .loaded = installments {} else { installments = .loading }
        do {
            let plans = try await dataSource.recurringPlans(groupId)
            guard generation == loadGeneration else { return }
            installments = plans.isEmpty ? .empty : .loaded(plans)
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            installments = .failed(error.displayMessage)
        }
    }
}
