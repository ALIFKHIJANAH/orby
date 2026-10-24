import AppKit
import NotchCore
import NotchShared
import SwiftUI

/// Focus mode: the blocked request takes over the expanded panel.
struct RequestFocusView: View {
    @EnvironmentObject var model: IslandModel
    let request: PendingRequest
    let session: AgentSession
    /// Ignore input briefly after the card appears, so a click aimed at the previous card
    /// (or at the notch as it pops open) can't land on this one.
    @State private var armed = PreviewRenderer.active

    var body: some View {
        // Assessed once per render: it runs a batch of regexes over the tool input.
        let risks = RiskAssessor.assess(tool: request.toolName, input: request.toolInput)
        let accent = risks.contains { $0.severity == .danger } ? Theme.error : Theme.attention
        VStack(alignment: .leading, spacing: 12) {
            RequestHeader(request: request, session: session)
            Group {
                switch request.kind {
                case .permission: PermissionBody(request: request, risks: risks)
                case .question: QuestionBody(request: request)
                case .plan: PlanBody(request: request)
                case .external: ExternalPromptBody(request: request, session: session, risks: risks)
                }
            }
            .allowsHitTesting(armed)
            .opacity(armed ? 1 : 0.75)
        }
        .padding(.vertical, 14)
        .padding(.leading, 17)
        .padding(.trailing, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(accent).frame(width: 3).padding(.vertical, 14).padding(.leading, 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.35), lineWidth: 1))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation(.easeOut(duration: 0.15)) { armed = true } }
        }
    }
}

// MARK: Header

private struct RequestHeader: View {
    @EnvironmentObject var model: IslandModel
    let request: PendingRequest
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentMascot(agent: session.agent, phase: session.phase, size: 28, activity: session.activity?.kind)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let t = session.title {
                        Text(PlainText.truncate(t, max: 44)).lineLimit(1)
                        Text("·")
                    }
                    Text(session.projectName).lineLimit(1)
                    if let branch = session.git?.branch { BranchChip(branch: branch, worktree: session.git?.isWorktree ?? false) }
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text("· waiting \(request.receivedAt.shortAgo == "now" ? "just now" : request.receivedAt.shortAgo)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
            }
            Spacer(minLength: 6)
            if model.pending.count > 1 { QueuePager() }
        }
    }

    private var title: String {
        let agent = session.agent == .claude ? "Claude" : session.agent.displayName
        switch request.kind {
        case .permission, .external:
            return "\(agent) wants to \(ToolDescriber.activity(tool: request.toolName, input: request.toolInput).intent)"
        case .question: return "\(agent) has a question"
        case .plan: return "\(agent)’s plan is ready"
        }
    }
}

private struct QueuePager: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        let index = min(model.selectedRequestIndex, model.pending.count - 1)
        HStack(spacing: 4) {
            Button { model.selectedRequestIndex = max(0, index - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
            Text("\(index + 1) of \(model.pending.count)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Button { model.selectedRequestIndex = min(model.pending.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(index >= model.pending.count - 1)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
        .help("Other agents are waiting too")
    }
}

// MARK: Shared controls

struct Keycap: View {
    let text: String
    var onLight = false

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(onLight ? Color.black.opacity(0.6) : Theme.secondaryText)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(onLight ? Color.black.opacity(0.12) : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct DecisionButton: View {
    enum Kind { case primary(Color), outline(Color), ghost }
    let title: String
    var keycap: String? = nil
    let kind: Kind
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                if let keycap { Keycap(text: keycap, onLight: isPrimary) }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressableStyle())
    }

    private var isPrimary: Bool { if case .primary = kind { true } else { false } }
    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .outline(let c): c
        case .ghost: Theme.primaryText
        }
    }
    private var background: Color {
        switch kind {
        case .primary(let c): c
        case .outline(let c): c.opacity(0.1)
        case .ghost: Color.white.opacity(0.1)
        }
    }
    private var stroke: Color {
        if case .outline(let c) = kind { return c.opacity(0.6) }
        return .clear
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Secondary "do it in the terminal" escape hatch, deliberately lighter than the decisions.
private struct TerminalButton: View {
    var title = "Answer in Terminal"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "terminal")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Leave this to the agent's own prompt in the terminal")
    }
}

private struct ActionBar<Trailing: View>: View {
    let terminalTitle: String
    let onTerminal: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            TerminalButton(title: terminalTitle, action: onTerminal)
            Spacer(minLength: 8)
            trailing
        }
    }
}

// MARK: Permission

private struct PermissionBody: View {
    @EnvironmentObject var model: IslandModel
    let request: PendingRequest
    let risks: [Risk]

    private var activity: Activity { ToolDescriber.activity(tool: request.toolName, input: request.toolInput) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Skip Claude's description when the title already says the same thing.
            if let reason = request.toolInput["description"]?.string, reason.lowercased() != activity.intent.lowercased() {
                Text(reason).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            if !risks.isEmpty { RiskChips(risks: risks) }
            RequestPreview(request: request, risks: risks)
            ActionBar(terminalTitle: "Answer in Terminal", onTerminal: { model.decide(request, .passthrough) }) {
                DecisionButton(title: "Deny", keycap: "⌘N", kind: .outline(Theme.error)) {
                    model.decide(request, .deny(message: "The user denied this from Orby."))
                }
                if !request.suggestions.isEmpty {
                    DecisionButton(title: "Always allow", kind: .ghost) {
                        model.decide(request, .allow(updatedPermissions: request.suggestions))
                    }
                }
                DecisionButton(title: "Allow", keycap: "⌘Y", kind: .primary(Theme.done)) { model.decide(request, .allow()) }
            }
            if let always = alwaysExplanation {
                Text(always)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// What "Always allow" will change, spelled out from Claude's own suggestions.
    private var alwaysExplanation: String? {
        let rules = request.suggestions.flatMap { $0["rules"]?.array ?? [] }.compactMap { r -> String? in
            guard let tool = r["toolName"]?.string else { return nil }
            return r["ruleContent"]?.string.map { "\(tool)(\($0))" } ?? tool
        }
        let agent = model.session(for: request.sessionKey)?.agent.displayName ?? "the agent"
        if !rules.isEmpty { return "Always allow adds the rule \(rules.joined(separator: ", ")), so \(agent) won't ask again for it." }
        if let mode = request.suggestions.first(where: { $0["type"]?.string == "setMode" })?["mode"]?.string {
            return mode == "acceptEdits"
                ? "Always allow auto-accepts file edits for the rest of this session."
                : "Always allow switches this session to \(ToolDescriber.words(mode)) mode."
        }
        return nil
    }
}

/// What the tool call will do: a diff for edits, the command, URL or path otherwise.
private struct RequestPreview: View {
    let request: PendingRequest
    let risks: [Risk]

    var body: some View {
        let danger = risks.contains { $0.severity == .danger }
        let input = request.toolInput
        let command = request.toolName == "run_command" ? (input["CommandLine"]?.string ?? "") : ToolDescriber.command(from: input)
        let path = input["file_path"]?.string ?? input["TargetFile"]?.string ?? input["AbsolutePath"]?.string
        if let diff = DiffPreview.make(tool: request.toolName, input: input) {
            DiffView(preview: diff, danger: danger)
        } else if !command.isEmpty {
            CodeBox(text: "$ " + command, copyText: command, danger: danger)
        } else if let url = input["url"]?.string ?? input["Url"]?.string {
            CodeBox(text: url, copyText: url, maxHeight: 60)
        } else if let path {
            CodeBox(text: ToolDescriber.abbreviate(path), copyText: path, maxHeight: 60)
        } else if let data = try? input.encoded(pretty: true), let s = String(data: data, encoding: .utf8), s != "{}" {
            CodeBox(text: s, copyText: s)
        }
    }
}

// MARK: External prompt (Antigravity)

/// The agent asks in its own terminal and offers no way to answer from outside it, so the
/// notch shows what it wants and takes you there.
private struct ExternalPromptBody: View {
    @EnvironmentObject var model: IslandModel
    let request: PendingRequest
    let session: AgentSession
    let risks: [Risk]

    var body: some View {
        let menu = model.externalMenus[request.id]
        let inFlight = model.answering[request.id]
        VStack(alignment: .leading, spacing: 10) {
            if !risks.isEmpty { RiskChips(risks: risks) }
            RequestPreview(request: request, risks: risks)
            if let error = model.answerErrors[request.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.attention)
            }
            if let menu {
                ActionBar(terminalTitle: "Go to terminal", onTerminal: { model.jump(to: session) }) {
                    if let deny = menu.deny {
                        DecisionButton(title: inFlight == .deny ? "Denying…" : "Deny", keycap: "⌘N", kind: .outline(Theme.error)) {
                            model.answerExternal(request, kind: .deny)
                        }
                        .help(deny.label)
                    }
                    if let always = menu.approveAlways {
                        DecisionButton(title: inFlight == .approveAlways ? "Allowing…" : "Always (this chat)", kind: .ghost) {
                            model.answerExternal(request, kind: .approveAlways)
                        }
                        .help(always.label)
                    }
                    if let approve = menu.approve {
                        DecisionButton(title: inFlight == .approve ? "Approving…" : "Approve", keycap: "⌘Y", kind: .primary(Theme.done)) {
                            model.answerExternal(request, kind: .approve)
                        }
                        .help(approve.label)
                    }
                }
                .disabled(inFlight != nil)
                Text("Answers by typing into \(session.agent.displayName)'s terminal, as if you pressed the option there.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(spacing: 8) {
                    Label("\(session.agent.displayName) only accepts answers in its own terminal.", systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer(minLength: 8)
                    DecisionButton(title: "Go to terminal", keycap: "⌘Y", kind: .primary(Theme.working)) {
                        model.jump(to: session)
                    }
                }
            }
        }
        // Re-read the agent's menu while the card is up; it can appear a moment after the log line.
        // A task rather than a stored Timer.publish, which every re-render of the card recreated.
        .task(id: request.id) {
            while !Task.isCancelled {
                model.loadExternalMenu(request)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct RiskChips: View {
    let risks: [Risk]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(risks, id: \.label) { risk in
                let color = risk.severity == .danger ? Theme.error : Theme.attention
                Label(risk.label, systemImage: risk.severity == .danger ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.14), in: Capsule())
            }
        }
    }
}

struct CodeBox: View {
    let text: String
    var copyText: String? = nil
    var maxHeight: CGFloat = 130
    var danger = false
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        FittedScroll(maxHeight: maxHeight) {
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.leading, 10)
                .padding(.trailing, 30)
        }
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(danger ? Theme.error.opacity(0.7) : Theme.stroke, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if let copyText, hovering || copied {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(5)
                .help("Copy")
            }
        }
        .onHover { hovering = $0 }
    }
}

private struct DiffView: View {
    let preview: DiffPreview
    let danger: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: preview.isWholeFile ? "doc.badge.plus" : "doc.text")
                Text(preview.fileName ?? "Changes").font(.system(size: 11, weight: .semibold, design: .monospaced))
                Spacer()
                if preview.isWholeFile {
                    Text("\(preview.addedCount + preview.hiddenCount) lines").foregroundStyle(Theme.tertiaryText)
                } else {
                    Text("+\(preview.addedCount)").foregroundStyle(Theme.done)
                    Text("−\(preview.removedCount)").foregroundStyle(Theme.error)
                }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))

            FittedScroll(maxHeight: 170) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in DiffRow(line: line) }
                    if preview.hiddenCount > 0 {
                        Text("+\(preview.hiddenCount) more lines")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(danger ? Theme.error.opacity(0.7) : Theme.stroke, lineWidth: 1))
    }
}

private struct DiffRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(sign).frame(width: 16, alignment: .center).foregroundStyle(color.opacity(0.8))
            Text(line.text.isEmpty ? " " : line.text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 11, weight: line.kind == .file ? .semibold : .regular, design: .monospaced))
        .foregroundStyle(line.kind == .context ? Theme.secondaryText : (line.kind == .file ? Theme.primaryText : color))
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .padding(.top, line.kind == .file ? 4 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        case .file: "▸"
        }
    }
    private var color: Color {
        switch line.kind {
        case .added: Theme.done
        case .removed: Theme.error
        default: Theme.secondaryText
        }
    }
    private var background: Color {
        switch line.kind {
        case .added: Theme.done.opacity(0.1)
        case .removed: Theme.error.opacity(0.1)
        default: .clear
        }
    }
}

// MARK: Question

private struct QuestionBody: View {
    @EnvironmentObject var model: IslandModel
    let request: PendingRequest
    @State private var page = 0
    @State private var answers: [String: [String]] = [:]
    @State private var otherText: [String: String] = [:]
    @State private var typingOther = false

    var body: some View {
        let questions = request.questions
        if questions.isEmpty {
            ActionBar(terminalTitle: "Answer in Terminal", onTerminal: { model.decide(request, .passthrough) }) {
                Text("This question can only be answered in the terminal.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            }
        } else {
            let q = questions[min(page, questions.count - 1)]
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let header = q.header {
                        Text(header.uppercased())
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Theme.attention)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Theme.attention.opacity(0.14), in: Capsule())
                    }
                    if q.multiSelect {
                        Text("Pick any").font(.system(size: 10.5)).foregroundStyle(Theme.tertiaryText)
                    }
                    Spacer()
                    if questions.count > 1 { progress(questions.count) }
                }
                Text(q.question)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 6) {
                    ForEach(Array(q.options.enumerated()), id: \.element.label) { i, option in
                        OptionRow(
                            index: i, option: option, selected: answers[q.question, default: []].contains(option.label),
                            multi: q.multiSelect
                        ) { choose(option.label, in: q, questions: questions) }
                    }
                    OtherAnswerRow(
                        text: Binding(get: { otherText[q.question, default: ""] }, set: { otherText[q.question] = $0 }),
                        typing: $typingOther
                    ) { submitOther(q, questions: questions) }
                }
                ActionBar(terminalTitle: "Answer in Terminal", onTerminal: { model.decide(request, .passthrough) }) {
                    if q.multiSelect || questions.count > 1 {
                        let count = currentAnswer(q).count
                        DecisionButton(
                            title: isLast(questions) ? (count > 0 ? "Submit (\(count))" : "Submit") : "Next",
                            kind: .primary(Theme.working)
                        ) { advance(q, questions: questions) }
                        .disabled(count == 0)
                    }
                }
            }
            .onReceive(model.optionShortcut) { i in
                guard i < q.options.count else { return }
                choose(q.options[i].label, in: q, questions: questions)
            }
        }
    }

    private func progress(_ total: Int) -> some View {
        HStack(spacing: 6) {
            Text("Question \(page + 1) of \(total)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.tertiaryText)
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    Circle().fill(i <= page ? Theme.working : Color.white.opacity(0.2)).frame(width: 5, height: 5)
                }
            }
        }
    }

    private func isLast(_ qs: [Question]) -> Bool { page >= qs.count - 1 }

    private func currentAnswer(_ q: Question) -> [String] {
        var a = answers[q.question, default: []]
        let other = otherText[q.question, default: ""].trimmingCharacters(in: .whitespaces)
        if !other.isEmpty { a.append(other) }
        return a
    }

    private func choose(_ label: String, in q: Question, questions: [Question]) {
        if q.multiSelect {
            var set = answers[q.question, default: []]
            if let i = set.firstIndex(of: label) { set.remove(at: i) } else { set.append(label) }
            answers[q.question] = set
        } else {
            answers[q.question] = [label]
            otherText[q.question] = nil
            advance(q, questions: questions)
        }
    }

    private func submitOther(_ q: Question, questions: [Question]) {
        guard !currentAnswer(q).isEmpty else { return }
        if !q.multiSelect { answers[q.question] = [] }
        advance(q, questions: questions)
    }

    private func advance(_ q: Question, questions: [Question]) {
        answers[q.question] = currentAnswer(q)
        otherText[q.question] = nil
        typingOther = false
        if isLast(questions) {
            model.decide(request, PermissionDecision.answering(request, answers: answers))
        } else {
            page += 1
        }
    }
}

private struct OptionRow: View {
    let index: Int
    let option: QuestionOption
    let selected: Bool
    let multi: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                if index < 9 { Keycap(text: "⌘\(index + 1)").frame(width: 26) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.primaryText)
                    if let d = option.detail {
                        Text(d).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: indicator)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Theme.working : Theme.tertiaryText)
                    .opacity(multi || hovering || selected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Theme.working.opacity(0.14) : (hovering ? Theme.cardHover : Color.white.opacity(0.05)),
                in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.working.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var indicator: String {
        if multi { return selected ? "checkmark.square.fill" : "square" }
        return selected ? "checkmark.circle.fill" : "arrow.right.circle"
    }
}

/// "Type your own answer…" that turns into a text field only when wanted.
private struct OtherAnswerRow: View {
    @Binding var text: String
    @Binding var typing: Bool
    let submit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        if typing {
            HStack(spacing: 8) {
                Image(systemName: "pencil").foregroundStyle(Theme.tertiaryText)
                TextField("Type your answer and press Return", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { typing = false }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.working.opacity(0.5), lineWidth: 1))
            .onAppear { focused = true }
        } else {
            Button { typing = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                    Text("Type your own answer…")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Theme.stroke))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: Plan

private struct PlanBody: View {
    @EnvironmentObject var model: IslandModel
    let request: PendingRequest
    @State private var feedback = ""

    private var note: String { feedback.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FittedScroll(maxHeight: 280) {
                MarkdownView(markdown: request.planMarkdown ?? "(empty plan)")
                    .padding(10)
            }
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            TextField("Changes for Claude (sends the plan back)…", text: $feedback, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            if !note.isEmpty {
                Label("“Request changes” sends this note back to Claude. “Approve” ignores it.", systemImage: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.attention)
            }
            ActionBar(terminalTitle: "Terminal", onTerminal: { model.decide(request, .passthrough) }) {
                // The only path that rejects the plan, and only with a note.
                DecisionButton(title: "Request changes", kind: .outline(Theme.attention)) {
                    model.decide(request, .deny(message: note))
                }
                .disabled(note.isEmpty)
                DecisionButton(title: "Approve + auto-edit", kind: .ghost) {
                    model.decide(request, .approvePlan(request, mode: "acceptEdits"))
                }
                .help("Approve and auto-accept file edits for this session")
                DecisionButton(title: "Approve", kind: .primary(Theme.done)) { model.decide(request, .approvePlan(request)) }
            }
        }
    }
}
