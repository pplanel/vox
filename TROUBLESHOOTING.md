# Troubleshooting - Vox

Soluções para problemas comuns.

## 🚫 App não compila

### Erro: "Cannot find 'SpeechAnalyzer' in scope"

**Causa**: SpeechAnalyzer/SpeechTranscriber requerem macOS 15.0+

**Solução**:
1. Abra projeto no Xcode
2. Selecione target → General
3. Minimum Deployments → macOS: **15.0**
4. Clean Build Folder (Cmd+Shift+K)
5. Build novamente (Cmd+B)

### Erro: "Cannot find type 'NSApplicationDelegateAdaptor'"

**Causa**: Import faltando

**Solução**: Verifique que `AppDelegate.swift` tem:
```swift
import AppKit
import SwiftUI
```

### Erro relacionado a @Observable

**Causa**: Requer Swift 5.9+ e macOS 14+

**Solução**: Verificar build settings:
- Swift Language Version: Swift 5.9 ou superior

## 🎤 Permissão de Microfone

### "Permissão de microfone negada" mesmo após conceder

**Causa**: Cache de permissões do macOS

**Solução**:
1. Fechar o app completamente
2. Ir em: System Settings → Privacy & Security → Microphone
3. **Remover** o Vox da lista (botão -)
4. Executar o app novamente
5. Conceder permissão quando solicitado

### App não solicita permissão

**Causa**: Info.plist sem NSMicrophoneUsageDescription

**Solução**:
1. Abrir Info.plist
2. Adicionar chave `NSMicrophoneUsageDescription`
3. Valor: "O Vox precisa acessar o microfone para transcrever sua voz em texto."
4. Clean Build Folder
5. Rebuild

### "Nenhum microfone disponível"

**Causa**: Microfone não conectado ou não detectado

**Solução**:
1. Verificar microfone conectado:
   - System Settings → Sound → Input
   - Deve mostrar microfone com barras de volume
2. Testar microfone em outro app (QuickTime, Voice Memos)
3. Reiniciar Mac se necessário

## 🎙️ Transcrição

### Não transcreve nada / Não aparece texto

**Causa 1**: Modelo de idioma não baixado

**Solução**:
- Aguardar status "Baixando modelo..."
- Requer conexão com internet na primeira vez
- Pode demorar alguns minutos

**Causa 2**: Idioma não suportado

**Solução**:
- Verificar idioma do sistema: System Settings → General → Language & Region
- Idiomas suportados: Português (BR/PT), Inglês, Espanhol, Francês, etc.
- Mudar para idioma suportado se necessário

**Causa 3**: Volume muito baixo

**Solução**:
- System Settings → Sound → Input
- Aumentar Input volume
- Falar mais perto do microfone

### Transcrição imprecisa

**Soluções**:
- Falar mais devagar e claramente
- Reduzir ruído ambiente
- Usar microfone de qualidade
- Verificar se idioma do sistema corresponde ao idioma falado

### Texto volátil não vira texto finalizado

**Causa**: Pausas muito curtas

**Solução**:
- Fazer pausas mais longas entre frases
- O sistema precisa de ~0.5-1s de silêncio para finalizar
- Usar pontuação falada: "ponto", "vírgula", "nova linha"

## 🪟 Interface

### Ícone não aparece na status bar

**Causa 1**: App crashou silenciosamente

**Solução**:
- Abrir Console.app
- Filtrar por "vox"
- Procurar crashes ou erros
- Corrigir conforme mensagem de erro

**Causa 2**: Status bar muito cheia

**Solução**:
- Remover outros ícones da status bar
- App pode estar escondido no menu overflow (>>)
- Cmd+arrastar outros ícones para fora

### Ícone aparece mas clique não faz nada

**Causa**: Erro no togglePopover

**Solução**:
1. Verificar console para erros
2. Verificar código em `AppDelegate.swift`:
```swift
button.action = #selector(togglePopover)
button.target = self
```

### Modal de transcrição não aparece

**Causa 1**: Configuração desativada

**Solução**:
- Abrir Settings → Geral
- Ativar "Mostrar modal no Dock durante gravação"

**Causa 2**: Janela atrás de outras

**Solução**:
- Procurar janela "Vox - Transcrição" em Mission Control
- Ou verificar código: `window.makeKeyAndOrderFront(nil)`

### Settings não abrem

**Causa**: Scene não configurada

**Solução**: Verificar `voxApp.swift`:
```swift
var body: some Scene {
    Settings {
        SettingsView()
    }
}
```

## 🗣️ Comandos de Voz

### Comandos não funcionam

**Causa 1**: Desativados nas settings

**Solução**:
- Settings → Comandos de Voz
- Ativar "Ativar comandos de voz"

**Causa 2**: Prefixo errado

**Solução**:
- Verificar prefixo em Settings
- Padrão: "vox"
- Falar claramente: "vox [comando]"
- Exemplo: "vox copiar"

**Causa 3**: Comando não reconhecido como frase final

**Solução**:
- Fazer pausa após comando
- Falar devagar e claramente
- Separar comando de outras frases

### "vox copiar" não copia

**Causa**: Transcript vazio

**Solução**:
- Verificar que há texto na transcrição
- Testar manualmente: copiar e colar em outro app

## 📋 Clipboard

### Texto não vai para clipboard ao parar

**Causa 1**: Configuração desativada

**Solução**:
- Settings → Geral
- Ativar "Copiar automaticamente para o clipboard"

**Causa 2**: Sandbox bloqueando

**Solução**: Verificar entitlements - não precisa de permissão especial para clipboard básico

### Clipboard só copia parte do texto

**Causa**: Encoding de caracteres

**Solução**: Verificar código em `SpeechService.swift`:
```swift
pasteboard.setString(transcript, forType: .string)
```

## 🔴 Erros Específicos

### "O modelo de transcrição não está disponível neste Mac"

**Causa**: Mac muito antigo ou macOS muito antigo

**Solução**:
- Verificar macOS 15.0+ (Sequoia)
- Verificar Mac com chip Apple Silicon ou Intel recente
- Alguns Macs mais antigos não suportam

### "Não foi possível converter o áudio do microfone"

**Causa**: Formato de áudio incompatível

**Solução**:
- Raro, geralmente problema com microfone específico
- Testar com microfone interno do Mac
- Reportar bug se persistir

### "Permissão de microfone negada. Libere em Ajustes do Sistema"

**Solução**:
1. Clicar no botão do alerta para abrir Settings
2. Ou manualmente: System Settings → Privacy & Security → Microphone
3. Ativar toggle para "vox"
4. Reiniciar app

## 🐛 Debug Avançado

### Ativar logs detalhados

Adicione breakpoints ou prints em:
- `SpeechService.swift` → `beginTranscription()`
- `AppDelegate.swift` → `handleRecordingStatusChange()`
- `SpeechService.swift` → processamento de resultados

### Usar Instruments

1. Xcode → Product → Profile (Cmd+I)
2. Escolher template:
   - **Leaks**: Detectar memory leaks
   - **Time Profiler**: Performance
   - **System Trace**: Chamadas do sistema

### Verificar notificações

Adicione observer temporário:
```swift
NotificationCenter.default.addObserver(
    forName: .speechServiceStatusChanged,
    object: nil,
    queue: .main
) { notification in
    print("📢 Status changed: \(notification)")
}
```

## 🆘 Ainda não funciona?

1. **Clean Build Folder**: Cmd+Shift+K
2. **Delete Derived Data**:
   - Xcode → Settings → Locations
   - Clicar seta em Derived Data
   - Deletar pasta do projeto
3. **Restart Xcode**
4. **Restart Mac**
5. **Verificar console** (Console.app) para erros específicos
6. **Criar novo projeto** e copiar código gradualmente

## 📞 Reportar Bug

Se encontrar bug não listado aqui, reúna:
- [ ] Versão do macOS
- [ ] Modelo do Mac
- [ ] Passos exatos para reproduzir
- [ ] Mensagem de erro completa (se houver)
- [ ] Logs do Console.app
- [ ] Screenshots se relevante

## ✅ Verificação Rápida

Lista de verificação rápida se algo não funciona:

- [ ] macOS 15.0+?
- [ ] Deployment target 15.0?
- [ ] Info.plist com NSMicrophoneUsageDescription?
- [ ] Entitlements com microphone = true?
- [ ] App Sandbox ativado?
- [ ] Permissão concedida em System Settings?
- [ ] Microfone funciona em outros apps?
- [ ] Todos os arquivos adicionados ao target?
- [ ] Clean build feito?

Se todos marcados e ainda não funciona, revisar código fonte ou criar novo projeto.
