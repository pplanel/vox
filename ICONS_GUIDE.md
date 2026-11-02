# Adicionando Ícone Personalizado ao Vox

## Ícone da Status Bar

Para um visual mais profissional, você pode criar ícones personalizados para a status bar.

### Especificações

- **Tamanho**: 16x16 pt ou 22x22 pt (32x32 ou 44x44 pixels @2x)
- **Formato**: Template image (preto e transparente)
- **Estilo**: Simple, claro, reconhecível

### Criando o Ícone

1. Use SF Symbols como base ou crie no Figma/Sketch
2. Exporte como PDF ou PNG @1x, @2x, @3x
3. Adicione ao Assets.xcassets

### Usando no Código

Em `AppDelegate.swift`, substitua:

```swift
private func updateStatusBarIcon() {
    guard let button = statusItem?.button else { return }
    
    let iconName: String
    let tintColor: NSColor
    
    switch speechService.status {
    case .recording:
        iconName = "mic.fill" // ou "statusbar-recording"
        tintColor = .systemRed
    case .preparing, .downloadingModel:
        iconName = "mic" // ou "statusbar-preparing"
        tintColor = .systemYellow
    case .error:
        iconName = "mic.slash" // ou "statusbar-error"
        tintColor = .systemRed
    case .idle:
        iconName = "mic" // ou "statusbar-idle"
        tintColor = .controlTextColor
    }
    
    // Para SF Symbols
    let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        button.image = image
        button.contentTintColor = tintColor
    }
    
    // OU para imagens personalizadas
    // if let image = NSImage(named: iconName) {
    //     image.isTemplate = true
    //     button.image = image
    //     button.contentTintColor = tintColor
    // }
}
```

## AppIcon

Para o ícone do aplicativo (que aparece no Finder, etc):

### Especificações macOS

- 16x16
- 32x32
- 64x64
- 128x128
- 256x256
- 512x512
- 1024x1024

### Ferramentas Recomendadas

- SF Symbols (base)
- [Icon Set Creator](https://apps.apple.com/app/icon-set-creator/id939343785)
- Figma + [AppIconBuilder](https://www.appicon.build/)
- Sketch

### Adicionando ao Projeto

1. Abra Assets.xcassets
2. Clique em AppIcon
3. Arraste as imagens para os tamanhos correspondentes

### Design Sugerido

Para um app de transcrição:
- Microfone estilizado
- Ondas sonoras
- Bolha de diálogo
- Cores: Azul, roxo, ou gradiente moderno

## Template SVG de Exemplo

```svg
<!-- statusbar-mic.svg -->
<svg width="22" height="22" viewBox="0 0 22 22" xmlns="http://www.w3.org/2000/svg">
  <path d="M11 2C9.34315 2 8 3.34315 8 5V11C8 12.6569 9.34315 14 11 14C12.6569 14 14 12.6569 14 11V5C14 3.34315 12.6569 2 11 2Z" fill="black"/>
  <path d="M6 9V11C6 13.7614 8.23858 16 11 16C13.7614 16 16 13.7614 16 11V9H18V11C18 14.866 14.866 18 11 18C7.13401 18 4 14.866 4 11V9H6Z" fill="black"/>
  <path d="M10 18V21H12V18H10Z" fill="black"/>
  <path d="M7 21H15V20H7V21Z" fill="black"/>
</svg>
```

Para converter SVG para assets do Xcode:
1. Use [SF Symbols App](https://developer.apple.com/sf-symbols/) para criar custom symbols
2. Ou use ferramentas online como [CloudConvert](https://cloudconvert.com/svg-to-png)
3. Exporte para PNG @1x, @2x, @3x

## Exemplo Completo com Assets

Estrutura no Assets.xcassets:

```
Assets.xcassets/
├── AppIcon.appiconset/
│   ├── icon_16x16.png
│   ├── icon_16x16@2x.png
│   ├── icon_32x32.png
│   ├── icon_32x32@2x.png
│   ├── icon_128x128.png
│   ├── icon_128x128@2x.png
│   ├── icon_256x256.png
│   ├── icon_256x256@2x.png
│   ├── icon_512x512.png
│   ├── icon_512x512@2x.png
│   └── Contents.json
└── StatusBarIcons/
    ├── statusbar-idle.imageset/
    │   ├── idle.pdf (vector)
    │   └── Contents.json
    ├── statusbar-recording.imageset/
    │   ├── recording.pdf (vector)
    │   └── Contents.json
    └── statusbar-error.imageset/
        ├── error.pdf (vector)
        └── Contents.json
```

## Dicas de Design

1. **Simplicidade**: Status bar icons devem ser simples e reconhecíveis
2. **Template Images**: Use preto sólido e transparente - o macOS aplica a cor
3. **Teste em Dark/Light Mode**: Certifique-se de que funciona em ambos
4. **Tamanho Consistente**: Mantenha o mesmo tamanho visual entre estados
5. **Acessibilidade**: Teste com VoiceOver - adicione descriptions

## Alternativa: Animações

Para feedback visual mais rico, considere animar o ícone:

```swift
private func animateStatusBarIcon() {
    guard let button = statusItem?.button else { return }
    
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.3
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.animator().alphaValue = 0.5
    } completionHandler: {
        button.animator().alphaValue = 1.0
    }
}
```

Chame `animateStatusBarIcon()` quando mudar de estado para dar feedback visual.
