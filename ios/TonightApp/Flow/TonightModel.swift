import AuthKit
import Foundation
import Observation
import ProfilesKit

enum TonightRoute: Equatable {
    case signIn
    case consent
    case addChild
    case subjects
    case childHome
    case parentArea

    init?(argument: String) {
        switch argument {
        case "signIn": self = .signIn
        case "consent": self = .consent
        case "addChild": self = .addChild
        case "subjects": self = .subjects
        case "child": self = .childHome
        case "parent": self = .parentArea
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
    static let digitCount = 4

    var session = ParentalGateSession()
    var answer = ""
    var offset = 0
    var notice = ""
    var presented = false
    let fixed: Bool

    init(fixed: Bool) {
        self.fixed = fixed
    }

    var challenge: GateChallenge {
        ParentalGateBank.challenge(fixed: fixed, offset: offset)
    }

    var isLocked: Bool { session.isLocked(at: Date()) }

    func press(_ key: String) -> GateVerdict? {
        if isLocked {
            notice = "Locked for a minute."
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
        switch verdict {
        case .unlocked:
            notice = ""
            answer = ""
        case .incorrect:
            notice = "Let's try a different one."
            answer = ""
            if !fixed { offset += 1 }
        case .locked:
            notice = "Locked for a minute."
            answer = ""
        }
        return verdict
    }

    func resetForBackground() {
        session.resetForBackground()
        answer = ""
        notice = ""
        presented = false
        offset = 0
    }

    static func preview(answer: String) -> GateModel {
        let gate = GateModel(fixed: true)
        gate.presented = true
        gate.answer = answer
        return gate
    }

    static func previewLocked() -> GateModel {
        let gate = GateModel(fixed: true)
        gate.notice = "Locked for a minute."
        var session = ParentalGateSession()
        _ = session.submit(answer: "1", to: ParentalGateBank.challenges[0], now: Date())
        _ = session.submit(answer: "1", to: ParentalGateBank.challenges[0], now: Date())
        _ = session.submit(answer: "1", to: ParentalGateBank.challenges[0], now: Date())
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
    var gate: GateModel
    var authMethod = "email"
    let consentStore = InMemoryAdultConsentStore()
    let sessionStore: any ParentSessionStoring

    init(sessionStore: any ParentSessionStoring = InMemorySessionStore()) {
        self.sessionStore = sessionStore
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
        case .subjects, .childHome, .parentArea:
            installFixtureChild()
        case .signIn, .consent, .addChild:
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
        finishSignIn(method: "email")
    }

    func finishSignIn(method: String) {
        authMethod = method
        let session = ParentSession.issue(parentID: "parent-placeholder", at: Date())
        try? sessionStore.save(session)
        route = .consent
    }

    func agreeToConsent() {
        guard consent.canContinue else { return }
        consent.saving = true
        let record = AdultConsentRecord(
            parentID: "parent-placeholder",
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
    }

    func finishSubjects() {
        if let editor {
            child = editor.child
        }
        route = .childHome
    }

    func openGate() {
        gate.presented = true
        if gate.isLocked {
            gate.notice = "Locked for a minute."
        }
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
            route = .parentArea
        case .locked:
            gate.presented = false
        case .incorrect:
            break
        }
    }

    func backgrounded() {
        let wasParent = route == .parentArea
        gate.resetForBackground()
        if wasParent {
            route = .childHome
        }
    }
}
