# Assets

Todo lo que hay aquí es editable y es lo que usa el juego directamente.

| Carpeta | Contenido | Cómo editarlo |
|---|---|---|
| `character/src/*.obj` | Prendas, pelo, accesorios y caras del personaje (fuente) | Blender u otro editor 3D (exportar como OBJ) |
| `character/Textures_4.png` | Paleta/textura del personaje | Cualquier editor de imágenes; mantén el tamaño y la disposición de los swatches |
| `character/skater_skater.res` | Malla **generada**, no editar a mano | Se regenera con el script de `tools/` |
| `fonts/` | Fuentes (OFL) | Sustituir el `.ttf` manteniendo el nombre |
| `audio/ambient.mp3` | Música ambiente | Sustituir el fichero manteniendo el nombre |
| `audio/sfx/*.wav` | Efectos de sonido del skater | Ver [audio/README.md](audio/README.md) |

Los ficheros `.import` los genera Godot; se versionan para que el import sea reproducible.

## Regenerar el personaje

Tras cambiar un `.obj` de `character/src/` o la textura:

```bash
godot --headless --path . -s tools/build_character.gd
```

Esto reconstruye `character/skater_skater.res`. Qué prendas se usan (y su
recoloreado/holgura) se define en `OUTFIT_PARTS` en `scripts/character_rig.gd`.

## Añadir assets nuevos

1. Colócalos en la carpeta que corresponda.
2. Apunta autor, fuente y licencia en [CREDITS.md](CREDITS.md).
3. Si el original está en un formato pesado (.blend, .psd), súbelo en `assets/source/`
   si pesa poco, o enlázalo en el PR si no.
