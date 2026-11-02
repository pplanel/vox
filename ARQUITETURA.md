# Arquitetura do Vox

## Visão Geral da Estrutura

```
┌─────────────────────────────────────────────────────────┐
│                     macOS Status Bar                     │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌─────┐ ┌──────┐         │
│  │ WiFi │  │ 🔋   │  │ 🔊   │  │ 🎤  │ │ 🕐   │         │
│  └──────┘  └──────┘  └──────┘  └─────┘ └──────┘         │
│                                   ▲                       │
│                                   │ Vox                   │
│                                   │                       │
└───────────────────────────────────┼───────────────────────┘
                                    │
                                    │ Clique
                                    ▼
                        ┌────────────────────────┐
                        │   StatusBarPopover     │
                        │                        │
                        │  • Status Visual       │
                        │  • Iniciar/Parar       │
                        │  • Limpar              │
                        │  • Ajustes...          │
                        │  • Sair                │
                        └────────────────────────┘
```

---

## Fluxo de Gravação

```
┌─────────────┐
│   Usuário   │
│  clica em   │
│  "Gravar"   │
└──────┬──────┘
       │
       ▼
┌──────────────────┐
│  AppDelegate     │
│  speechService.  │
│    toggle()      │
└──────┬───────────┘
       │
       ▼
┌──────────────────────────────────┐
│      SpeechService               │
│                                  │
│  1. Solicita permissão           │
│  2. Baixa modelo (se preciso)    │
│  3. Configura AVAudioEngine      │
│  4. Cria SpeechAnalyzer          │
│  5. Cria SpeechTranscriber       │
│  6. Inicia captura de áudio      │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│     Microfone 🎤                 │
│                                  │
│  Áudio → AVAudioEngine           │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│    SpeechAnalyzer                │
│                                  │
│  Processa áudio em tempo real    │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│   SpeechTranscriber              │
│                                  │
│  Transcreve → Texto              │
└──────┬───────────────────────────┘
       │
       ├─────────────────┬──────────────────┐
       │                 │                  │
       ▼                 ▼                  ▼
┌──────────────┐  ┌─────────────┐  ┌──────────────────┐
│   Volátil    │  │  Finalizado │  │ Comando de Voz?  │
│   (itálico)  │  │   (normal)  │  │                  │
└──────┬───────┘  └──────┬──────┘  └────────┬─────────┘
       │                 │                  │
       │                 │                  ▼
       │                 │         ┌─────────────────┐
       │                 │         │ processCommand  │
       │                 │         │ • copiar        │
       │                 │         │ • limpar        │
       │                 │         │ • parar         │
       │                 │         │ • etc.          │
       │                 │         └─────────────────┘
       │                 │
       └────────┬────────┘
                ▼
   ┌──────────────────────────┐
   │ TranscriptionModalView   │
   │                          │
   │  Mostra texto em         │
   │  tempo real              │
   │                          │
   │  [Texto finalizado...]   │
   │  Texto volátil...        │
   │                          │
   │  [Copiar] [Limpar] [Stop]│
   └──────────────────────────┘
                │
                │ Ao parar
                ▼
        ┌────────────────┐
        │   Clipboard    │
        │   📋          │
        │  Texto copiado │
        └────────────────┘
```

---

## Estrutura de Arquivos

```
vox/
├── voxApp.swift                    # Entry point
│   └── @main struct voxApp: App
│       ├── AppDelegate (adaptor)
│       └── Settings scene
│
├── AppDelegate.swift               # Core do app
│   └── class AppDelegate
│       ├── statusItem (NSStatusItem)
│       ├── speechService (SpeechService)
│       ├── popover (NSPopover)
│       └── transcriptionWindow (NSWindow)
│
├── SpeechService.swift             # Lógica de transcrição
│   └── class SpeechService
│       ├── Status enum
│       ├── AVAudioEngine
│       ├── SpeechAnalyzer
│       ├── SpeechTranscriber
│       ├── transcript: String
│       ├── volatileText: String
│       ├── start()
│       ├── stop()
│       ├── processVoiceCommand()
│       └── copyToClipboard()
│
├── StatusBarPopoverView.swift      # UI do menu
│   └── struct StatusBarPopoverView
│       ├── Status indicator
│       ├── Record/Stop button
│       ├── Clear button
│       └── Settings/Quit links
│
├── TranscriptionModalView.swift    # Modal de texto
│   └── struct TranscriptionModalView
│       ├── Header com status
│       ├── ScrollView com texto
│       └── Footer com ações
│
└── SettingsView.swift              # Configurações
    └── struct SettingsView
        ├── TabView
        │   ├── GeneralSettingsView
        │   ├── VoiceCommandsSettingsView
        │   └── AboutSettingsView
        └── @AppStorage properties
```

---

## Fluxo de Dados

```
┌─────────────────────────────────────────────────────────┐
│                    UserDefaults                          │
│                                                          │
│  • autoStartRecording: Bool                             │
│  • autoCopyToClipboard: Bool                            │
│  • showDockModal: Bool                                  │
│  • enableVoiceCommands: Bool                            │
│  • commandPrefix: String                                │
│                                                          │
└────────────┬──────────────────────────┬─────────────────┘
             │                          │
             │ Lê                       │ Escreve
             ▼                          │
    ┌─────────────────┐                │
    │ SpeechService   │                │
    │ lê ao processar │                │
    └─────────────────┘                │
                                       │
                              ┌────────┴─────────┐
                              │  SettingsView    │
                              │  @AppStorage     │
                              │  modifica values │
                              └──────────────────┘
```

---

## Ciclo de Vida do App

```
1. App Launch
   ├── voxApp.init()
   ├── AppDelegate.applicationDidFinishLaunching()
   │   ├── registerDefaultSettings()
   │   ├── NSApp.setActivationPolicy(.accessory)
   │   ├── Cria statusItem
   │   ├── Observa .speechServiceStatusChanged
   │   └── requestMicrophonePermission()
   │
   └── Status bar ícone aparece 🎤

2. Usuário clica no ícone
   ├── togglePopover() chamado
   └── Mostra StatusBarPopoverView

3. Usuário clica "Iniciar Gravação"
   ├── Task { await speechService.toggle() }
   ├── speechService.start()
   │   ├── Verifica permissão
   │   ├── Baixa modelo (se necessário)
   │   ├── Configura áudio
   │   └── Inicia transcrição
   │
   ├── status = .recording
   ├── Notificação .speechServiceStatusChanged
   ├── updateStatusBarIcon() → vermelho 🔴
   └── showTranscriptionModal()

4. Transcrição em andamento
   ├── Áudio → SpeechAnalyzer → SpeechTranscriber
   ├── Resultados:
   │   ├── Volátil → volatileText
   │   └── Final → transcript (ou comando)
   │
   └── UI atualiza em tempo real (@Observable)

5. Usuário para gravação
   ├── speechService.stop()
   ├── Finaliza áudio
   ├── Copia para clipboard (se ativo)
   ├── status = .idle
   ├── updateStatusBarIcon() → cinza 🎤
   └── closeTranscriptionModal()

6. App continua rodando
   └── Loop: aguarda clique no ícone

7. Usuário clica "Sair"
   └── NSApplication.shared.terminate(nil)
```

---

## Dependências entre Componentes

```
┌──────────────┐
│   voxApp     │
└──────┬───────┘
       │ owns
       ▼
┌──────────────┐      creates      ┌─────────────────┐
│ AppDelegate  │ ─────────────────→│  NSStatusItem   │
└──────┬───────┘                   └─────────────────┘
       │
       │ owns
       ▼
┌────────────────┐     observes    ┌──────────────────┐
│ SpeechService  │←─────────────────│ NotificationCenter│
└────────┬───────┘                 └──────────────────┘
         │
         │ uses
         ├─────────────┬──────────────┬─────────────┐
         ▼             ▼              ▼             ▼
┌──────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐
│AVAudioEngine │ │  Speech  │ │  Speech  │ │ NSPasteboard │
│              │ │ Analyzer │ │Transcriber│ │              │
└──────────────┘ └──────────┘ └──────────┘ └──────────────┘

┌──────────────┐
│ AppDelegate  │ creates & shows
└──────┬───────┘
       ├─────────────────────┬─────────────────────┐
       ▼                     ▼                     ▼
┌─────────────┐  ┌────────────────────┐  ┌──────────────┐
│  NSPopover  │  │TranscriptionWindow │  │Settings Window│
└──────┬──────┘  └─────────┬──────────┘  └──────┬───────┘
       │                   │                     │
       │ contains          │ contains            │ contains
       ▼                   ▼                     ▼
┌─────────────────┐ ┌─────────────────────┐ ┌────────────┐
│StatusBarPopover │ │TranscriptionModal   │ │Settings    │
│     View        │ │      View           │ │  View      │
└─────────────────┘ └─────────────────────┘ └────────────┘
```

---

## Observability e State Management

```
@Observable class SpeechService
    │
    ├─ status: Status (observado)
    │  └─ didSet → NotificationCenter.post(.speechServiceStatusChanged)
    │
    ├─ transcript: String (observado)
    │  └─ Binding em Views
    │
    └─ volatileText: String (observado)
       └─ Binding em Views

@EnvironmentObject speechService
    │
    ├─ StatusBarPopoverView acessa
    ├─ TranscriptionModalView acessa
    └─ Mudanças propagam automaticamente
```

---

## Threads e Concorrência

```
┌─────────────────┐
│   Main Thread   │  (@MainActor)
│                 │
│  • AppDelegate  │
│  • All Views    │
│  • UI Updates   │
└────────┬────────┘
         │
         │ Task { await ... }
         │
         ▼
┌─────────────────────┐
│  Swift Concurrency  │
│                     │
│  • SpeechService    │
│    async functions  │
│                     │
│  • start()          │
│  • stop()           │
│  • toggle()         │
└────────┬────────────┘
         │
         │ Audio callbacks
         │
         ▼
┌─────────────────────┐
│   Audio Thread      │  (não isolado)
│                     │
│  • installTap()     │
│  • Processa buffer  │
│  • Converte áudio   │
│  • Yield to stream  │
└─────────────────────┘

AsyncStream
    ↓
SpeechAnalyzer/Transcriber (background)
    ↓
for await result (assíncrono)
    ↓
@MainActor update UI
```

---

## Segurança e Permissões

```
┌────────────────────────────────┐
│      App Sandbox (macOS)       │
│                                │
│  ✅ Microphone Access          │
│  ✅ Audio Input                │
│  ❌ Network (não necessário)   │
│  ❌ Files (não necessário)     │
│                                │
└────────────────────────────────┘
         │
         │ NSMicrophoneUsageDescription
         ▼
┌────────────────────────────────┐
│   Permissão do Usuário         │
│                                │
│   [  ] Vox deseja acessar      │
│        seu microfone           │
│                                │
│   [ Não Permitir ]  [ OK ]     │
└────────────────────────────────┘
         │
         │ if granted
         ▼
┌────────────────────────────────┐
│   AVAudioEngine pode capturar  │
│   Speech pode transcrever      │
└────────────────────────────────┘
```

---

## Resumo da Arquitetura

**Padrão**: Model-View-Controller + Observable
**UI Framework**: SwiftUI
**State Management**: @Observable + @EnvironmentObject + @AppStorage
**Concorrência**: Swift Concurrency (async/await, AsyncStream)
**Áudio**: AVFoundation (AVAudioEngine)
**Transcrição**: Speech Framework (SpeechAnalyzer/Transcriber)
**Sistema**: AppKit (NSStatusItem, NSPopover, NSWindow)

**Princípios**:
- ✅ Separação de responsabilidades
- ✅ Estado observável e reativo
- ✅ Código assíncrono seguro
- ✅ UI declarativa
- ✅ Mínima superfície de API pública
- ✅ Privacidade by design (on-device)
