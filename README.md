# Dictation

[Русская версия](README.ru.md)

A native macOS menu bar app. Hold **Control + 🌐 (Globe / Fn)**, speak, then release either key. Local Whisper transcribes your voice and sends the text to the original input field using ⌘V.

- Apple GPU recognition with Metal/MPS; CPU mode is also available.
- A live, mirrored voice spectrum while recording and a separate recognition animation.
- Bottom, center or top indicator placement.
- English and Russian interface; automatic selection and an in-app override.
- No account, API key, subscription or cloud service.

## Zero Internet Connection

**Dictation runs entirely on your Mac. Audio and transcripts are processed locally and are never sent to a server by this application. Dictation makes no Internet requests.**

There are no application servers, network APIs, analytics, telemetry, update checks, model downloads or local HTTP servers. Swift and the Python worker communicate through local stdin/stdout pipes. Whisper uses only an existing model directory; missing model files produce an error instead of a download. Hugging Face offline mode is forced, and Hugging Face and ONNX Runtime telemetry are disabled.

Recordings live in a private temporary directory (owner access only) and are deleted after recognition, cancellation, an error or a normal exit. A forced termination can leave a temporary recording behind. The last transcript is kept only in memory; there is no saved transcript history. Preferences contain settings and local paths, not dictated text. Clipboard writes use macOS's **current-host-only** option, so Dictation does not publish them through Universal Clipboard.

This promise covers the app and its recognition worker during use. Installing development tools, Python packages and model files is a separate setup step and may require Internet access. A program you paste into, or a separate clipboard manager, has its own storage and network behavior. Dictation does not control those applications.

## Requirements and build

- macOS 14 or later and Xcode / Swift 5.9 or later.
- A local Python environment with `faster-whisper` and its dependencies. The tested versions are recorded in [requirements.txt](requirements.txt). Python and model weights are not bundled.
- A complete local CTranslate2 Whisper model directory, including `model.bin`, `config.json`, `tokenizer.json`, `preprocessor_config.json` and the vocabulary files supplied with that model. Use a multilingual model for Russian.
- GPU mode requires an Apple Silicon Mac and a CTranslate2 build that exposes the experimental MPS backend. The tested installation uses CTranslate2 4.9.1. Selecting CPU works without MPS; there is no silent CPU fallback.

```sh
bash scripts/build.sh
open dist/Dictation.app
```

Build with the script to include the worker, translations and macOS permission descriptions. Running the bare Swift executable does not provide the complete app bundle.

The default locations preserve compatibility with an existing local installation:

```text
~/.local/share/whisper-ru/venv/bin/python
~/.local/share/whisper-ru/model/
```

Change them under **Settings → Recognition settings** if your installation lives elsewhere. Dictation never installs packages, downloads weights or modifies your existing Whisper installation. The requirements file records the tested package versions; it does not bundle native dependencies or guarantee that every CTranslate2 build includes MPS.

## First launch

1. Allow microphone access in the app's settings.
2. Enable **Dictation.app** in **System Settings → Privacy & Security → Accessibility**. The app rechecks permissions automatically.
3. Wait until the local model is ready, close settings and place your cursor in an input field.
4. Hold Control + 🌐, speak and release the keys.

If the shortcut remains unavailable, allow Dictation in **Input Monitoring** and restart the app. Secure Input and protected fields can prevent global shortcuts or pasting.

If Globe switches input languages or opens system dictation, set **Keyboard → Press 🌐 key to → Do Nothing**. Check your input-source shortcut, usually Control + Space. Dictation does not change macOS keyboard assignments.

## Settings

| Setting | Behavior |
| --- | --- |
| Interface language | **System / English / Русский**. System selects Russian when the primary preferred macOS language is Russian, otherwise English. An explicit choice is saved and applies immediately. |
| Speech language | Russian, English or Auto-detect. Independent of interface language. Existing choices are preserved; a fresh setup uses Russian for a Russian interface, otherwise Auto-detect. |
| Indicator position | Bottom, Center or Top; saved and applied immediately. The same screen is used throughout one dictation. |
| Device | Apple GPU (Metal/MPS, FP16) or CPU (INT8). A change reloads the worker automatically. The UI shows the actual device reported by the engine. |
| Recognition mode | Fast (`beam_size=1`) or Accurate (`beam_size=5`). This changes search effort, not model size. A change reloads the worker automatically. |
| Python / model paths | Click **Restart model** after editing paths. |
| Outro filter | Removes the specific unwanted Russian “subscribe to our channel…” phrase described below. Enabled by default. |

The in-app language selector translates the menu, settings, indicator and application error messages without restarting Whisper. macOS permission dialogs follow the system/app language selected by macOS. Raw third-party error details retain their original language.

The GPU worker warms up Metal before reporting readiness and keeps the model resident between recordings. Audio decoding and voice activity detection may still use CPU. GPU mode does not imply use of Apple's separate Neural Engine.

## Recording and insertion

- Press Control and Globe in either order. Arrow keys are not mistaken for the physical Globe key.
- Release either key to finish. **Esc** cancels a recording; recognition can be cancelled from the menu. New recording is blocked while recognition or insertion is pending.
- Recording also stops at three minutes, on sleep/session deactivation, on an audio interruption, or when a required permission is revoked.
- The nonactivating indicator leaves focus in the target application. Its 25-band audio spectrum is mirrored around the center. Recognition uses a distinct traveling wave. Reduce Motion is respected.
- Capturing and rechecking the target field uses background Accessibility queries. Before sending ⌘V, the app checks the original app/window/field, intervening input and physical modifier keys.
- Clicking, typing, switching applications or Spaces after recording begins prevents automatic paste, even if you return to the original window. The text is copied locally for manual ⌘V instead. If the clipboard changes immediately before insertion, the transcript remains available in the menu/settings.
- Electron/web editors with incomplete Accessibility data use an unchanged-window fallback; recreated text fields are compared by role, identifier and frame. Insufficient evidence results in copying only.
- The original clipboard is restored after one second if nobody has changed it. Rapid successive dictations share the original restoration snapshot. A newer clipboard change is preserved.
- **Text sent** means that ⌘V was sent to the target process, not that the recipient confirmed insertion. It disappears after 0.8 seconds. The last phrase remains available to copy.

The optional outro filter removes this complete phrase only at the end of a result:

> Подписывайтесь на наш канал, ставьте лайки и подписывайтесь на наш канал.

It tolerates case, punctuation and repeated endings, keeps shorter similar phrases and occurrences inside the body, and inserts nothing if cleanup leaves an empty result. Disable it when intentionally dictating this exact ending. It is a narrow cleanup rule, not a general hallucination detector.

## Architecture

| Component | Responsibility |
| --- | --- |
| `AppModel` | Main-actor recording/recognition state, settings, cancellation, permissions and UI messages. |
| `GlobalShortcut` / `HoldShortcut` | Global event tap and physical Control + Globe state machine. |
| `AudioRecorder` / `AudioCaptureSession` | Native PCM capture, private CAF file and synchronized finalization. |
| `SpectrumAnalyzer` | Hann-windowed frequency analysis with independent attack/release dynamics. |
| `WhisperService` / `whisper_worker.py` | A persistent local Python process; JSON lines, request IDs, timeouts and process cleanup. |
| `InsertionContext` / `TextInsertion` / `ClipboardWriter` | Focus tracking, guarded ⌘V, local-only clipboard and restoration. |
| `Overlay` / `Waveform` / `SettingsView` | SwiftUI appearance inside AppKit windows. |
| `AppLocalization` | English/Russian resource catalogs, system detection and explicit language choice. |

`DictationCore` contains independently testable policies, spectrum analysis and localization. The Swift package has no third-party Swift dependencies. The Python runtime is deliberately separate so an existing model can be reused.

## Verification

```sh
bash scripts/test.sh
python3 scripts/test_worker.py --device mps --beam-size 5
python3 scripts/test_worker.py --device cpu --beam-size 5
```

Swift tests cover shortcuts, insertion policy, spectrum dynamics, cleanup, language selection, audio finalization, isolated test clipboards and the worker protocol. Python unit tests cover invalid requests, missing model files and translation catalog coverage. Clipboard tests need a macOS user session with access to the pasteboard service; restricted automation sandboxes may block it. They never modify the general clipboard.

A real-model test with all network access denied:

```sh
mkdir -p .build/fixtures
say -v 'Milena (Russian (Russia))' -o .build/fixtures/russian.aiff \
  'Привет. Это проверка локального распознавания речи.'
python3 scripts/test_worker.py --deny-network --device mps --beam-size 5 \
  --speech .build/fixtures/russian.aiff
```

Use an already installed Russian voice (`say -v '?'` lists available voices). The test checks readiness, actual device/precision, silence, a missing audio file, Russian speech, worker reuse and EOF shutdown. `--deny-network` adds macOS sandbox network denial and a Python socket/DNS audit; it is a development test, not an app dependency. GPU tests need a context that allows Metal access.

Manual acceptance still includes both key orders, release of either key, TextEdit and web/Electron editors, switching focus, Esc, sleep/lock, microphone disconnection, multiple displays, fullscreen windows, both interface languages and CPU/GPU switching. See [the code audit](docs/AUDIT.md) for evidence and remaining limitations.

## Signing and publication

The build script creates an ad-hoc-signed `dist/Dictation.app`. A Developer account is unnecessary for local personal use. Rebuilding or moving the app may require regranting permissions; keep a stable installation path. `DICTATION_SIGN_IDENTITY` can select an existing signing identity. Developer ID notarization, an installer and automatic updates are not configured.

Build output, virtual environments and private configuration are excluded from Git. Model weights and Python packages stay outside the project. An open-source license has not yet been selected.
