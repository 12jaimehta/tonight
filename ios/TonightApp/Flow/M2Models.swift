import CaptureKit
import Foundation
import MarkingKit
import Observation
import ProfilesKit
import TaskKit

enum TodayPhase: Equatable {
    case ready
    case empty
    case loading
    case failed
}

enum TodayTaskState: Equatable {
    case todo
    case reading
    case marked(correct: Int, total: Int)
    case awaitingCheck
    case checked(stars: Int)
}

@MainActor
@Observable
final class TodayModel {
    var children: [ChildProfile] = []
    var selectedID: UUID?
    var tasks: [HomeworkTask] = []
    var statuses: [UUID: TodayTaskState] = [:]
    var marks: [UUID: Mark] = [:]
    var readingModes: [UUID: InputMode] = [:]
    var notebookAttempts: [NotebookAttempt] = []
    var parentChecks: [ParentCheck] = []
    var praises: [Praise] = []
    var phase: TodayPhase = .ready
    var weekCount = 0
    var selectedTaskID: UUID?

    var selected: ChildProfile? {
        children.first { $0.id == selectedID }
    }

    var visibleTasks: [HomeworkTask] {
        tasks.filter { $0.childID == selectedID }
    }

    func groups() -> [(subjectID: String, tasks: [HomeworkTask])] {
        guard let child = selected else { return [] }
        let order = child.subjects.filter { !$0.hidden }.sorted { $0.order < $1.order }.map(\.subjectID)
        return order.compactMap { id in
            let rows = visibleTasks.filter { $0.subjectID == id }
            return rows.isEmpty ? nil : (id, rows)
        }
    }

    func loadSample(for child: ChildProfile) {
        children = [child, TodayModel.meera]
        selectedID = child.id
        weekCount = 7
        phase = .ready
        let schoolClass = child.schoolClass ?? "1"
        let passage = TodayCopy.passage
        let english = HomeworkTask.make(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011") ?? UUID(),
            childID: child.id,
            subjectID: "english",
            schoolClass: schoolClass,
            instruction: "Read page 12: \"The Red Kite\"",
            checkMode: .auto,
            confirmedText: passage,
            pagePhotoRefs: [PhotoRef(relativePath: "pages/english.jpg")]
        )
        let maths = HomeworkTask.make(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012") ?? UUID(),
            childID: child.id,
            subjectID: "maths",
            schoolClass: schoolClass,
            instruction: "Sums on page 14",
            checkMode: .parent,
            pagePhotoRefs: [PhotoRef(relativePath: "pages/maths.jpg")]
        )
        let evs = HomeworkTask.make(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013") ?? UUID(),
            childID: child.id,
            subjectID: "evs",
            schoolClass: schoolClass,
            instruction: "Draw 3 animals that live in water",
            checkMode: .parent,
            pagePhotoRefs: [PhotoRef(relativePath: "pages/evs.jpg")]
        )
        var built: [HomeworkTask] = []
        if case .success(let task) = english {
            built.append(task)
            let mark = TodayCopy.sampleMark()
            statuses[task.id] = .marked(correct: mark.correct, total: mark.total)
            marks[task.id] = mark
            readingModes[task.id] = .spoken
        }
        if case .success(let task) = maths {
            built.append(task)
            statuses[task.id] = .awaitingCheck
        }
        if case .success(let task) = evs {
            built.append(task)
            statuses[task.id] = .todo
        }
        tasks = built
        if let maths = built.first(where: { $0.subjectID == "maths" }) {
            notebookAttempts = [
                NotebookAttempt(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000021") ?? UUID(),
                    taskID: maths.id,
                    at: Date(timeIntervalSince1970: 1_700_000_000),
                    workPhotoRef: PhotoRef(relativePath: "work/maths.jpg")
                )
            ]
        }
    }

    static let meera = ProfileRules.make(
        nickname: "Meera",
        schoolClass: "1",
        avatarID: "leaf",
        showMarkToChild: true,
        parentLabel: "Mummy",
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
    )

    static func previewPopulated() -> TodayModel {
        let model = TodayModel()
        let child = ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy")
        model.loadSample(for: child)
        return model
    }

    static func preview(phase: TodayPhase) -> TodayModel {
        let model = previewPopulated()
        model.phase = phase
        if phase == .empty {
            model.tasks = []
            model.weekCount = 0
        }
        return model
    }
}

enum TodayCopy {
    static let passage = "Ravi has a red kite. It flies over the roof and past the tall tree by the school every day."
    /// Drops the last two words so the stored mark is the same one the parent screen shows.
    static let heard = "Ravi has a red kite. It flies over the roof and past the tall tree by the school."

    static func sampleMark() -> Mark {
        Marker().mark(
            expected: passage,
            heard: heard,
            options: MarkerOptions(locale: "en-IN", asrEngine: "apple_on_device")
        )
    }
}

struct DraftLine: Identifiable, Equatable {
    var id: Int
    var text: String
    var included: Bool
    var uncertain: Bool
    var editing: Bool
}

/// Static stand-in for Vision. It still runs on the captured JPEG bytes.
struct PlaceholderOCR: OCREngine {
    var lines: [OCRLine]

    func lines(for image: CapturedPageImage) -> [OCRLine] {
        guard PageJPEG.isJPEG(image.bytes) else { return [] }
        return lines
    }

    func recognize(_ image: CapturedPageImage) async -> [OCRLine] {
        lines(for: image)
    }
}

enum MarkChoice: String, Equatable {
    case useDefault
    case show
    case hide
}

@MainActor
@Observable
final class NewTaskModel {
    var subjectID = ""
    var checkMode: CheckMode = .auto
    var instruction = ""
    var instructionEdited = false
    var pageAttached = false
    var cameraDenied = false
    var noEnglish = false
    var manualFallback = false
    var manualText = ""
    var lines: [DraftLine] = []
    var captured: CapturedPageImage?
    var pageRelativePath: String?
    var markChoice: MarkChoice = .useDefault
    var saving = false
    var editingLineID: Int?
    private(set) var typingEnabled = false
    let ocr: any OCREngine = PlaceholderOCR(lines: NewTaskModel.sampleOCRLines)

    static let sampleOCRLines: [OCRLine] = [
        OCRLine(text: "Ravi has a red kite."),
        OCRLine(text: "It flies over the roof.")
    ]

    var showMarkOverride: Bool? {
        switch markChoice {
        case .useDefault: return nil
        case .show: return true
        case .hide: return false
        }
    }

    /// Paste wins when the parent typed the passage. Otherwise the confirmed OCR lines are the passage.
    var passageKind: ContentSourceKind {
        let pasted = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
        if manualFallback || !pasted.isEmpty { return .paste }
        return .photo
    }

    var confirmedText: String {
        guard checkMode == .auto, let source = contentSource() else { return "" }
        return TaskContent.confirmedPassage(from: source) ?? ""
    }

    func contentSource() -> (any TaskContentSource)? {
        switch passageKind {
        case .photo:
            let ocr = lines.filter(\.included).map(\.text).joined(separator: "\n")
            return PhotoContentSource(ocrText: ocr)
        case .paste:
            return PasteContentSource(pastedText: manualText)
        case .template:
            return nil
        }
    }

    /// The parent already passed the gate. The child has no call that reaches this.
    func enableTyping(gateUnlocked: Bool) -> Bool {
        guard checkMode == .auto else { return false }
        guard TypingAccess.canEnable(editor: .parent, gateUnlocked: gateUnlocked) else { return false }
        typingEnabled = true
        return true
    }

    func revokeTyping() {
        typingEnabled = false
    }

    var wordCount: Int {
        confirmedText.split { $0.isWhitespace || $0.isNewline }.count
    }

    func issues() -> [HomeworkIssue] {
        HomeworkRules.issues(for: HomeworkDraft(
            subjectID: subjectID,
            checkMode: checkMode,
            confirmedText: checkMode == .auto ? confirmedText : "",
            photoCount: pageAttached ? 1 : 0,
            stars: nil
        ))
    }

    var canLeaveActivity: Bool { !subjectID.isEmpty }

    var canConfirmWords: Bool {
        checkMode == .auto && !confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSave: Bool { issues().isEmpty && !saving }

    var offersReadAloud: Bool {
        if subjectID.isEmpty { return true }
        return SubjectCatalog.record(subjectID)?.automaticCheckAllowed == true
    }

    func selectSubject(_ id: String) {
        subjectID = id
        let auto = SubjectCatalog.record(id)?.automaticCheckAllowed == true
        checkMode = auto ? .auto : .parent
        if !instructionEdited {
            instruction = auto ? "Read page 12 out loud" : "Do the sums on page 14 in your notebook."
        }
    }

    func selectMode(_ mode: CheckMode) {
        if mode == .auto && !offersReadAloud { return }
        checkMode = mode
        if !instructionEdited {
            instruction = mode == .auto ? "Read page 12 out loud" : "Do the sums on page 14 in your notebook."
        }
    }

    func attachSamplePage() {
        let relative = "pages/\(UUID().uuidString).jpg"
        let ref: PhotoRef
        do {
            ref = try AppPhotoFiles.writeJPEG(relativePath: relative)
        } catch {
            return
        }
        let image = CapturedPageImage(bytes: PageJPEG.bytes, capturedAt: Date())
        pageRelativePath = ref.relativePath
        captured = image
        pageAttached = true
        cameraDenied = false
        guard checkMode == .auto else { return }
        if noEnglish {
            lines = []
            manualFallback = true
            return
        }
        manualFallback = false
        manualText = ""
        applyPlaceholderOCR(image)
    }

    private func applyPlaceholderOCR(_ image: CapturedPageImage) {
        guard let placeholder = ocr as? PlaceholderOCR else { return }
        let recognized = placeholder.lines(for: image)
        lines = recognized.enumerated().map { index, line in
            DraftLine(id: index, text: line.text, included: true, uncertain: index == 1, editing: false)
        }
    }

    func rescan() {
        pageAttached = false
        pageRelativePath = nil
        captured = nil
        lines = []
        manualFallback = false
        manualText = ""
    }

    func makeTask(child: ChildProfile) -> HomeworkTask? {
        guard canSave else { return nil }
        let photos = pageRelativePath.map { [PhotoRef(relativePath: $0)] } ?? []
        let text = checkMode == .auto ? confirmedText : nil
        let result = HomeworkTask.make(
            childID: child.id,
            subjectID: subjectID,
            schoolClass: child.schoolClass ?? "1",
            instruction: instruction,
            checkMode: checkMode,
            confirmedText: text,
            pagePhotoRefs: photos,
            passageSource: checkMode == .auto ? passageKind : nil
        )
        guard case .success(var task) = result else { return nil }
        guard PhotoCapturePolicy.writesToPhotoLibrary == false else { return nil }
        task.showMarkOverride = showMarkOverride
        if typingEnabled, let allowed = task.settingTypingEnabled(true, editor: .parent, gateUnlocked: true) {
            task = allowed
        }
        return task
    }

    static func previewEnglish() -> NewTaskModel {
        let model = NewTaskModel()
        model.selectSubject("english")
        model.attachSamplePage()
        return model
    }

    static func previewMaths() -> NewTaskModel {
        let model = NewTaskModel()
        model.selectSubject("maths")
        return model
    }

    static func previewCameraOff() -> NewTaskModel {
        let model = previewMaths()
        model.cameraDenied = true
        return model
    }

    static func previewNoEnglish() -> NewTaskModel {
        let model = NewTaskModel()
        model.selectSubject("english")
        model.noEnglish = true
        model.attachSamplePage()
        return model
    }
}
