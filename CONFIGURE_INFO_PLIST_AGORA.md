# 🚨 AÇÃO NECESSÁRIA: Configurar Info.plist no Xcode

## ✅ Arquivo Info.plist Criado!

Acabei de criar o arquivo **`Info.plist`** na raiz do projeto com todas as permissões necessárias.

---

## 📋 PRÓXIMOS PASSOS (Faça Agora)

### 1️⃣ Adicionar o Info.plist ao Projeto Xcode

**No Xcode:**

1. **Arraste o arquivo `Info.plist`** do Finder para dentro do Xcode
   - OU clique com botão direito no projeto → "Add Files to vox..."
   - Selecione o `Info.plist` que está na raiz do projeto
   - ✅ Marque "Copy items if needed"
   - ✅ Marque "Add to targets: vox"
   - Clique em **"Add"**

---

### 2️⃣ Configurar o Target para Usar Este Info.plist

**No Xcode:**

1. Clique no projeto **"vox"** (topo esquerdo, ícone azul)
2. Selecione o **TARGET "vox"** (não o projeto)
3. Clique na aba **"Build Settings"**
4. Procure por: **"Info.plist File"** (use a busca)
5. Clique duas vezes no valor
6. Digite: **`Info.plist`** (ou `vox/Info.plist` se estiver dentro de uma pasta)
7. Pressione Enter

**Deve ficar assim:**
```
Info.plist File: Info.plist
```

---

### 3️⃣ Configurar App Sandbox

**No Xcode:**

1. TARGET "vox" → aba **"Signing & Capabilities"**
2. Se **NÃO** tiver "App Sandbox":
   - Clique em **"+ Capability"** (canto superior esquerdo)
   - Procure e adicione **"App Sandbox"**
3. Dentro do **App Sandbox**, na seção **"Hardware"**, marque:
   - ✅ **Microphone**
   - ✅ **Audio Input**

---

### 4️⃣ Limpar Cache e Permissões

**No Terminal:**

```bash
# Limpar DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData

# Reset permissões de microfone
tccutil reset Microphone

# Reiniciar processo de permissões
killall tccd
```

**OU execute o script:**

```bash
./limpar_permissoes.sh
```

---

### 5️⃣ Rebuild Completo

**No Xcode:**

1. **Product → Clean Build Folder** (Cmd+Shift+K)
2. Aguarde terminar (veja a barra de progresso)
3. **Product → Build** (Cmd+B)
4. Verifique se **NÃO há erros**
5. **Product → Run** (Cmd+R)

---

### 6️⃣ Testar Permissão

Quando o app executar:

1. O **alerta de permissão** deve aparecer
2. Clique em **"OK"** ou **"Allow"**
3. Abra: **System Settings → Privacy & Security → Microphone**
4. O **"vox"** deve aparecer na lista! ✅

---

## 🎯 Checklist Visual

```
[ ] 1. Info.plist adicionado ao projeto Xcode
[ ] 2. TARGET "vox" → Build Settings → Info.plist File = "Info.plist"
[ ] 3. TARGET "vox" → Signing & Capabilities → App Sandbox ativo
[ ] 4. App Sandbox → Microphone marcado ✅
[ ] 5. App Sandbox → Audio Input marcado ✅
[ ] 6. Executei: rm -rf ~/Library/Developer/Xcode/DerivedData
[ ] 7. Executei: tccutil reset Microphone
[ ] 8. Executei: killall tccd
[ ] 9. Clean Build (Cmd+Shift+K)
[ ] 10. Build (Cmd+B) - SEM ERROS
[ ] 11. Run (Cmd+R)
[ ] 12. Alerta de permissão apareceu
[ ] 13. Cliquei em "OK"
[ ] 14. App aparece em System Settings → Microphone ✅
```

---

## 📸 Referência Visual

### Onde Adicionar o Info.plist:

```
Xcode Project Navigator:
├── 📁 vox
│   ├── 📄 voxApp.swift
│   ├── 📄 AppDelegate.swift
│   ├── 📄 SpeechService.swift
│   ├── 📄 Info.plist           ← ADICIONE AQUI
│   └── ...
```

### Build Settings:

```
Target vox → Build Settings
Procure: "Info.plist File"
Valor: Info.plist                ← CONFIGURE AQUI
```

### Signing & Capabilities:

```
Target vox → Signing & Capabilities
├── App Sandbox
│   ├── Hardware
│   │   ├── ☑️ Microphone       ← MARQUE AQUI
│   │   └── ☑️ Audio Input      ← MARQUE AQUI
```

---

## 🐛 Troubleshooting

### "Info.plist not found" ao compilar

**Solução:**
1. Verifique o caminho em Build Settings
2. Se o Info.plist está dentro de uma pasta "vox", use: `vox/Info.plist`
3. Se está na raiz, use apenas: `Info.plist`

### "Duplicate Info.plist entries"

**Solução:**
1. TARGET "vox" → Info tab
2. Delete as entradas duplicadas (se houver)
3. Mantenha apenas o Info.plist file

### App ainda não aparece nas permissões

**Solução:**
1. Verifique se o Info.plist foi incluído no Build:
   - TARGET "vox" → Build Phases → Copy Bundle Resources
   - O Info.plist deve aparecer lá
2. Se não estiver, arraste-o para lá
3. Clean Build novamente

---

## 🎯 Resultado Esperado

Após seguir todos os passos:

1. ✅ App compila sem erros
2. ✅ Alerta de permissão aparece ao executar
3. ✅ App aparece em System Settings → Privacy & Security → Microphone
4. ✅ Toggle do app está visível e pode ser ativado
5. ✅ Transcrição funciona quando permissão está ativa

---

## 📞 Se Ainda Não Funcionar

### Opção 1: Verificar o Info.plist Compilado

**No Terminal:**

```bash
# Encontrar o app compilado
find ~/Library/Developer/Xcode/DerivedData -name "vox.app" -type d 2>/dev/null

# Verificar se tem a descrição (substitua [CAMINHO] pelo resultado acima)
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" [CAMINHO]/Contents/Info.plist
```

Se mostrar a descrição = OK ✅  
Se der erro = Info.plist não foi incluído no build ❌

### Opção 2: Criar Novo Projeto

Se nada funcionar, pode haver corrupção no projeto. Nesse caso:

1. Crie um novo projeto macOS
2. Copie os arquivos .swift
3. Configure tudo novamente do zero

---

## 💡 Dica Importante

**Certifique-se de que o arquivo Info.plist está:**
1. ✅ No projeto Xcode (visível no navegador)
2. ✅ Configurado em Build Settings → Info.plist File
3. ✅ Incluído em Build Phases → Copy Bundle Resources

**Se faltar qualquer um desses, o app não terá as permissões necessárias!**

---

## 🚀 Comece Agora

**Execute estes comandos na ordem:**

```bash
# 1. Limpar cache
rm -rf ~/Library/Developer/Xcode/DerivedData
tccutil reset Microphone
killall tccd

# 2. No Xcode
# - Adicionar Info.plist ao projeto
# - Configurar Build Settings → Info.plist File
# - Ativar App Sandbox → Microphone
# - Clean Build (Cmd+Shift+K)
# - Run (Cmd+R)

# 3. Verificar
# System Settings → Privacy → Microphone → vox ✅
```

---

**Agora sim vai funcionar! 🎤✨**

Siga os passos acima e me diga se o app apareceu nas permissões!
