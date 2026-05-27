import SwiftUI

struct NewProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var tint: Profile.Tint = .blue
    let onCreate: (String, Profile.Tint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Profile")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $name, prompt: Text("Personal, Work, Side Project…"))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Color")
                        .frame(width: 60, alignment: .leading)
                    TintPicker(selection: $tint)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onCreate(name, tint)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}

struct TintPicker: View {
    @Binding var selection: Profile.Tint

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Profile.Tint.allCases) { tint in
                Button {
                    selection = tint
                } label: {
                    ZStack {
                        Circle()
                            .fill(tint.color)
                            .frame(width: 18, height: 18)
                        if selection == tint {
                            Circle()
                                .strokeBorder(.primary, lineWidth: 2)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(tint.rawValue.capitalized)
            }
        }
    }
}
