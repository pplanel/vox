# 🎯 COMANDOS PRONTOS - Copy & Paste

## 🚨 O app não aparece nas permissões de microfone?

Acabei de criar o arquivo **`Info.plist`** com todas as permissões necessárias.

---

## ✅ Execute Estes Comandos (Copy/Paste)

### 1️⃣ Limpar Cache e Permissões (Terminal)

```bash
# Copie e cole tudo de uma vez:

# Fechar Xcode se estiver aberto
killall Xcode 2>/dev/null || true

# Limpar DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData

# Reset permissões de microfone
tccutil reset Microphone 2>/dev/null || sudo tccutil reset Microphone

# Reiniciar processo de permissões
killall tccd 2>/dev/null

echo "✅ Cache limpo! Agora configure no Xcode."
```

---

### 2️⃣ No Xcode (Interface Gráfica)

**Abra o Xcode e faça na ordem:**

#### A. Adicionar Info.plist ao Projeto

```
1. No Finder, encontre o arquivo "Info.plist" na pasta do projeto
2. Arraste o arquivo para dentro do Xcode (na lista de arquivos)
3. Na janela que abrir:
   ✅ Marque "Copy items if needed"
   ✅ Marque "Add to targets: vox"
4. Clique "Add"
```

#### B. Configurar Build Settings

```
1. Clique no projeto "vox" (ícone azul, topo esquerdo)
2. Selecione TARGET "vox"
3. Aba "Build Settings"
4. Procure por: "Info.plist File" (use Cmd+F)
5. Clique duas vezes no valor
6. Digite: Info.plist
7. Pressione Enter
```

#### C. Configurar App Sandbox

```
1. TARGET "vox" → aba "Signing & Capabilities"
2. Se não tiver "App Sandbox":
   - Clique em "+ Capability"
   - Adicione "App Sandbox"
3. Em "Hardware", marque:
   ✅ Microphone
   ✅ Audio Input
```

#### D. Clean Build

```
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Aguarde terminar
3. Product → Build (Cmd+B)
4. Verifique se NÃO há erros
5. Product → Run (Cmd+R)
```

---

### 3️⃣ Verificar Permissão (macOS)

```
1. Quando o app executar, o alerta deve aparecer
2. Clique em "OK" ou "Allow"
3. Abra: System Settings → Privacy & Security → Microphone
4. O "vox" deve aparecer na lista! ✅
```

---

## 🔧 Se Der Erro "Info.plist not found"

**Execute no Terminal (na pasta do projeto):**

```bash
# Verificar se o Info.plist existe
ls -la Info.plist

# Deve mostrar: -rw-r--r--  1 user  staff  1234 Nov  2 12:00 Info.plist
```

**Se não existir, crie manualmente:**

```bash
# Copie e cole este comando completo:
cat > Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSMicrophoneUsageDescription</key>
	<string>O Vox precisa acessar o microfone para transcrever sua voz em texto.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>O Vox usa reconhecimento de fala para transcrever suas palavras em tempo real.</string>
	<key>LSUIElement</key>
	<false/>
</dict>
</plist>
EOF

echo "✅ Info.plist criado!"
```

---

## 🎯 Checklist Rápido

```
[ ] 1. Executei os comandos de limpeza no Terminal
[ ] 2. Adicionei Info.plist ao projeto Xcode
[ ] 3. Configurei Build Settings → Info.plist File
[ ] 4. Ativei App Sandbox
[ ] 5. Marquei Microphone e Audio Input
[ ] 6. Fiz Clean Build (Cmd+Shift+K)
[ ] 7. Fiz Build (Cmd+B) - sem erros
[ ] 8. Fiz Run (Cmd+R)
[ ] 9. Alerta de permissão apareceu
[ ] 10. App aparece em System Settings → Microphone ✅
```

---

## 🐛 Troubleshooting Rápido

### Erro: "Multiple commands produce Info.plist"

**Solução:**
```
1. TARGET "vox" → Build Phases
2. Copy Bundle Resources
3. Remova qualquer Info.plist duplicado
4. Mantenha apenas um
5. Clean Build
```

### App não compila após adicionar Info.plist

**Solução:**
```bash
# Terminal
rm -rf ~/Library/Developer/Xcode/DerivedData
killall Xcode

# Abra o Xcode novamente
# Product → Clean Build Folder
# Product → Build
```

### App compila mas não aparece nas permissões

**Verificar se Info.plist foi incluído:**
```bash
# Terminal - encontrar o app compilado
find ~/Library/Developer/Xcode/DerivedData -name "vox.app" -type d 2>/dev/null | head -1

# Copie o caminho e verifique:
# (Substitua [CAMINHO] pelo resultado acima)
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" [CAMINHO]/Contents/Info.plist
```

Se mostrar a descrição = OK ✅  
Se der erro = Info.plist não foi incluído ❌

**Nesse caso:**
```
1. TARGET "vox" → Build Phases → Copy Bundle Resources
2. Clique no "+"
3. Adicione o Info.plist
4. Clean Build e Run novamente
```

---

## 💡 Última Opção: Bundle ID Novo

Se **NADA** funcionar, force um novo Bundle ID:

```
1. TARGET "vox" → General
2. Bundle Identifier: 
   De: com.seuNome.vox
   Para: com.seuNome.vox.novo
3. Clean Build
4. Run
```

Isso força o macOS a ver como um app completamente novo.

---

## 🎤 Resumo Ultra-Rápido

```bash
# 1. Terminal (limpar)
rm -rf ~/Library/Developer/Xcode/DerivedData && tccutil reset Microphone && killall tccd

# 2. Xcode
# - Arrastar Info.plist para o projeto
# - Build Settings → Info.plist File = "Info.plist"
# - Signing & Capabilities → App Sandbox → Microphone ✅

# 3. Build
# Cmd+Shift+K → Cmd+B → Cmd+R

# 4. ✅ Funciona!
```

---

## 📞 Precisa de Ajuda?

**Arquivos de Documentação:**
- `CONFIGURE_INFO_PLIST_AGORA.md` - Guia completo passo a passo
- `FIX_PERMISSAO_MICROFONE.md` - Troubleshooting detalhado
- `SOLUCAO_RAPIDA_PERMISSAO.md` - Solução visual rápida

---

**Siga os comandos acima e o app VAI aparecer nas permissões! 🚀**

Me avise quando o "vox" aparecer na lista de microfone! 🎤
