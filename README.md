<img width="1871" height="1023" alt="portada" src="https://github.com/user-attachments/assets/b8110296-bd67-4562-8e2e-1c0ea68bcac0" />

# sk8-vibe-project

Juego de skate para móvil hecho con **Godot 4.7** (renderer Mobile, Jolt Physics).
Sesiones de 2 minutos para hacer el máximo de puntos encadenando trucos, grinds y
manuals en un skatepark low-poly al atardecer.

> Estado: prototipo temprano (v0.1). ¡Se aceptan contribuciones! Mira el
> [ROADMAP](ROADMAP.md) y [CONTRIBUTING](CONTRIBUTING.md).

## ⚠️ Lee el moodboard antes de contribuir

**Es imprescindible leer el moodboard antes de hacer cualquier contribución**
(código, gráficos o sonidos). Define la dirección artística del juego y los PR que
no la respeten no se aceptarán.

- 📌 Tablero de Pinterest: https://pin.it/3eSmdPFaN
- 🎨 Archivo del moodboard (Photoshop) en el repo: [moodboard/Moodboard%20sk8.psb](moodboard/Moodboard%20sk8.psb)
- 📁 Carpeta y normas: [moodboard/](moodboard/README.md)

## Controles (táctil)

- **Mitad izquierda**: stick flotante de movimiento lateral. Doble toque = grab.
  Stick hacia abajo = derrape: la tabla se cruza perpendicular a la marcha y frena; al
  soltar vuelve a ponerse recta y sigues.
- **Mitad derecha**: flick hacia arriba o toque para empujar; flicks para trucos.
  Cuanto más largo es el recorrido del flick (de abajo del todo a arriba del todo),
  más alto es el salto. El trazo del dedo se queda dibujado hasta que cae el truco.
- **fijar / volver** (arriba a la derecha): marca un punto de reset donde estás y
  vuelve a él cuando quieras repetir un spot o si te quedas atascado. Un aro amarillo
  marca el spot; volver cuesta el combo en curso y no funciona en el aire ni en un grind.
- Más altura de pop = más puntos (de ×0,8 a ×1,3 en cada truco). Con un combo largo la
  cámara lenta de los trucos se nota más; a partir de x3 cada truco suena a campanitas.
- En escritorio el ratón emula el toque. Teclado: flechas = stick derecho,
  Espacio = ollie, W = empujar, K = grab, F = fijar spot, R = volver al spot.
  Mayús mantenido = pop suave (el teclado no mide recorrido).
- Mando: stick derecho = trucos (misma intensidad por recorrido que en táctil),
  stick izquierdo abajo o X = frenar,
  Back/Select = fijar spot, Y = volver al spot.

## El recorrido

Empiezas arriba de una carretera de bajada con curvas (serpentina, 3,5 % de pendiente)
que llega al roll-in del deck oeste del park. A los lados hay césped, un poco más bajo
que el asfalto: puedes salirte, pero vas a la mitad de velocidad. Atajos:

- **Atajos 1 y 2:** al principio de la primera y la segunda curva, un kicker por dentro
  de la curva (al entrar ya vas girando hacia él), hueco de césped y rampa de recepción
  donde sale la curva. Te ahorras la curva. Todas las rampas de la carretera tienen
  un poco de lanzadera (los kickers, más).
- **Atajo 3, el puente:** rampa de subida, puente por encima del tramo siguiente (si vas
  por la carretera pasas por debajo) y una rampa larga que baja directa al roll-in.

Del roll-in bajas hacia el este por uno de tres carriles (el park baja 2,4 m en total). Los carriles 1 y 3 empiezan 3 m más tarde que
la escalera, para que dé tiempo a colocarse:

1. **Norte, gap:** lanzadera larga al borde del deck, 6 m de césped y rampa de recepción,
   que también es lanzadera para hacer el gap a la inversa.
2. **Centro, escaleras:** un set de 15 escalones con hubba a cada lado (1,2 m sobre los
   escalones y 1 m de ancho) y barandilla en medio (1,1 m), altas para poder grindarlas al saltar del deck.
3. **Sur, basura:** bank de bajada y un ledge sobre arco ancho (1,6 m) que hace de lanzadera (súbelo
   rodando o grindando) para saltar un contenedor de basura con un cono encima, algo
   lejos: hace falta un buen ollie. Tocar el cono es caer.

Los tres carriles acaban en una lanzadera enorme (4 m) que te saca del mapa por una
abertura del murete; en el centro, antes, hay dos olas (la primera de 1,4 m y la
segunda de 2,1 m). Subir las lanzaderas no frena: te empujan y te lanzan fuera aunque
llegues despacio. Al salir del mapa vuelves arriba de la carretera con la misma
velocidad: apareces en el aire y caes sobre la salida, como si vinieras de la rampa.

En las olas y las rampas el skater hace pump solo: se agacha al bajar,
se estira al subir y gana velocidad (`PUMP_ACCEL` en `scripts/skater.gd`). Y en el aire,
al caer sobre una rampa u ola, se va inclinando hacia ella antes de tocarla (transfer)
para entrar suave (`TRANSFER_TIME`).

Todas las rampas rectas tienen un poco de curva de lanzadera al final (más empinadas
arriba); la de recepción del gap, más marcada (`BANK_KICK` y `GAP_KICK`).

## Módulos del mapa

Piezas sueltas que se colocan a mano en el editor de Godot (`scripts/modules/`):

| Módulo | Qué es | Grind |
|---|---|---|
| `ParkWave` | Ola de hormigón de varias crestas (VAG-3) | no |
| `ParkWedge` | Cuña curva de hormigón con canto vivo | canto trasero |
| `ParkArchLedge` | Ledge inclinado sobre un arco | cara superior |
| `DownhillRoad` | La carretera de salida (la coloca el park, no se mueve a mano) | no |

Para usarlos: abre `scenes/main.tscn`, selecciona el nodo `Modules` y añade un nodo
`Node3D` con el script del módulo (o duplica uno de los de ejemplo). Muévelo en X/Z y
rótalo solo en Y y deja la escala en 1. Y es la altura de la base: 0 en el fondo del
park, o la del deck (2,4) si la pieza va encima. Las medidas (largo, ancho, altura,
color...) se cambian en el Inspector, y la malla se actualiza en el editor.

Cada módulo dibuja su malla y registra su física en el skatepark al arrancar
(`register()`), así que lo que se ve es lo que se pisa. Para crear uno nuevo, hereda de
`ParkModule` e implementa `_build()` y `register()`. Los módulos son nuevos y están
sin probar en el editor: si algo sale raro de forma o de escala, abre un issue.

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
