import Foundation

/// An undoable, non-destructive editing session for the pure Cineo project
/// model. Only small manifest snapshots are stored: never video/audio bytes.
public struct CineoEditHistory: Sendable {
    public private(set) var current: CineoManifest
    private var undoStack: [CineoManifest] = []
    private var redoStack: [CineoManifest] = []
    /// Bound in-memory state to protect a long recording/editing session.
    public let capacity: Int

    public init(project: CineoManifest, capacity: Int = 100) throws {
        try project.validate()
        guard (1...1000).contains(capacity) else { throw EditHistoryError.invalidCapacity }
        self.current = project
        self.capacity = capacity
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoDepth: Int { undoStack.count }
    public var redoDepth: Int { redoStack.count }

    /// All-or-nothing edit. Invalid changes cannot corrupt current state,
    /// clear the redo chain or create a useless undo entry.
    public mutating func perform(_ action: CineoEditAction) throws {
        var candidate = current
        try action.apply(to: &candidate)
        try candidate.validate()
        guard candidate != current else { return }
        undoStack.append(current)
        if undoStack.count > capacity { undoStack.removeFirst() }
        current = candidate
        redoStack.removeAll(keepingCapacity: true)
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(current)
        current = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(current)
        if undoStack.count > capacity { undoStack.removeFirst() }
        current = next
        return true
    }
}

public enum EditHistoryError: Error, Equatable, Sendable {
    case invalidCapacity
    case invalidIndex
}

/// Declarative operations that do not touch source media or file bookmarks.
public enum CineoEditAction: Sendable {
    case insert(SourceEdit, at: Int)
    case replace(SourceEdit, at: Int)
    case remove(at: Int)
    case move(from: Int, to: Int)
    case setCanvas(Canvas)
    case rename(String)

    public func apply(to project: inout CineoManifest) throws {
        switch self {
        case .insert(let edit, let index):
            guard (0...project.edits.count).contains(index) else { throw EditHistoryError.invalidIndex }
            project.edits.insert(edit, at: index)
        case .replace(let edit, let index):
            guard project.edits.indices.contains(index) else { throw EditHistoryError.invalidIndex }
            project.edits[index] = edit
        case .remove(let index):
            guard project.edits.indices.contains(index) else { throw EditHistoryError.invalidIndex }
            project.edits.remove(at: index)
        case .move(let from, let to):
            guard project.edits.indices.contains(from),
                  project.edits.indices.contains(to) else { throw EditHistoryError.invalidIndex }
            let segment = project.edits.remove(at: from)
            project.edits.insert(segment, at: to)
        case .setCanvas(let canvas):
            project.canvas = canvas
        case .rename(let title):
            project.title = title
        }
    }
}
