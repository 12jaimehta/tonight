import Foundation
import MarkingKit
import Observation
import ProfilesKit
import SpeechKit
import TaskKit

enum ChildCardState: Equatable {
    case todo(count: Int, readAloud: Bool)
    case done
    case awaitingCheck
    case checked
    case resting
}

struct ChildHomeBoard {
    var child: ChildProfile
    var tasks: [HomeworkTask]
    var statuses: [UUID: TodayTaskState]
    var praises: [Praise]

    struct Card: Identifiable {
        var subject: ChildSubject
        var state: ChildCardState
        var task: HomeworkTask?
        var isNext: Bool
        var id: String { subject.subjectID }
    }

    var cards: [Card] {
        let visible = child.subjects.filter { !$0.hidden }.sorted { $0.order < $1.order }
        let nextID = nextTask?.id
        return visible.map { subject in
            let match = tasks.filter { $0.subjectID == subject.subjectID && $0.childID == child.id }
            let (state, task) = Self.state(for: match, statuses: statuses)
            return Card(subject: subject, state: state, task: task, isNext: task?.id == nextID)
        }
    }

    var nextTask: HomeworkTask? {
        let order = child.subjects.filter { !$0.hidden }.sorted { $0.order < $1.order }.map(\.subjectID)
        let open = tasks.filter { task in
            task.childID == child.id && isOpen(statuses[task.id] ?? .todo)
        }
        for id in order {
            if let task = open.first(where: { $0.subjectID == id }) { return task }
        }
        return nil
    }

    var awaitingTask: HomeworkTask? {
        tasks.first { task in
            task.childID == child.id && statuses[task.id] == .awaitingCheck
        }
    }

    var unseenPraise: Praise? {
        praises.first { $0.seenAt == nil }
    }

    var openCount: Int {
        tasks.filter { $0.childID == child.id && isOpen(statuses[$0.id] ?? .todo) }.count
    }

    var allDone: Bool {
        let mine = tasks.filter { $0.childID == child.id }
        return !mine.isEmpty && nextTask == nil && awaitingTask == nil
    }

    private func isOpen(_ state: TodayTaskState) -> Bool {
        switch state {
        case .todo, .reading: return true
        case .marked, .awaitingCheck, .checked: return false
        }
    }

    private static func state(for match: [HomeworkTask], statuses: [UUID: TodayTaskState]) -> (ChildCardState, HomeworkTask?) {
        guard let first = match.first else { return (.resting, nil) }
        if let waiting = match.first(where: { statuses[$0.id] == .awaitingCheck }) {
            return (.awaitingCheck, waiting)
        }
        let todos = match.filter { isTodo(statuses[$0.id] ?? .todo) }
        if let todo = todos.first {
            return (.todo(count: todos.count, readAloud: todo.checkMode == .auto), todo)
        }
        if match.contains(where: { if case .checked = statuses[$0.id] { return true }; return false }) {
            return (.checked, first)
        }
        return (.done, first)
    }

    private static func isTodo(_ state: TodayTaskState) -> Bool {
        switch state {
        case .todo, .reading: return true
        default: return false
        }
    }
}

enum ReadPhase: Equatable {
    case idle
    case hearing
    case recording
    case micOff
    case unavailable
}

@MainActor
@Observable
final class ReadAloudSession {
    var taskID: UUID
    var phase: ReadPhase
    var started = false
    var mark: Mark?
    var unavailableReason: String?
    var hearingWord: String?
    let micDenied: Bool
    let engine: FakeSpeechEngine

    init(task: HomeworkTask, micDenied: Bool = false, speechUnavailable: Bool = false) {
        taskID = task.id
        self.micDenied = micDenied
        if speechUnavailable {
            phase = .unavailable
            unavailableReason = "Reading marks need a newer iPhone. Make this a Notebook task instead."
            engine = FakeSpeechEngine(scripted: .unavailable("On-device recognition is unavailable"))
        } else if micDenied {
            phase = .micOff
            engine = FakeSpeechEngine(scripted: .unavailable("Microphone or speech permission was denied"))
        } else {
            phase = .idle
            let result = SpeechRecognitionResult(
                transcript: TodayCopy.heard,
                words: [],
                engineID: .fake
            )
            engine = FakeSpeechEngine(scripted: .transcript(result))
        }
    }

    func hear() {
        guard phase != .recording else { return }
        phase = phase == .hearing ? .idle : .hearing
    }

    func read() {
        if micDenied || phase == .micOff {
            phase = .micOff
            return
        }
        if phase == .unavailable { return }
        phase = .recording
        started = true
    }

    func pause() {
        guard phase == .recording else { return }
        phase = .idle
    }

    func finish(expected: String) async {
        let outcome = await engine.transcribe(audio: SpeechAudio(samples: Data()), locale: OnDeviceRequestPolicy.localeIdentifier)
        switch outcome {
        case .unavailable(let reason):
            unavailableReason = reason
            phase = .unavailable
        case .transcript(let result):
            let activity = ReadAloudActivity()
            mark = activity.score(attempt: ActivityAttempt(expectedText: expected, heardText: result.transcript))
            phase = .idle
        }
    }

    static func preview(phase: ReadPhase) -> ReadAloudSession {
        let task = HomeworkTask.make(
            childID: UUID(),
            subjectID: "english",
            schoolClass: "1",
            instruction: "Read page 12 out loud",
            checkMode: .auto,
            confirmedText: TodayCopy.passage
        )
        let session: ReadAloudSession
        if case .success(let made) = task {
            session = ReadAloudSession(task: made, micDenied: phase == .micOff, speechUnavailable: phase == .unavailable)
        } else {
            session = ReadAloudSession(task: HomeworkTask(
                id: UUID(),
                childID: UUID(),
                subjectID: "english",
                schoolClass: "1",
                instruction: "Read",
                checkMode: .auto,
                confirmedText: TodayCopy.passage,
                pagePhotoRefs: [],
                media: [],
                showMarkOverride: nil,
                stars: nil,
                createdAt: Date()
            ))
        }
        session.phase = phase
        session.started = phase == .recording
        return session
    }
}

enum NotebookPhase: Equatable {
    case instruction
    case camera
    case confirm
    case denied
    case blurry
}

@MainActor
@Observable
final class NotebookSession {
    var taskID: UUID
    var phase: NotebookPhase
    var workPhoto: PhotoRef?

    init(task: HomeworkTask, denied: Bool = false) {
        taskID = task.id
        phase = denied ? .denied : .instruction
    }

    func shutter() {
        let relative = "work/\(taskID.uuidString).jpg"
        guard let ref = try? AppPhotoFiles.writeJPEG(relativePath: relative) else { return }
        workPhoto = ref
        phase = .confirm
    }

    static func preview(_ phase: NotebookPhase) -> NotebookSession {
        let task = HomeworkTask(
            id: UUID(),
            childID: UUID(),
            subjectID: "maths",
            schoolClass: "1",
            instruction: "Do the sums on page 14 in your notebook.",
            checkMode: .parent,
            confirmedText: nil,
            pagePhotoRefs: [PhotoRef(relativePath: "pages/maths.jpg")],
            media: [],
            showMarkOverride: nil,
            stars: nil,
            createdAt: Date()
        )
        let session = NotebookSession(task: task, denied: phase == .denied)
        session.phase = phase
        if phase == .confirm || phase == .blurry {
            session.workPhoto = PhotoRef(relativePath: "work/preview.jpg")
        }
        return session
    }
}

@MainActor
@Observable
final class PraiseDraft {
    var presetID: String?
    var custom = ""
    var writing = false
    var sent = false
    var stars: Int?

    var phrase: String? {
        let typed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return String(typed.prefix(40)) }
        guard let presetID else { return nil }
        return PraisePresets.phrase(id: presetID)
    }

    var lang: String {
        PraisePresets.v1.first { $0.id == presetID }?.lang ?? "en"
    }

    func makePraise(taskID: UUID, attemptID: UUID?) -> Praise? {
        guard let phrase else { return nil }
        let typed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return Praise(
            taskID: taskID,
            attemptID: attemptID,
            presetID: presetID ?? "",
            text: typed.isEmpty ? nil : String(typed.prefix(40)),
            lang: lang
        )
    }
}

enum GatePurpose: Equatable {
    case exitChild
    case settings
    case parentCheck
}
