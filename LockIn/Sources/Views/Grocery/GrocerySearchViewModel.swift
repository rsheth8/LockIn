import Foundation

/// Drives the Shop Smart search: debounce, fetch, score, rank.
@MainActor
final class GrocerySearchViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case searching
        case results([ScoredGroceryItem])
        /// Searched, nothing came back worth showing.
        case empty(query: String)
        case failed(String)
    }

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published private(set) var state: State = .idle

    private let provider: GroceryProvider
    private var searchTask: Task<Void, Never>?

    /// Long enough that typing "greek yogurt" is one request rather than twelve,
    /// short enough not to feel laggy after the last keystroke.
    private let debounce = Duration.milliseconds(400)

    init(provider: GroceryProvider = OpenFoodFactsGroceryProvider()) {
        self.provider = provider
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: - Searching

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Two characters matches the floor `catalogSearch` enforces anyway;
        // below it there's nothing to show and no point spending a request.
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.debounce)
            } catch {
                // Cancelled by the next keystroke — the newer task owns the
                // state now, so this one must not touch it.
                return
            }

            self.state = .searching
            do {
                let items = try await self.provider.search(trimmed)
                guard !Task.isCancelled else { return }
                let ranked = Self.rank(items)
                self.state = ranked.isEmpty ? .empty(query: trimmed) : .results(ranked)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed("Couldn't reach the food database. Check your connection and try again.")
            }
        }
    }

    /// Re-runs the current query, for the retry button on a failure.
    func retry() {
        scheduleSearch()
    }

    // MARK: - Ranking
    //
    // Pure and static so the ordering rules can be tested without a network, a
    // debounce, or a main actor.

    nonisolated static func rank(_ items: [GroceryItem]) -> [ScoredGroceryItem] {
        // Open Food Facts holds a separate record per region and per pack size,
        // so one shelf item can arrive four times under the same name. Dedupe
        // on the name the user would read, keeping the first — the one the
        // search service ranked most relevant to the query.
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.name.lowercased()).inserted }

        return unique
            .map { ScoredGroceryItem(item: $0, score: SmartChoiceEngine.score($0)) }
            .sorted { left, right in
                // Anything judged on one or two stray numbers sorts below
                // everything that was judged properly, whatever it scored.
                // Otherwise a record carrying nothing but a NOVA 1 tag would
                // outrank a genuinely good product with a full panel.
                let leftThin = left.score.confidence == .thin
                let rightThin = right.score.confidence == .thin
                if leftThin != rightThin { return rightThin }
                if left.score.value != right.score.value { return left.score.value > right.score.value }
                // Stable, so equal scores don't reshuffle between redraws.
                return left.item.name < right.item.name
            }
    }
}
