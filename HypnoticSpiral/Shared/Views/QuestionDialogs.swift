//
//  QuestionDialogs.swift
//  HypnoticSpiral
//
//  Overlay dialogs for in-session questions and prompts
//

import SwiftUI

/// Simple message prompt with OK button
struct PromptDialog: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()

            Button("OK") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

/// Text input question that stores answer in a variable
struct OpenQuestionDialog: View {
    let prompt: String
    let variableName: String
    let onSubmit: (String) -> Void

    @State private var answer: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text(prompt)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()

            TextField("Your answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitAnswer()
                }
                .frame(width: 300)

            Button("Submit") {
                submitAnswer()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(answer.isEmpty)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            // Auto-focus the text field
            isFocused = true
        }
    }

    private func submitAnswer() {
        guard !answer.isEmpty else { return }
        onSubmit(answer)
    }
}

/// Yes/No question that branches to different scripts
struct YesNoQuestionDialog: View {
    let question: String
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(question)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()

            HStack(spacing: 20) {
                Button("No") {
                    onNo()
                }
                .keyboardShortcut("n")
                .buttonStyle(.bordered)

                Button("Yes") {
                    onYes()
                }
                .keyboardShortcut("y")
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

/// Challenge question (like open_question but for interactive challenges)
struct ChallengeDialog: View {
    let prompt: String
    let variableName: String
    let onSubmit: (String) -> Void

    @State private var answer: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text(prompt)
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundColor(.orange)
                .padding()

            TextField("Your answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitAnswer()
                }
                .frame(width: 300)

            Button("Submit") {
                submitAnswer()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            isFocused = true
        }
    }

    private func submitAnswer() {
        onSubmit(answer)
    }
}

/// Persistent preference question - saves to SharedVariables
struct SetPrefDialog: View {
    let prompt: String
    let variableName: String
    let onSubmit: (String) -> Void

    @State private var answer: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(prompt)
                    .font(.title2)
                    .multilineTextAlignment(.center)

                Text("(This will be saved for future sessions)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            TextField("Your answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitAnswer()
                }
                .frame(width: 300)

            Button("Save") {
                submitAnswer()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(answer.isEmpty)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            isFocused = true
        }
    }

    private func submitAnswer() {
        guard !answer.isEmpty else { return }
        onSubmit(answer)
    }
}
