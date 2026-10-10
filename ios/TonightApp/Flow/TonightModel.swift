import AuthKit
import Foundation
import MarkingKit
import Observation
import ProfilesKit
import SpeechKit
import TaskKit

enum TonightRoute: Equatable {
    case signIn
    case consent
    case addChild
    case subjects
    case childHome
    case today
    case newTask
    case addPage
    case checkWords
    case review
    case readAloud
    case childResult
    case notebook
    case parentChecksChild
    case parentResult
    case parentCheck
    case praise

    init?(argument: String) {
        switch argument {
        case "signIn": self = .signIn
        case "consent": self = .consent
        case "addChild": self = .addChild
        case "subjects": self = .subjects
        case "child": self = .childHome
        case "today", "parent": self = .today
        case "newTask": self = .newTask
        default: return nil
        }
    }
}

@MainActor
@Observable
final class SignInModel {
    enum Phase: Equatable {
        case welcome
        case code
        case codeError
        case offline
        case loading
    }

    var phase: Phase = .welcome
    var email = "parent@example.com"
    var code = ""
    var offline = false

    var digitCount: Int { code.filter(\.isNumber).count }

    var canVerify: Bool {
        digitCount == 6 && !offline && phase != .loading
    }

    func continueWithEmail() {
        phase = offline ? .offline : .code
    }

    /// Placeholder check. No network. `000000` is the static error state.
    func verify() -> Bool {
        guard canVerify else { return false }
        if code == "000000" {
            phase = .codeError
            return false
        }
        phase = .loading
        return true
    }

    func clampCode() {
        let digits = String(code.filter(\.isNumber).prefix(6))
        if digits != code { code = digits }
    }

    static func preview(phase: Phase, code: String = "", offline: Bool = false) -> SignInModel {
        let model = SignInModel()
        model.phase = phase
        model.code = code
        model.offline = offline
        return model
    }
}

@MainActor
@Observable
final class ConsentModel {
    var accepted = false
    var saving = false
    var error: String?
    var showingPrivacy = false

    var canContinue: Bool { accepted && !saving }

    func toggleAccepted() {
        accepted.toggle()
        error = nil
    }

    static func preview(accepted: Bool, error: String? = nil) -> ConsentModel {
        let model = ConsentModel()
        model.accepted = accepted
        model.error = error
        return model
    }
}

@MainActor
@Observable
final class AddChildModel {
    var nickname = ""
    var schoolClass = AudienceConfig.v1.classes[0]
    var avatarID = AvatarPresets.ids[0]
    var parentChoice = "Mummy"
    var customParentLabel = ""
    var showMarkToChild = true
    var touchedNickname = false

    var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nicknameError: String? {
        guard touchedNickname else { return nil }
        if trimmedNickname.isEmpty || trimmedNickname.count > 16 {
            return "Use a short nickname, up to 16 letters."
        }
        return nil
    }

    var resolvedParentLabel: String {
        if parentChoice == "Other" {
            return customParentLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parentChoice
    }

    var canContinue: Bool {
        !trimmedNickname.isEmpty
            && trimmedNickname.count <= 16
            && !resolvedParentLabel.isEmpty
            && resolvedParentLabel.count <= 16
            && AvatarPresets.ids.contains(avatarID)
            && AudienceConfig.v1.classes.contains(schoolClass)
    }

    func makeProfile(id: UUID = UUID()) -> ChildProfile? {
        touchedNickname = true
        guard canContinue else { return nil }
        return ProfileRules.make(
            nickname: trimmedNickname,
            schoolClass: schoolClass,
            avatarID: avatarID,
            showMarkToChild: showMarkToChild,
            parentLabel: resolvedParentLabel,
            id: id
        )
    }

    static func preview(nickname: String, schoolClass: String = "1", touched: Bool = false) -> AddChildModel {
        let model = AddChildModel()
        model.nickname = nickname
        model.schoolClass = schoolClass
        model.touchedNickname = touched
        return model
    }
}

@MainActor
@Observable
final class SubjectsEditor {
    var child: ChildProfile
    var notice = ""
    var showAllOptional = false
    var renamingID: String?

    var renameText = ""

    init(child: ChildProfile) {
        self.child = child
    }

    var ordered: [ChildSubject] {
        child.subjects.sorted { $0.order < $1.order }
    }

    var orderLabel: String {
        ordered.map(\.subjectID).joined(separator: ", ")
    }

    var optionalIDs: [String] {
        let taken = Set(SubjectCatalog.classDefaultIDs)
        return SubjectCatalog.all.map(\.id).filter { !taken.contains($0) }
    }

    var visibleOptionalIDs: [String] {
        showAllOptional ? optionalIDs : Array(optionalIDs.prefix(6))
    }

    func hide(_ subjectID: String) {
        let wasVisible = child.subjects.contains { $0.subjectID == subjectID && !$0.hidden }
        let visibleCount = child.subjects.filter { !$0.hidden }.count
        child.setSubjectHidden(subjectID, true)
        let stillVisible = child.subjects.contains { $0.subjectID == subjectID && !$0.hidden }
        if wasVisible && stillVisible && visibleCount <= 1 {
            notice = "Keep at least one subject."
        } else {
            notice = ""
        }
    }

    func show(_ subjectID: String) {
        child.setSubjectHidden(subjectID, false)
        notice = ""
    }

    func toggleHidden(_ subjectID: String) {
        let row = child.subjects.first { $0.subjectID == subjectID }
        if row?.hidden == true {
            show(subjectID)
        } else {
            hide(subjectID)
        }
    }

    func move(_ subjectID: String, by delta: Int) {
        var ids = ordered.map(\.subjectID)
        guard let index = ids.firstIndex(of: subjectID) else { return }
        let target = index + delta
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        child.reorderSubjects(ids)
        notice = ""
    }

    /// Drag-handle drop. Swaps two rows and never removes a subject, including the last visible one.
    @discardableResult
    func move(_ subjectID: String, onto targetID: String) -> Bool {
        guard subjectID != targetID else { return false }
        var ids = ordered.map(\.subjectID)
        guard let from = ids.firstIndex(of: subjectID), let to = ids.firstIndex(of: targetID) else { return false }
        let visible = child.subjects.filter { !$0.hidden }.map(\.subjectID)
        guard !visible.isEmpty, visible.allSatisfy({ ids.contains($0) }) else { return false }
        ids.swapAt(from, to)
        child.reorderSubjects(ids)
        let stillVisible = child.subjects.filter { !$0.hidden }.map(\.subjectID)
        guard Set(stillVisible) == Set(visible) else { return false }
        notice = ""
        return true
    }

    func toggleOptional(_ subjectID: String) {
        if child.subjects.contains(where: { $0.subjectID == subjectID }) {
            let visible = child.subjects.filter { !$0.hidden }
            let row = child.subjects.first { $0.subjectID == subjectID }
            if visible.count <= 1, row?.hidden == false {
                notice = "Keep at least one subject."
                return
            }
            child.subjects.removeAll { $0.subjectID == subjectID }
            child.reorderSubjects(ordered.map(\.subjectID))
            notice = ""
        } else {
            let order = (child.subjects.map(\.order).max() ?? -1) + 1
            child.subjects.append(ChildSubject(subjectID: subjectID, order: order))
            notice = ""
        }
    }

    func beginRename(_ subjectID: String) {
        renamingID = subjectID
        let row = child.subjects.first { $0.subjectID == subjectID }
        renameText = row?.displayName ?? ""
    }

    func saveRename() {
        guard let renamingID else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nil : String(trimmed.prefix(16))
        child.renameSubject(renamingID, to: name)
        self.renamingID = nil
        renameText = ""
    }

    func resetRename() {
        renameText = ""
    }

    static func preview() -> SubjectsEditor {
        SubjectsEditor(child: ProfileRules.make(nickname: "Aarav", schoolClass: "2", showMarkToChild: true, parentLabel: "Mummy"))
    }

    static func previewRename() -> SubjectsEditor {
        let editor = preview()
        editor.beginRename("evs")
        editor.renameText = "Our World"
        return editor
    }
}

@MainActor
@Observable
final class GateModel {
    static let digitCount = ParentalGateBank.digitCount

    var session: ParentalGateSession
    var answer = ""
    var offset = 0
    var notice = ""
    var presented = false
    let fixed: Bool
    private let defaults: UserDefaults
    private(set) var challenge: GateChallenge

    init(fixed: Bool, defaults: UserDefaults = .standard) {
        self.fixed = fixed
        self.defaults = defaults
        session = ParentalGateSession(lockoutRecord: ParentalGateLockout.load(from: defaults))
        challenge = ParentalGateBank.challenge(fixed: fixed, offset: 0)
    }

    var isLocked: Bool { session.isLocked(at: Date()) }

    /// Each presentation of the real gate draws a new spelled number. The fixed UI-test gate stays on 347.
    func preparePresentation() {
        if fixed {
            challenge = ParentalGateBank.challenge(fixed: true)
            return
        }
        var generator = SystemRandomNumberGenerator()
        challenge = ParentalGateBank.randomChallenge(using: &generator)
    }

    func press(_ key: String) -> GateVerdict? {
        if isLocked {
            return .locked
        }
        if key == "delete" {
            if !answer.isEmpty { answer.removeLast() }
            return nil
        }
        guard answer.count < Self.digitCount else { return nil }
        answer.append(contentsOf: key.filter(\.isNumber).prefix(1))
        if answer.count == Self.digitCount {
            return submit()
        }
        return nil
    }

    func submit() -> GateVerdict {
        let verdict = session.submit(answer: answer, to: challenge, now: Date())
        session.lockoutRecord.save(to: defaults)
        switch verdict {
        case .unlocked:
            notice = ""
            answer = ""
        case .incorrect:
            notice = "Let's try a different one."
            answer = ""
            if !fixed {
                offset += 1
                challenge = ParentalGateBank.challenge(fixed: false, offset: offset)
            }
        case .locked:
            notice = ""
            answer = ""
        }
        return verdict
    }

    func resetForBackground() {
        session.resetForBackground()
        session.lockoutRecord.save(to: defaults)
        answer = ""
        notice = ""
        presented = false
    }

    static func preview(answer: String) -> GateModel {
        let gate = GateModel(fixed: true)
        gate.presented = true
        gate.answer = answer
        return gate
    }

    static func previewLocked() -> GateModel {
        let gate = GateModel(fixed: true)
        gate.presented = true
        gate.notice = "Let's try a different one."
        var session = ParentalGateSession()
        let challenge = ParentalGateBank.challenge(fixed: true)
        _ = session.submit(answer: "1", to: challenge, now: Date())
        _ = session.submit(answer: "1", to: challenge, now: Date())
        gate.session = session
        return gate
    }
}

@MainActor
@Observable
final class TonightModel {
    var route: TonightRoute
    var signIn = SignInModel()
    var consent = ConsentModel()
    var addChild = AddChildModel()
    var child: ChildProfile?
    var editor: SubjectsEditor?
    var today = TodayModel()
    var draft = NewTaskModel()
    var readAloud: ReadAloudSession?
    var notebook: NotebookSession?
    var praiseDraft = PraiseDraft()
    var gatePurpose: GatePurpose = .exitChild
    var gate: GateModel
    var authMethod = "email"
    var showingWithdrawal = false
    var confirmingWithdrawal = false
    var withdrawalNotice = ""
    var withdrawalHasConsent = false
    var withdrawalLocal = ""
    var withdrawalEpoch = 0
    let consentStore = InMemoryAdultConsentStore()
    let consentCenter: ConsentCenter?
    var serverWithdrawal: ServerWithdrawalClient?
    var serverConsentID: UUID?
    let emailOTP: EmailOTPClient?
    let sessionStore: any ParentSessionStoring
    let speech: any SpeechSynthesizing

    init(
        sessionStore: any ParentSessionStoring = KeychainSessionStore(),
        speech: any SpeechSynthesizing = IndianEnglishSpeech(),
        consentCenter: ConsentCenter? = nil,
        serverWithdrawal: ServerWithdrawalClient? = nil,
        emailOTP: EmailOTPClient? = nil
    ) {
        self.sessionStore = sessionStore
        self.speech = speech
        self.consentCenter = consentCenter
        self.serverWithdrawal = serverWithdrawal
        self.emailOTP = emailOTP
        let arguments = ProcessInfo.processInfo.arguments
        gate = GateModel(fixed: arguments.contains("-TonightFixedGate"))
        if let index = arguments.firstIndex(of: "-TonightScreen"), arguments.indices.contains(arguments.index(after: index)) {
            let name = arguments[arguments.index(after: index)]
            route = TonightRoute(argument: name) ?? .signIn
        } else {
            route = .signIn
        }
        if arguments.contains("-TonightOffline") {
            signIn.offline = true
            signIn.phase = .offline
        }
        switch route {
        case .subjects, .childHome:
            installFixtureChild()
        case .today:
            installFixtureChild()
            if let child {
                today.loadSample(for: child)
            }
            applyTodayPhase(arguments)
        case .newTask:
            installFixtureChild()
            ensureToday()
            if arguments.contains("-TonightCameraDenied") {
                draft.cameraDenied = true
            }
            if arguments.contains("-TonightNoEnglish") {
                draft.noEnglish = true
            }
        case .signIn, .consent, .addChild, .addPage, .checkWords, .review, .readAloud, .childResult, .notebook, .parentChecksChild, .parentResult, .parentCheck, .praise:
            break
        }
        if arguments.contains("-TonightSeedConsent") || arguments.contains("-TonightSeedLocalData") {
            seedLocalConsent()
        }
        if arguments.contains("-TonightSeedLocalData") {
            seedLocalChildData()
        }
    }

    private func seedLocalChildData() {
        guard let child, let consentCenter else { return }
        let ledger = consentCenter.ledger
        if ledger.rememberWords(childProfileID: child.id).isEmpty {
            try? ledger.addRememberWord("kite", childProfileID: child.id)
        }
        if ledger.markCorrections(childProfileID: child.id).isEmpty {
            try? ledger.addMarkCorrection("star", childProfileID: child.id)
        }
        if ledger.liveArtefacts(childProfileID: child.id).isEmpty {
            if (try? ledger.storeAudio(Data([1, 2, 3]), childProfileID: child.id, serverPath: false)) == nil {
                _ = try? ledger.storeText("clip", childProfileID: child.id, kind: .audio, serverPath: false)
            }
        }
    }

    private func activeConsent(for childID: UUID) -> AudioConsentRecord? {
        guard let record = consentCenter?.record(for: childID), record.withdrawnAt == nil else { return nil }
        return record
    }

    private func localInventory(_ childID: UUID) -> String {
        guard let consentCenter else { return "remember 0 marks 0 audio 0" }
        let words = consentCenter.ledger.rememberWords(childProfileID: childID).count
        let marks = consentCenter.ledger.markCorrections(childProfileID: childID).count
        let audio = consentCenter.ledger.liveArtefacts(childProfileID: childID).count
        return "remember \(words) marks \(marks) audio \(audio)"
    }

    private func seedLocalConsent() {
        guard let child, let consentCenter else { return }
        let parentID = (try? sessionStore.load())?.parentID ?? "parent"
        try? consentCenter.grant(AudioConsentRecord(
            parentID: parentID,
            childProfileID: child.id,
            scopes: [.onDevice],
            tappedAt: Date(),
            method: "screen",
            backendConfirmed: true
        ))
    }

    private func applyTodayPhase(_ arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-TonightToday"),
              arguments.indices.contains(arguments.index(after: index)) else { return }
        switch arguments[arguments.index(after: index)] {
        case "empty":
            today.tasks = []
            today.statuses = [:]
            today.weekCount = 0
            today.phase = .empty
        case "loading":
            today.phase = .loading
        case "error":
            today.phase = .failed
        default:
            break
        }
    }

    func installFixtureChild() {
        let profile = ProfileRules.make(
            nickname: "Aarav",
            schoolClass: "1",
            avatarID: "sun",
            showMarkToChild: true,
            parentLabel: "Mummy",
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        )
        child = profile
        editor = SubjectsEditor(child: profile)
        addChild.nickname = profile.nickname
        addChild.schoolClass = profile.schoolClass ?? "1"
        addChild.parentChoice = profile.parentLabel
        addChild.showMarkToChild = profile.showMarkToChild
        addChild.avatarID = profile.avatarID
    }

    func continueFromApple() {
        finishSignIn(method: "apple")
    }

    func continueFromEmail() {
        signIn.continueWithEmail()
    }

    func verifyEmailCode() {
        guard signIn.verify() else { return }
        guard let emailOTP else {
            finishSignIn(method: "email")
            return
        }
        let email = signIn.email
        let code = signIn.code
        Task { @MainActor in
            do {
                let session = try await emailOTP.verify(email: email, code: code)
                if let parent = UUID(uuidString: session.parentID) {
                    _ = await serverWithdrawal?.createParent(id: parent)
                }
                authMethod = "email"
                route = .consent
            } catch {
                signIn.phase = .codeError
            }
        }
    }

    func finishSignIn(method: String) {
        authMethod = method
        route = .consent
    }

    func agreeToConsent() {
        guard consent.canContinue else { return }
        consent.saving = true
        let parentID = (try? sessionStore.load())?.parentID ?? ""
        let record = AdultConsentRecord(
            parentID: parentID,
            acceptedAt: Date(),
            method: authMethod
        )
        consentStore.save(record)
        consent.saving = false
        route = .addChild
    }

    func continueToSubjects() {
        guard let profile = addChild.makeProfile() else { return }
        child = profile
        editor = SubjectsEditor(child: profile)
        route = .subjects
        Task { await publishChild(profile) }
    }

    private func publishChild(_ profile: ChildProfile) async {
        guard let serverWithdrawal,
              let parent = UUID(uuidString: (try? sessionStore.load())?.parentID ?? "") else { return }
        _ = await serverWithdrawal.createChild(
            id: profile.id,
            parentID: parent,
            nickname: profile.nickname,
            schoolClass: profile.schoolClass ?? "1"
        )
        let consentID = UUID()
        serverConsentID = consentID
        _ = await serverWithdrawal.createConsent(id: consentID, parentID: parent, childID: profile.id)
        try? consentCenter?.grant(AudioConsentRecord(
            id: consentID,
            parentID: parent.uuidString.lowercased(),
            childProfileID: profile.id,
            scopes: [.onDevice],
            tappedAt: Date(),
            method: "screen",
            backendConfirmed: true
        ))
    }

    func finishSubjects() {
        if let editor {
            child = editor.child
        }
        ensureToday()
        route = .today
    }

    func ensureToday() {
        guard let child else { return }
        if today.children.contains(where: { $0.id == child.id }) == false {
            today.children.append(child)
        } else if let index = today.children.firstIndex(where: { $0.id == child.id }) {
            today.children[index] = child
        }
        if today.selectedID == nil {
            today.selectedID = child.id
        }
    }

    func startNewTask() {
        draft = NewTaskModel()
        route = .newTask
    }

    func closeDraft() {
        draft = NewTaskModel()
        route = .today
    }

    func nextFromActivity() {
        guard draft.canLeaveActivity else { return }
        route = .addPage
    }

    func nextFromPage() {
        route = draft.checkMode == .auto ? .checkWords : .review
    }

    func typeInstead() {
        draft.manualFallback = true
        draft.lines = []
        route = .checkWords
    }

    func confirmWords() {
        guard draft.canConfirmWords else { return }
        route = .review
    }

    func makeNotebook() {
        draft.checkMode = .parent
        draft.manualFallback = false
        draft.revokeTyping()
        route = .review
    }

    /// Opens the parental gate. The flag flips only after the gate unlocks.
    func allowTyping() {
        guard draft.checkMode == .auto, !draft.typingEnabled else { return }
        openGate(for: .enableTyping)
    }

    func backFromPage() {
        route = .newTask
    }

    func backFromWords() {
        route = .addPage
    }

    func backFromReview() {
        route = draft.checkMode == .auto ? .checkWords : .addPage
    }

    func saveDraft(handOff: Bool) {
        guard let child = today.selected ?? self.child else { return }
        guard let task = draft.makeTask(child: child) else { return }
        draft.saving = true
        today.tasks.append(task)
        today.statuses[task.id] = .todo
        today.phase = .ready
        if today.children.isEmpty {
            today.children = [child]
            today.selectedID = child.id
        }
        draft = NewTaskModel()
        route = handOff ? .childHome : .today
    }

    func openGate() {
        openGate(for: gatePurpose)
    }

    func openGate(for purpose: GatePurpose) {
        gatePurpose = purpose
        if gate.isLocked {
            gate.presented = false
            return
        }
        gate.preparePresentation()
        gate.presented = true
    }

    func closeGate() {
        gate.presented = false
        gate.answer = ""
    }

    func pressGate(_ key: String) {
        guard let verdict = gate.press(key) else { return }
        switch verdict {
        case .unlocked:
            gate.presented = false
            ensureToday()
            switch gatePurpose {
            case .exitChild:
                if route == .childHome {
                    route = .today
                }
            case .settings:
                route = .today
                confirmingWithdrawal = false
                withdrawalNotice = ""
                let childID = child?.id ?? today.selected?.id
                withdrawalHasConsent = childID.flatMap { activeConsent(for: $0) } != nil
                withdrawalLocal = childID.map(localInventory) ?? ""
                showingWithdrawal = true
            case .parentCheck:
                route = .parentCheck
            case .enableTyping:
                _ = draft.enableTyping(gateUnlocked: true)
            }
        case .locked:
            gate.presented = false
        case .incorrect:
            break
        }
    }

    func backgrounded() {
        gate.resetForBackground()
    }

    func refreshWithdrawalQueue() async {
        if let emailOTP {
            _ = try? await emailOTP.refreshSession()
        }
        _ = await serverWithdrawal?.flush()
    }

    func askWithdrawal() {
        confirmingWithdrawal = true
    }

    func cancelWithdrawal() {
        showingWithdrawal = false
        confirmingWithdrawal = false
    }

    /// Clears the adult consent record, withdraws the child in the consent store, and flushes the deletion queue.
    func confirmWithdrawal() async {
        let childID = child?.id ?? today.selected?.id
        consentStore.clear()
        guard let childID else {
            withdrawalNotice = "No child to withdraw."
            return
        }
        guard let consentCenter else {
            withdrawalNotice = "Consent store is not configured."
            return
        }
        do {
            guard let existing = activeConsent(for: childID) else {
                withdrawalHasConsent = false
                withdrawalNotice = "No consent on file"
                return
            }
            let consentID = serverConsentID ?? existing.id
            _ = try await consentCenter.withdraw(childProfileID: childID, at: Date())
            await serverWithdrawal?.submit(childID: childID, consentRecordID: consentID)
            withdrawalLocal = localInventory(childID)
            withdrawalNotice = "Consent withdrawn"
            confirmingWithdrawal = false
            withdrawalEpoch += 1
        } catch {
            withdrawalNotice = "Couldn't withdraw consent."
        }
    }

    func openTask(_ id: UUID) {
        today.selectedTaskID = id
        guard let task = today.tasks.first(where: { $0.id == id }) else { return }
        praiseDraft = PraiseDraft()
        switch today.statuses[id] ?? .todo {
        case .marked:
            route = .parentResult
        case .awaitingCheck, .checked:
            route = task.checkMode == .parent ? .parentCheck : .parentResult
        case .todo, .reading:
            break
        }
    }

    func openChildTask(_ task: HomeworkTask) {
        if today.statuses[task.id] == .awaitingCheck {
            today.selectedTaskID = task.id
            route = .parentChecksChild
            return
        }
        let denied = ProcessInfo.processInfo.arguments.contains("-TonightMicDenied")
        let unavailable = ProcessInfo.processInfo.arguments.contains("-TonightSpeechUnavailable")
        if task.checkMode == .auto {
            readAloud = ReadAloudSession(task: task, micDenied: denied, speechUnavailable: unavailable, speech: speech)
            route = .readAloud
        } else {
            let cameraDenied = ProcessInfo.processInfo.arguments.contains("-TonightCameraDenied")
            notebook = NotebookSession(task: task, denied: cameraDenied)
            route = .notebook
        }
    }

    func finishReading() async {
        guard let session = readAloud, let task = task(session.taskID) else { return }
        await session.finish(expected: task.confirmedText ?? "")
        guard let mark = session.mark else { return }
        today.marks[task.id] = mark
        today.readingModes[task.id] = session.inputMode
        today.statuses[task.id] = .marked(correct: mark.correct, total: mark.total)
        route = .childResult
    }

    func sendNotebook() {
        guard let session = notebook, let photo = session.workPhoto, task(session.taskID) != nil else { return }
        let attempt = NotebookAttempt(taskID: session.taskID, workPhotoRef: photo)
        today.notebookAttempts.append(attempt)
        today.statuses[session.taskID] = .awaitingCheck
        today.selectedTaskID = session.taskID
        route = .parentChecksChild
    }

    func sendParentCheck() {
        guard let task = parentTask, let stars = praiseDraft.stars else { return }
        let attempt = today.notebookAttempts.first { $0.taskID == task.id }
        guard let check = ParentCheck(attemptID: attempt?.id ?? UUID(), stars: stars) else { return }
        today.parentChecks.append(check)
        today.statuses[task.id] = .checked(stars: stars)
        if var stored = today.tasks.first(where: { $0.id == task.id }),
           let index = today.tasks.firstIndex(where: { $0.id == task.id }) {
            stored.stars = stars
            today.tasks[index] = stored
        }
        if let praise = praiseDraft.makePraise(taskID: task.id, attemptID: attempt?.id) {
            today.praises.append(praise)
        }
        praiseDraft.sent = true
    }

    func sendEnglishPraise() {
        guard let task = parentTask else { return }
        if let praise = praiseDraft.makePraise(taskID: task.id, attemptID: nil) {
            today.praises.append(praise)
        }
        praiseDraft.sent = true
    }

    func hearPraise(_ praise: Praise) {
        let text = praise.text ?? praise.presetPhrase ?? ""
        let speaker = speech
        Task { await SpokenCue.passage(text, using: speaker) }
    }

    func thankPraise(_ praise: Praise) {
        guard let index = today.praises.firstIndex(where: { $0.id == praise.id }) else { return }
        today.praises[index].seenAt = Date()
        route = .childHome
    }

    func task(_ id: UUID) -> HomeworkTask? {
        today.tasks.first { $0.id == id }
    }

    var parentTask: HomeworkTask? {
        guard let id = today.selectedTaskID else { return nil }
        return task(id)
    }

    func setMarkShown(_ shown: Bool) {
        guard let id = today.selectedTaskID, let index = today.tasks.firstIndex(where: { $0.id == id }) else { return }
        today.tasks[index].showMarkOverride = shown
    }

    func markVisible(for task: HomeworkTask) -> Bool {
        MarkVisibility.shownToChild(taskOverride: task.showMarkOverride, childDefault: child?.showMarkToChild ?? false)
    }

    /// Stars stay nil while the mark is hidden, so the child screen has nothing to read out.
    func praiseStars(for task: HomeworkTask) -> Int? {
        guard markVisible(for: task) else { return nil }
        if task.checkMode == .parent {
            return task.stars ?? today.parentChecks.last(where: { check in
                today.notebookAttempts.contains { $0.id == check.attemptID && $0.taskID == task.id }
            })?.stars
        }
        guard let mark = today.marks[task.id] else { return nil }
        return EnglishStars.count(for: mark, inputMode: readingMode(for: task.id))
    }

    func readingMode(for taskID: UUID) -> InputMode {
        if let mode = today.readingModes[taskID] { return mode }
        if readAloud?.taskID == taskID { return readAloud?.inputMode ?? .spoken }
        return .spoken
    }
}
