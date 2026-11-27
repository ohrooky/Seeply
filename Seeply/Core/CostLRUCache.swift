import Foundation

/// A strict cost budget, unlike NSCache's advisory totalCostLimit. Owned by an actor.
struct CostLRUCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
        var access: UInt64
    }
    let budget: Int
    private(set) var totalCost = 0
    private var clock: UInt64 = 0
    private var entries: [Key: Entry] = [:]
    var count: Int { entries.count }

    init(budget: Int) { self.budget = max(0, budget) }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.access = clock
        entries[key] = entry
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, cost: Int) {
        guard cost >= 0, cost <= budget else { return }
        if let previous = entries.removeValue(forKey: key) { totalCost -= previous.cost }
        while totalCost > budget - cost, let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: cost, access: clock)
        totalCost += cost
    }

    mutating func removeAll() {
        entries.removeAll()
        totalCost = 0
    }
}
