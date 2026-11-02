# Checklist Final - Vox

## ✅ Arquivos para DELETAR do Projeto

Estes arquivos não são mais necessários e podem ser removidos:

- [ ] `ContentView.swift` - Substituído pelo sistema de status bar
- [ ] `Persistence.swift` - CoreData não é usado
- [ ] `vox.xcdatamodeld` - CoreData não é usado (se existir)

## ✅ Configurações do Xcode

### Info.plist
- [ ] Adicionar `NSMicrophoneUsageDescription`
- [ ] Adicionar `NSSpeechRecognitionUsageDescription`

### Target Settings

#### General
- [ ] Deployment Target: macOS 15.0
- [ ] App Category: Productivity

#### Signing & Capabilities
- [ ] Adicionar **App Sandbox**
- [ ] Marcar **Audio Input** ✓
- [ ] Marcar **Microphone** ✓

#### Entitlements (Verificar arquivo .entitlements)
- [ ] `com.apple.security.device.audio-input` = true
- [ ] `com.apple.security.device.microphone` = true

## ✅ Arquivos Adicionados ao Projeto

Certifique-se de que estes arquivos foram adicionados ao target:

- [ ] `AppDelegate.swift`
- [ ] `StatusBarPopoverView.swift`
- [ ] `SettingsView.swift`
- [ ] `TranscriptionModalView.swift`

Arquivos de documentação (não precisam estar no target):
- [ ] `README.md`
- [ ] `PROJECT_SETUP.md`
- [ ] `MUDANCAS.md`
- [ ] `CHECKLIST.md` (este arquivo)

## ✅ Testes Funcionais

### Primeira Execução
- [ ] App inicia sem crashes
- [ ] Ícone aparece na status bar (não no Dock)
- [ ] Clicar no ícone abre o popover
- [ ] Solicita permissão de microfone
- [ ] Se negado, mostra alerta com link para Settings

### Gravação Básica
- [ ] Clicar "Iniciar Gravação" funciona
- [ ] Ícone fica vermelho durante gravação
- [ ] Modal de transcrição aparece
- [ ] Falar produz texto na modal
- [ ] Texto volátil aparece em itálico
- [ ] Texto finalizado aparece normal
- [ ] Parar gravação funciona
- [ ] Texto é copiado para clipboard

### Settings
- [ ] Menu "Ajustes..." abre janela
- [ ] Tab "Geral" funciona
- [ ] Tab "Comandos de Voz" funciona
- [ ] Tab "Sobre" funciona
- [ ] Toggles salvam valores
- [ ] TextField do prefixo salva valor
- [ ] Link para Settings do Sistema funciona

### Comandos de Voz
Ativar "Comandos de Voz" nas Settings e testar:
- [ ] "vox copiar" - copia texto
- [ ] "vox limpar" - limpa transcrição
- [ ] "vox parar" - para gravação
- [ ] "vox novo parágrafo" - adiciona quebra de linha
- [ ] "vox apagar última frase" - remove última frase

### Configurações
Testar se as configurações funcionam:
- [ ] Desativar "Mostrar modal no Dock" - modal não aparece
- [ ] Desativar "Copiar automaticamente" - não copia ao parar
- [ ] Desativar "Comandos de voz" - comandos não funcionam
- [ ] Mudar prefixo de comando - novos comandos funcionam

### Atalhos de Teclado
Com popover aberto:
- [ ] Cmd+R inicia gravação
- [ ] Cmd+S para gravação

### Estados de Erro
- [ ] Negar permissão de microfone - mostra erro adequado
- [ ] Desconectar microfone durante gravação - mostra erro

## 🐛 Problemas Conhecidos a Verificar

- [ ] Modal fecha corretamente ao parar gravação?
- [ ] Popover fecha ao clicar fora?
- [ ] App responde a mudanças de idioma do sistema?
- [ ] Múltiplas sessões de gravação funcionam?
- [ ] Memory leaks? (usar Instruments)

## 📋 Melhorias Futuras (Opcional)

- [ ] Adicionar atalho global (Hot Key)
- [ ] Histórico de transcrições
- [ ] Exportar para arquivo
- [ ] Mais comandos de voz customizáveis
- [ ] Temas de cor
- [ ] Inserir texto diretamente em apps focados

## 🎨 Assets

- [ ] Adicionar ícone do app (AppIcon)
- [ ] Considerar ícones personalizados para status bar

## 📦 Distribuição (Futuro)

- [ ] Configurar version/build number
- [ ] Testar em máquina limpa
- [ ] Archive e Export
- [ ] Notarização Apple (para distribuição)

---

## Ordem Recomendada de Execução

1. **Deletar arquivos não usados**
2. **Configurar Info.plist**
3. **Configurar Capabilities**
4. **Build & Run**
5. **Testar primeira execução**
6. **Testar gravação básica**
7. **Testar comandos de voz**
8. **Testar configurações**
9. **Verificar problemas conhecidos**

## Dicas de Debug

Se algo não funcionar:

1. **Permissão negada?**
   - Ir em: System Settings → Privacy & Security → Microphone
   - Verificar se o app está listado e marcado

2. **Modal não aparece?**
   - Verificar "Mostrar modal no Dock" nas Settings
   - Verificar console para erros

3. **Comandos de voz não funcionam?**
   - Verificar se estão ativados nas Settings
   - Verificar prefixo de comando
   - Falar claramente o prefixo + comando

4. **Ícone não muda de cor?**
   - Verificar console - notificação está sendo enviada?
   - Verificar método `updateStatusBarIcon()`

5. **Crash ao iniciar?**
   - Verificar se todos os arquivos estão no target
   - Verificar imports necessários
   - Verificar console para erro específico
