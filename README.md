# 🎤 Vox - Transcrição de Voz Minimalista para macOS

> Um aplicativo minimalista de transcrição de voz que vive na barra de status do macOS

[![macOS](https://img.shields.io/badge/macOS-15.0+-blue.svg)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-Custom-green.svg)](LICENSE)

---

## 🚀 Início Rápido (5 minutos)

```bash
# 1. Configure Info.plist (adicione NSMicrophoneUsageDescription)
# 2. Ative App Sandbox + Microphone nas Capabilities
# 3. Delete ContentView.swift e Persistence.swift
# 4. Build & Run!
```

**[📖 Guia Completo de Início Rápido →](INICIO_RAPIDO.md)**

---

## ✨ O que é o Vox?

---

## ✨ O que é o Vox?

Vox é um aplicativo de **transcrição de voz on-device** para macOS que:
- 🎤 Transcreve sua voz em **tempo real**
- 🔒 Funciona **100% offline** (após download inicial do modelo)
- 🎯 Interface **minimalista** - apenas um ícone na status bar
- 📋 Copia automaticamente para o **clipboard**
- 🗣️ Responde a **comandos de voz**
- 🔴 **Feedback visual** com mudança de cor do ícone

---

## 🎬 Demo Visual

```
Status Bar (próximo ao relógio):
┌─────────────────────────────────┐
│  🔊  🔋  [🎤]  🕐              │  ← Ícone do Vox
└─────────────────────────────────┘
         │
         │ Clique
         ▼
┌──────────────────────────┐
│  Status: Pronto          │
│  ─────────────────────   │
│  [▶ Iniciar Gravação]    │
│  [ Limpar ]              │
│  ─────────────────────   │
│  Ajustes... │ Sair       │
└──────────────────────────┘
         │
         │ Gravar
         ▼
┌────────────────────────────────────┐
│  🔴 Gravando... │ [⬛ Parar]       │
│  ──────────────────────────────── │
│                                    │
│  Olá, este é um teste de          │
│  transcrição em tempo real.       │
│                                    │
│  Está funcionando muito bem...    │
│                                    │
│  ──────────────────────────────── │
│  [📋 Copiar] [🗑️ Limpar] [⬛ Parar] │
└────────────────────────────────────┘
         │
         │ Parar
         ▼
📋 Texto copiado para clipboard!
```

---

## 🌟 Características

### 🎯 Design Minimalista
- **Sem janela principal**: O app funciona inteiramente pela barra de status
- **Sem ícone no Dock** - `NSApp.setActivationPolicy(.accessory)`
- **Ícone na status bar**: Localizado próximo ao relógio e outros ícones do sistema
- **Mudança de cor visual**: O ícone muda de cor durante a gravação
  - 🎤 Cinza: Pronto para gravar
  - 🟡 Amarelo: Preparando
  - 🔴 Vermelho: Gravando
  - ⚠️ Vermelho com barra: Erro

### 🎯 Design Minimalista
- **Sem janela principal**: O app funciona inteiramente pela barra de status
- **Ícone na status bar**: Localizado próximo ao relógio e outros ícones do sistema
- **Mudança de cor visual**: O ícone muda de cor durante a gravação
  - 🎤 Cinza: Pronto para gravar
  - 🟡 Amarelo: Preparando
  - 🔴 Vermelho: Gravando
  - ⚠️ Vermelho com barra: Erro

### 🎙️ Transcrição em Tempo Real
- Transcrição on-device usando Speech Framework da Apple
- Privacidade total: nada é enviado para servidores
- Suporte a português e outros idiomas suportados pelo macOS
- Texto volátil mostra o que está sendo falado em tempo real
- Texto finalizado é adicionado automaticamente

### 📋 Clipboard Automático
- Ao parar a gravação, o texto vai automaticamente para o clipboard
- Pode ser desativado nas configurações
- Comando de voz para copiar manualmente

### 🪟 Modal de Transcrição
- Quando não está focado em uma área de texto, abre modal no centro da tela
- Mostra o stream da transcrição em tempo real
- Scroll automático conforme o texto vai sendo adicionado
- Pode ser desativada nas configurações

### 🗣️ Comandos de Voz
Controle o app usando sua voz! Prefixo padrão: "vox"

- **"vox copiar"**: Copia o texto atual para o clipboard
- **"vox limpar"**: Limpa toda a transcrição
- **"vox parar"**: Para a gravação
- **"vox novo parágrafo"**: Adiciona quebra de linha
- **"vox apagar última frase"**: Remove a última frase

O prefixo pode ser personalizado nas configurações.

## Estrutura do Projeto

### Arquivos Principais

- **voxApp.swift**: Ponto de entrada do app, define a janela de Settings
- **AppDelegate.swift**: Gerencia a status bar, popover e modal de transcrição
- **SpeechService.swift**: Serviço de transcrição usando Speech Framework e AVFoundation
- **StatusBarPopoverView.swift**: UI do popover que aparece ao clicar no ícone da status bar
- **TranscriptionModalView.swift**: Modal que mostra a transcrição em tempo real
- **SettingsView.swift**: Janela de configurações com tabs (Geral, Comandos de Voz, Sobre)

### Arquivos Removidos/Desnecessários

- **ContentView.swift**: Não é mais usado (substituído pelo sistema de status bar)
- **Persistence.swift**: CoreData não é necessário para este app

## Requisitos

- macOS 15.0+ (Sequoia)
- Xcode 16+
- Swift 6.0+
- Microfone

## Configuração

Veja `PROJECT_SETUP.md` para instruções detalhadas sobre:
- Configuração do Info.plist
- Permissões necessárias
- Capabilities e entitlements
- Valores padrão do UserDefaults

## Como Usar

1. Execute o app - ele aparecerá na barra de status
2. Clique no ícone do microfone para abrir o menu
3. Clique em "Iniciar Gravação" (ou use Cmd+R)
4. Fale naturalmente
5. Use comandos de voz para controlar
6. Clique em "Parar Gravação" (ou use Cmd+S) quando terminar
7. O texto é copiado automaticamente para o clipboard

### Atalhos de Teclado

- **Cmd+R**: Iniciar gravação (quando popover está aberto)
- **Cmd+S**: Parar gravação (quando popover está aberto)

## Configurações

Acesse através do menu do popover → "Ajustes..."

### Aba Geral
- Iniciar gravação automaticamente ao abrir
- Copiar automaticamente para o clipboard
- Mostrar modal no Dock durante gravação
- Link para permissões de microfone

### Aba Comandos de Voz
- Ativar/desativar comandos de voz
- Personalizar prefixo de comando
- Lista de comandos disponíveis

### Aba Sobre
- Informações do app
- Versão

## Permissões

O app solicita as seguintes permissões:
- **Microfone**: Para capturar áudio
- **Reconhecimento de Fala**: Para transcrever o áudio

As permissões são solicitadas automaticamente na primeira execução. Se negadas, um alerta aparece com link direto para os Ajustes do Sistema.

## Privacidade

- ✅ Toda transcrição é feita on-device
- ✅ Nenhum dado é enviado para servidores
- ✅ Usa modelos de ML da Apple localmente
- ✅ Download automático de modelos de idioma se necessário

## Tecnologias Utilizadas

- **SwiftUI**: Interface do usuário
- **Speech Framework**: Transcrição de voz (SpeechAnalyzer/SpeechTranscriber)
- **AVFoundation**: Captura de áudio do microfone
- **AppKit**: Integração com status bar e sistema do macOS
- **Swift Concurrency**: async/await para operações assíncronas

## Autor

Pedro Planel - 2026

## Próximas Features (Sugestões)

- [ ] Atalho global de teclado para iniciar/parar gravação
- [ ] Histórico de transcrições
- [ ] Exportar para arquivo
- [ ] Mais comandos de voz
- [ ] Suporte para múltiplos idiomas simultâneos
- [ ] Integração com apps de texto (inserir diretamente)
- [ ] Temas de cor personalizáveis
