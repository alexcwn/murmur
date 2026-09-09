import SwiftUI

/// Teach the machine words it keeps getting wrong.
struct DictionaryView: View {
    @Bindable var controller: DictationController
    @Binding var query: String

    @State private var newTerm = ""
    @State private var newHeard = ""
    @State private var newWrite = ""
    @State private var editingTerm: DictionaryTerm?
    @State private var editingCorrection: DictionaryCorrection?

    private var store: DictionaryStore { controller.dictionaryStore }

    private var terms: [DictionaryTerm] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.dictionary.terms }
        return store.dictionary.terms.filter {
            $0.text.localizedCaseInsensitiveContains(q) || $0.note.localizedCaseInsensitiveContains(q)
        }
    }

    private var corrections: [DictionaryCorrection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.dictionary.corrections }
        return store.dictionary.corrections.filter {
            $0.heard.localizedCaseInsensitiveContains(q)
                || $0.write.localizedCaseInsensitiveContains(q)
                || $0.note.localizedCaseInsensitiveContains(q)
        }
    }

    private var termWarning: EntryValidator.Warning? {
        newTerm.isEmpty ? nil : EntryValidator.check(term: newTerm)
    }

    private var correctionWarning: EntryValidator.Warning? {
        (newHeard.isEmpty && newWrite.isEmpty)
            ? nil
            : EntryValidator.check(heard: newHeard, write: newWrite)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.loose) {
                addWords
                addCorrections
                fileRow
            }
            .padding(Tokens.Space.base)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Words

    private var addWords: some View {
        Faceplate(padding: Tokens.Space.base) {
            VStack(alignment: .leading, spacing: Tokens.Space.snug) {
                Silkscreen(text: "Words it should know", size: .large)
                Text("Names, jargon, product names. Passed to the recogniser as context, and used to fix casing afterwards.")
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(Tokens.Text.secondary)

                HStack(spacing: Tokens.Space.snug) {
                    TextField("Anthropic", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .font(Tokens.Typography.body)
                        .onSubmit(commitTerm)
                    DeckButton(title: "Add", isEnabled: !newTerm.trimmingCharacters(in: .whitespaces).isEmpty) {
                        commitTerm()
                    }
                    .frame(width: 74)
                }

                if let w = termWarning { warningRow(w) }

                if terms.isEmpty {
                    Silkscreen(text: query.isEmpty ? "None yet" : "No matches",
                               size: .micro, color: Tokens.Text.secondary)
                } else {
                    ForEach(terms) { term in
                        Well(padding: Tokens.Space.snug) {
                            HStack(spacing: Tokens.Space.snug) {
                                Text(term.text)
                                    .font(Tokens.Typography.body)
                                    .foregroundStyle(Tokens.Text.readout)
                                if !term.note.isEmpty {
                                    Text(term.note)
                                        .font(Tokens.Typography.bodySmall)
                                        .foregroundStyle(Tokens.Text.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Button { editingTerm = term } label: {
                                    Silkscreen(text: "Edit", size: .micro)
                                }
                                .buttonStyle(.plain)
                                Button { store.deleteTerm(term.id) } label: {
                                    Silkscreen(text: "Delete", size: .micro, color: Tokens.Signal.record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editingTerm) { term in
            EditTermSheet(term: term) { store.update($0) }
        }
    }

    // MARK: - Corrections

    private var addCorrections: some View {
        Faceplate(padding: Tokens.Space.base) {
            VStack(alignment: .leading, spacing: Tokens.Space.snug) {
                Silkscreen(text: "When you hear → write", size: .large)
                Text("Runs after the cleanup pass, so it always wins. Matches whole words only, and tolerates glued or hyphenated forms — one rule catches “cloud code”, “CloudCode” and “Cloud-Code”.")
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(Tokens.Text.secondary)

                HStack(spacing: Tokens.Space.snug) {
                    TextField("cloud code", text: $newHeard)
                        .textFieldStyle(.roundedBorder)
                        .font(Tokens.Typography.body)
                    Silkscreen(text: "→", size: .normal)
                    TextField("Claude Code", text: $newWrite)
                        .textFieldStyle(.roundedBorder)
                        .font(Tokens.Typography.body)
                        .onSubmit(commitCorrection)
                    DeckButton(title: "Add", isEnabled: canAddCorrection) { commitCorrection() }
                        .frame(width: 74)
                }

                if let w = correctionWarning { warningRow(w) }

                if corrections.isEmpty {
                    Silkscreen(text: query.isEmpty ? "None yet" : "No matches",
                               size: .micro, color: Tokens.Text.secondary)
                } else {
                    ForEach(corrections) { c in
                        Well(padding: Tokens.Space.snug) {
                            HStack(spacing: Tokens.Space.snug) {
                                Text(c.heard)
                                    .font(Tokens.Typography.readoutSmall)
                                    .foregroundStyle(Tokens.Text.secondary)
                                Silkscreen(text: "→", size: .micro)
                                Text(c.write)
                                    .font(Tokens.Typography.body)
                                    .foregroundStyle(Tokens.Text.readout)
                                Spacer(minLength: 0)
                                if let w = EntryValidator.check(heard: c.heard, write: c.write),
                                   w.severity == .danger {
                                    Silkscreen(text: "Risky", size: .micro, color: Tokens.Signal.record)
                                        .help(w.message)
                                }
                                Button { editingCorrection = c } label: {
                                    Silkscreen(text: "Edit", size: .micro)
                                }
                                .buttonStyle(.plain)
                                Button { store.deleteCorrection(c.id) } label: {
                                    Silkscreen(text: "Delete", size: .micro, color: Tokens.Signal.record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editingCorrection) { c in
            EditCorrectionSheet(correction: c) { store.update($0) }
        }
    }

    private var fileRow: some View {
        HStack(spacing: Tokens.Space.snug) {
            Silkscreen(text: "Stored at", size: .micro)
            Text(store.url.path(percentEncoded: false))
                .font(Tokens.Typography.readoutSmall)
                .foregroundStyle(Tokens.Text.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let at = store.lastExternalReload,
               Date().timeIntervalSince(at) < 6 {
                Silkscreen(text: "Reloaded", size: .micro, color: Tokens.Signal.levelSafe)
            }
            Button { store.revealInFinder() } label: {
                Silkscreen(text: "Reveal", size: .micro)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tokens.Space.tight)
    }

    private func warningRow(_ warning: EntryValidator.Warning) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.snug) {
            Rectangle()
                .fill(warning.severity == .danger ? Tokens.Signal.record : Tokens.Signal.levelWarn)
                .frame(width: 3)
            Text(warning.message)
                .font(Tokens.Typography.bodySmall)
                .foregroundStyle(warning.severity == .danger ? Tokens.Signal.record : Tokens.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private var canAddCorrection: Bool {
        !newHeard.trimmingCharacters(in: .whitespaces).isEmpty
            && !newWrite.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commitTerm() {
        guard !newTerm.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addTerm(newTerm)
        newTerm = ""
    }

    private func commitCorrection() {
        guard canAddCorrection else { return }
        store.addCorrection(heard: newHeard, write: newWrite)
        newHeard = ""
        newWrite = ""
    }
}

// MARK: - Edit sheets

private struct EditTermSheet: View {
    @State var term: DictionaryTerm
    var onSave: (DictionaryTerm) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.base) {
            Silkscreen(text: "Edit word", size: .large)
            TextField("Word", text: $term.text).textFieldStyle(.roundedBorder)
            TextField("Note (optional)", text: $term.note).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                DeckButton(title: "Cancel") { dismiss() }.frame(width: 90)
                DeckButton(title: "Save") { onSave(term); dismiss() }.frame(width: 90)
            }
        }
        .padding(Tokens.Space.section)
        .frame(width: 380)
        .background(Tokens.Surface.chassis)
    }
}

private struct EditCorrectionSheet: View {
    @State var correction: DictionaryCorrection
    var onSave: (DictionaryCorrection) -> Void
    @Environment(\.dismiss) private var dismiss

    private var warning: EntryValidator.Warning? {
        EntryValidator.check(heard: correction.heard, write: correction.write)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.base) {
            Silkscreen(text: "Edit correction", size: .large)
            TextField("When you hear", text: $correction.heard).textFieldStyle(.roundedBorder)
            TextField("Write", text: $correction.write).textFieldStyle(.roundedBorder)
            TextField("Note (optional)", text: $correction.note).textFieldStyle(.roundedBorder)
            if let w = warning {
                Text(w.message)
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(w.severity == .danger ? Tokens.Signal.record : Tokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                DeckButton(title: "Cancel") { dismiss() }.frame(width: 90)
                DeckButton(title: "Save") { onSave(correction); dismiss() }.frame(width: 90)
            }
        }
        .padding(Tokens.Space.section)
        .frame(width: 420)
        .background(Tokens.Surface.chassis)
    }
}
