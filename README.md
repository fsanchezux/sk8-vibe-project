# sk8-vibe-project

Juego de skate para móvil hecho con **Godot 4.7** (renderer Mobile, Jolt Physics).
Sesiones de 2 minutos para hacer el máximo de puntos encadenando trucos, grinds y
manuals en un skatepark low-poly al atardecer.

> Estado: prototipo temprano (v0.1). ¡Se aceptan contribuciones! Mira el
> [ROADMAP](ROADMAP.md) y [CONTRIBUTING](CONTRIBUTING.md).

## Controles (táctil)

- **Mitad izquierda**: stick flotante de movimiento lateral. Doble toque = grab.
- **Mitad derecha**: flick hacia arriba o toque para empujar; flicks para trucos.
- En escritorio el ratón emula el toque.

## Requisitos

- [Godot 4.7](https://godotengine.org/download) (la versión indicada en `project.godot`).
- Para exportar a Android: plantillas de exportación, JDK y Android SDK
  ([guía oficial](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)).

## Ejecutar

```bash
git clone https://github.com/fsanchezux/sk8-vibe-project.git
cd sk8-vibe-project
godot --editor --path .      # abrir en el editor
godot --path .               # o ejecutar directamente
```

La primera vez Godot importará los assets (genera `.godot/`, que no se versiona).

## Estructura

```
scenes/    Escena principal
scripts/   Lógica del juego (GDScript)
shaders/   Shader "painted" low-poly
assets/    Assets editables: modelos, texturas, fuentes, audio (ver assets/README.md)
tools/     Scripts de editor para regenerar assets (personaje, efectos de sonido)
moodboard/ Referencias visuales y de ambiente (ver moodboard/README.md)
```

## Assets

Todo lo editable (modelos fuente `.obj`, textura, fuentes, música y efectos de
sonido) está en [`assets/`](assets/README.md), con instrucciones para modificarlo
y regenerar lo que se deriva de ello.

## Cómo editar los gráficos

Después de cualquier cambio, abre el proyecto en Godot para que reimporte los
archivos y prueba el juego.

| Quiero cambiar… | Dónde | Cómo |
|---|---|---|
| **El personaje** (ropa, pelo, calzado, cara) | `assets/character/src/*.obj` | Edita el modelo en Blender (exporta como OBJ) o elige otras prendas en `OUTFIT_PARTS` de `scripts/character_rig.gd`. Después ejecuta `godot --headless --path . -s tools/build_character.gd` para regenerar `skater_skater.res`. |
| **Los colores del personaje** | `assets/character/Textures_4.png` | Retoca la paleta en cualquier editor de imágenes, sin cambiar el tamaño ni la posición de los colores. Regenera el personaje como arriba. |
| **El aspecto del skatepark** (colores de hormigón, madera, hierba, árboles…) | constantes `C_*` en `scripts/skatepark.gd` y `scripts/scenery.gd` | Cambia los `Color(r, g, b)`. El skatepark y el entorno se generan por código con formas básicas. |
| **El estilo "pintado a mano"** | `shaders/painted.gdshader` | Parámetros `scale` (tamaño de las pinceladas) y `strength` (intensidad). La textura de pincel se crea en `scripts/skatepark.gd`. |
| **La interfaz** (colores y fuentes) | constantes de color en `scripts/game_ui.gd` y `assets/fonts/` | Cambia los colores o sustituye los `.ttf` conservando el nombre. |
| **El icono de la app** | `icon.svg` | Edítalo con Inkscape o similar. |
| **Geometría del skatepark** (rampas, rails, bancos) | `scripts/skatepark.gd` | Se define con primitivas (caja, quarter pipe, escalera…) en código; la misma definición da la física y el modelo. |

Los fuentes `.obj` están excluidos del import del juego (`.gdignore`), así que
solo se usan para regenerar el personaje y no pesan en el APK. Más detalles en
[assets/README.md](assets/README.md).

## Cómo editar los sonidos

Los efectos están en [`assets/audio/sfx/`](assets/audio/README.md) como `.wav`
(pop, catch, land, roll, grind, skid, celebrate, scrape) y la música en
`assets/audio/ambient.mp3`.

1. Edita el `.wav` (por ejemplo con [Audacity](https://www.audacityteam.org/)) o
   sustitúyelo por otro **con el mismo nombre**. También vale `.ogg` o `.mp3`.
2. Abre el proyecto en Godot para reimportarlo y ejecuta el juego.
3. Si lo borras, el juego usa el sonido sintetizado por código como respaldo.

`roll`, `grind` y `scrape` suenan en bucle. El volumen y el tono cambian en
tiempo real según la velocidad (`scripts/skater_audio.gd`). Para restaurar los
originales: `godot --headless --path . -s tools/export_sfx.gd`. Guía completa en
[assets/audio/README.md](assets/audio/README.md).

## Licencia

Código: [MIT](LICENSE). Assets: licencias propias, ver [assets/CREDITS.md](assets/CREDITS.md).
