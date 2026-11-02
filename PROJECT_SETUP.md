# Configurações Necessárias do Projeto Vox

## Info.plist

Adicione as seguintes entradas no arquivo Info.plist do projeto:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>O Vox precisa acessar o microfone para transcrever sua voz em texto.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>O Vox usa reconhecimento de fala para transcrever suas palavras em tempo real.</string>

<key>LSUIElement</key>
<false/>
```

## Configurações do Target

### General
- Deployment Target: macOS 15.0 ou superior
- App Category: Productivity

### Signing & Capabilities
Adicione as seguintes capabilities:
1. App Sandbox
   - Microphone (ativado)
   - Audio Input (ativado)
   
### Build Settings
- Enable Hardened Runtime: Yes
- Code Sign Style: Automatic Development

## Entitlements

Certifique-se de que o arquivo .entitlements contém:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.microphone</key>
<true/>
```

## UserDefaults Defaults

O app usa os seguintes UserDefaults com valores padrão:

- `autoStartRecording`: false
- `autoCopyToClipboard`: true
- `showDockModal`: true
- `enableVoiceCommands`: true
- `commandPrefix`: "vox"

Para definir valores padrão, adicione no AppDelegate:

```swift
func registerDefaultSettings() {
    UserDefaults.standard.register(defaults: [
        "autoStartRecording": false,
        "autoCopyToClipboard": true,
        "showDockModal": true,
        "enableVoiceCommands": true,
        "commandPrefix": "vox"
    ])
}
```

Chame `registerDefaultSettings()` no início de `applicationDidFinishLaunching`.
