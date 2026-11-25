import SwiftUI
import DictationCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private let accent = Color(red: 0.40, green: 0.94, blue: 0.78)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("DICTATION", systemImage: "waveform").font(.system(size: 12, weight: .bold)).tracking(2.5).foregroundStyle(accent)
                    Spacer()
                    Label(model.text("privacy.local"), systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.text("settings.title")).font(.system(size: 35, weight: .semibold, design: .rounded)).tracking(-1)
                    Text(model.text("settings.description"))
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineSpacing(4)
                }
                HStack(spacing: 12) {
                    keycap("⌃", label: "control")
                    Text("+").foregroundStyle(.white.opacity(0.3))
                    keycap("🌐", label: "globe / fn")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(model.text("settings.hold")).font(.system(size: 13, weight: .semibold))
                        Text(model.text("settings.release")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                }.padding(20).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Picker(model.text("language.label"), selection: $model.interfaceLanguage) {
                        Text(model.text("language.system")).tag(InterfaceLanguage.system)
                        Text("English").tag(InterfaceLanguage.english)
                        Text("Русский").tag(InterfaceLanguage.russian)
                    }
                    Text(model.text("language.note")).font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    permission(model.text("permission.microphone"), subtitle: model.text("permission.microphone.detail"), icon: "mic", granted: model.microphoneAllowed, action: model.requestMicrophone)
                    Divider().overlay(.white.opacity(0.05)).padding(.leading, 47)
                    permission(model.text("permission.accessibility"), subtitle: model.text("permission.accessibility.detail"), icon: "keyboard", granted: model.accessibilityAllowed, action: model.requestAccessibility)
                    Divider().overlay(.white.opacity(0.05)).padding(.leading, 47)
                    HStack(spacing: 14) {
                        Image(systemName: "cpu").frame(width: 24).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.text("model.local")).font(.system(size: 12, weight: .semibold))
                            Text(model.modelReady ? model.backendDescription : model.modelLoading ? model.text("model.warming") : model.text("model.setup"))
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        if model.modelLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: model.modelReady ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(model.modelReady ? accent : .orange) }
                    }.padding(.vertical, 15)
                }

                if model.phase == .error {
                    Text(model.detail).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                }
                if model.accessibilityAllowed && !model.shortcutReady {
                    Text(model.text("permission.input.error"))
                        .font(.system(size: 12)).foregroundStyle(.orange)
                    Button(model.text("permission.input.open")) { model.openPrivacy("Privacy_ListenEvent") }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(model.text("position.title")).font(.system(size: 12, weight: .semibold))
                    Picker(model.text("position.title"), selection: $model.overlayPosition) {
                        ForEach(OverlayPosition.allCases) { position in
                            Text(model.text("position." + position.rawValue)).tag(position)
                        }
                    }.pickerStyle(.segmented).labelsHidden()
                }

                DisclosureGroup(model.text("recognition.title")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(model.text("recognition.device"), selection: $model.device) {
                            Text("Apple GPU (Metal)").tag("mps")
                            Text("CPU").tag("cpu")
                        }
                        Text(model.modelLoading
                             ? (model.device == "mps" ? model.text("model.switchGPU") : model.text("model.switchCPU"))
                             : (model.modelReady ? model.text("model.current", model.backendDescription) : model.text("model.notReady")))
                            .font(.caption).foregroundStyle(.secondary)
                        Picker(model.text("recognition.mode"), selection: $model.beamSize) {
                            Text(model.text("recognition.fast")).tag(1)
                            Text(model.text("recognition.accurate")).tag(5)
                        }
                        Picker(model.text("recognition.language"), selection: $model.language) {
                            Text("Русский").tag("ru")
                            Text("English").tag("en")
                            Text(model.text("recognition.auto")).tag("")
                        }
                        pathField(model.text("recognition.python"), text: $model.pythonPath)
                        Toggle(model.text("recognition.filter"), isOn: $model.removePromotionalTail)
                            .font(.system(size: 12))
                        pathField(model.text("recognition.modelFolder"), text: $model.modelPath)
                        Button(model.text("recognition.restart")) { model.restartModel() }.disabled(model.busy)
                        Text(model.text("recognition.note")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 14).disabled(model.busy)
                }.font(.system(size: 12)).tint(accent)

                if !model.lastTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(model.text("last.title")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Button(model.text("last.copy")) { TextInsertion.copy(model.lastTranscript) }.font(.system(size: 11))
                        }
                        Text(model.lastTranscript).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        if let seconds = model.lastTranscriptionSeconds {
                            Text(model.text("last.duration", String(format: "%.2f", seconds))).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Button(model.text("settings.preview")) { model.preview() }.buttonStyle(.plain).foregroundStyle(accent).disabled(model.busy)
                    Spacer()
                    Text(model.text("settings.escape")).foregroundStyle(.white.opacity(0.3))
                }.font(.system(size: 11))
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.text("privacy.title"), systemImage: "lock.shield").foregroundStyle(accent)
                    Text(model.text("privacy.description")).foregroundStyle(.secondary)
                }.font(.system(size: 11))
                Text(model.text("settings.globeTip"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).lineSpacing(3)
            }.padding(32)
        }
        .frame(width: 530, height: 760)
        .background(Color(red: 0.045, green: 0.065, blue: 0.075))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func keycap(_ symbol: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(symbol).font(.system(size: 24, weight: .medium))
            Text(label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
        }.frame(width: 67, height: 66)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
    }

    private func permission(_ title: String, subtitle: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            if granted { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
            else { Button(model.text("permission.allow"), action: action).controlSize(.small).tint(accent) }
        }.padding(.vertical, 15)
    }

    private func pathField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
        }
    }
}
