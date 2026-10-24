# Sela's logo

A river stone holding still while the current bends around it.

- `app-icon.svg` is the macOS app icon, drawn on Apple's grid: an 824 point tile at 100,100 on a 1024 canvas.
- `favicon.svg` is the same picture at full bleed, with heavier currents so it reads at 16 pixels. The website and `assets/icon.svg` use it.
- `app-icon-1024.png` is the master the app's icon sizes come from.
- `concepts/` holds the generated sheets the design was picked from. They are references, not artwork.

To rebuild the app icons after changing `app-icon.svg`, render it at 1024 pixels with a browser, then resize it into `app/Sela/Assets.xcassets/AppIcon.appiconset`.
