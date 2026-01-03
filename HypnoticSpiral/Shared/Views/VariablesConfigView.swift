//
//  VariablesConfigView.swift
//  HypnoticSpiral
//
//  Configuration pane for preset variables
//  Accessible from config picker toolbar
//

import SwiftUI

struct VariablesConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var variables = SharedVariables.shared
    @State private var newVariableName = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        Form {
            Section {
                Text("Set common variables used across all configurations. These will be available via $variableName in scripts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Variables") {
                ForEach(sortedVariableKeys, id: \.self) { key in
                    HStack {
                        Text("$\(key)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)

                        TextField("Value", text: Binding(
                            get: { variables.variables[key] ?? "" },
                            set: { variables.variables[key] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button(action: { variables.removeVariable(name: key) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Add new variable field
                HStack {
                    Text("$")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("new variable", text: $newVariableName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isAddFieldFocused)
                        .onSubmit {
                            addNewVariable()
                        }

                    Button(action: addNewVariable) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(newVariableName.isEmpty)
                }
            }

            Section {
                Text("Changes are saved automatically and will be applied when you start any configuration.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Global Variables")
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 300)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var sortedVariableKeys: [String] {
        variables.variables.keys.sorted()
    }

    private func addNewVariable() {
        let trimmed = newVariableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        variables.addVariable(name: trimmed)
        newVariableName = ""
        isAddFieldFocused = true
    }
}
