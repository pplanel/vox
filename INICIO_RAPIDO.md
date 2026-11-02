# 🚀 GUIA RÁPIDO DE INÍCIO - Vox

## ⚡ 5 Minutos para Começar

### Passo 1: Configurar Info.plist (2 min)

Abra o arquivo `Info.plist` do projeto e adicione:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>O Vox precisa acessar o microfone para transcrever sua voz em texto.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>O Vox usa reconhecimento de fala para transcrever suas palavras em tempo real.</string>
```

**Como fazer:**
1. No Xcode, encontre `Info.plist` no navegador de arquivos
2. Clique com botão direito → Open As → Source Code
3. Cole as linhas acima antes do `</dict>` final
4. Salve (Cmd+S)

---

### Passo 2: Configurar Capabilities (1 min)

1. Selecione o **target** do projeto (ícone azul do app)
2. Vá para aba **Signing & Capabilities**
3. Clique no **+ Capability**
4. Adicione **App Sandbox**
5. Na seção App Sandbox que apareceu, marque:
   - ✅ **Audio Input**
   - ✅ **Microphone**

---

### Passo 3: Deletar Arquivos Não Usados (30 seg)

No navegador de arquivos do Xcode:
1. **Clique com botão direito** em `ContentView.swift` → Delete → Move to Trash
2. **Clique com botão direito** em `Persistence.swift` → Delete → Move to Trash
3. Se existir `vox.xcdatamodeld` → Delete → Move to Trash

---

### Passo 4: Verificar Deployment Target (30 seg)

1. Selecione o **target** do projeto
2. Aba **General**
3. Em **Minimum Deployments**, macOS deve estar **15.0**
4. Se estiver diferente, mude para 15.0

---

### Passo 5: Build & Run! (1 min)

1. **Clean Build Folder**: Cmd+Shift+K
2. **Build**: Cmd+B (espere compilar sem erros)
3. **Run**: Cmd+R

**O que deve acontecer:**
- ✅ App inicia
- ✅ Ícone aparece na status bar (próximo ao relógio)
- ✅ Não aparece no Dock

---

## 🎯 Primeiro Uso

1. **Clique** no ícone na status bar
2. Aparece um **popover** com opções
3. Clique **"Iniciar Gravação"**
4. **Primeira vez**: Solicita permissão do microfone
5. Clique **"OK"** ou **"Permitir"**
6. Ícone fica **vermelho** 🔴
7. Uma **janela** aparece mostrando a transcrição
8. **Fale** algo em português
9. Texto aparece em **tempo real**!
10. Clique **"Parar"** quando terminar
11. Texto é **copiado** para o clipboard automaticamente
12. **Cole** (Cmd+V) em qualquer app!

---

## 🗣️ Teste os Comandos de Voz

Com a gravação ativa, tente:

- **"vox novo parágrafo"** - Adiciona quebra de linha
- **"vox limpar"** - Limpa o texto
- **"vox copiar"** - Copia para clipboard
- **"vox parar"** - Para a gravação

---

## ⚙️ Abrir Configurações

1. Clique no ícone na status bar
2. Clique **"Ajustes..."**
3. Explore as 3 abas:
   - **Geral**: Auto-copy, modal, etc.
   - **Comandos de Voz**: Ativar/desativar, mudar prefixo
   - **Sobre**: Info do app

---

## 🚨 Se Algo Der Errado

### Erro ao compilar?
- Verificar que deployment target é **15.0**
- Clean Build Folder (Cmd+Shift+K)
- Fechar e reabrir Xcode

### Permissão negada?
1. System Settings → Privacy & Security → Microphone
2. Ativar toggle para **vox**
3. Reiniciar app

### Não transcreve?
- Falar em **português** (ou mudar idioma do sistema)
- Aguardar download do modelo (primeira vez)
- Verificar volume do microfone em System Settings → Sound

### Mais problemas?
Ver arquivo **TROUBLESHOOTING.md** para soluções detalhadas.

---

## 📚 Documentação Completa

Criamos documentação extensiva para você:

| Arquivo | Conteúdo |
|---------|----------|
| **RESUMO_EXECUTIVO.md** | ✅ Resumo completo do que foi implementado |
| **README.md** | 📖 Documentação geral do projeto |
| **CHECKLIST.md** | ✓ Lista de tudo para testar |
| **TROUBLESHOOTING.md** | 🔧 Soluções para problemas comuns |
| **PROJECT_SETUP.md** | ⚙️ Configuração detalhada |
| **ICONS_GUIDE.md** | 🎨 Como adicionar ícones personalizados |
| **MUDANCAS.md** | 📝 Todas as mudanças implementadas |

---

## ✅ Checklist Ultra-Rápido

Antes de rodar:
- [ ] Info.plist com NSMicrophoneUsageDescription? ✓
- [ ] Capabilities: App Sandbox + Microphone? ✓
- [ ] Deletou ContentView.swift e Persistence.swift? ✓
- [ ] Deployment target 15.0? ✓
- [ ] Clean build? ✓

Se todos ✓ → **Cmd+R e use!** 🚀

---

## 🎓 Dica Pro

Adicione um **atalho de teclado global** (futuro):
- Gravar de qualquer app sem precisar clicar
- Exemplo: Cmd+Shift+V para iniciar/parar
- Ver `MUDANCAS.md` para ideias de implementação

---

## 🎉 Pronto!

Você agora tem um **app de transcrição de voz** completamente funcional!

**Principais recursos:**
- 🎤 Transcrição em tempo real
- 🔴 Ícone visual na status bar
- 📋 Auto-copy para clipboard
- 🗣️ Comandos de voz
- 🔒 100% privado (on-device)

**Aproveite! 🚀**

---

**Dúvidas?** Consulte os arquivos de documentação listados acima.
