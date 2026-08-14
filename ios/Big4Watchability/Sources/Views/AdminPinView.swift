import SwiftUI

// Swift mirror of AdminPinScreen.kt - reached by tapping About's title 12
// times. PIN is checked server-side (adminService.ts); this screen only
// ever holds what the user typed, never the real PIN itself.
struct AdminPinView: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter PIN")
                    .font(.title3.bold())
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pin) { newValue in
                        pin = newValue.filter(\.isNumber)
                    }
                if let error = viewModel.loginError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                Button {
                    viewModel.submitPin(pin)
                } label: {
                    if viewModel.isLoggingIn {
                        ProgressView()
                    } else {
                        Text("Unlock").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoggingIn || pin.isEmpty)
                Text("Not shown anywhere in Settings on purpose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
