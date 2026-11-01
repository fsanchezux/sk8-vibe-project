# Audio

```
audio/
  ambient.mp3      Música ambiente (en bucle)
  sfx/             Efectos de sonido del skater (editables)
    pop.wav        Pop del tail al saltar
    catch.wav      "Clac" al atrapar la tabla tras un truco
    land.wav       Aterrizaje (también se usa al caerte, con tono más grave)
    roll.wav       Rodadura (bucle; volumen y tono suben con la velocidad)
    grind.wav      Grind sobre barandillas y ledges (bucle)
    skid.wav       Derrape de ruedas en un revert
    celebrate.wav  Campanitas del combo (el tono sube con el multiplicador)
    scrape.wav     Tail arrastrando al frenar (bucle)
```

## Cambiar un sonido

1. Edita o sustituye el archivo de `sfx/` conservando el **nombre**
   (por ejemplo `pop.wav`). Vale `.wav`, `.ogg` o `.mp3`.
2. Abre el proyecto en Godot (o ejecuta `godot --headless --path . --import`) para
   que lo reimporte.
3. Ejecuta el juego: ya suena el nuevo.

Recomendaciones:

- **Mono**, 16 bits y unos 22-44 kHz bastan. Mantenlos cortos (los de un solo
  disparo, menos de 0,5 s).
- `roll`, `grind` y `scrape` se reproducen **en bucle**: que empiecen y acaben
  sin cortes (cruzando el final con el principio).
- El juego cambia **volumen y tono** en tiempo real según la velocidad y la fuerza
  del truco (ver `scripts/skater_audio.gd`), así que no hace falta que el archivo
  lo tenga ya incorporado.
- Si borras un archivo de `sfx/`, el juego usa el sonido sintetizado por código
  como respaldo.

## Restaurar los originales

Los sonidos originales se generan por código. Para volver a crear los `.wav`:

```bash
godot --headless --path . -s tools/export_sfx.gd
```

(Sobrescribe los que haya en `sfx/`.)

## Herramientas gratuitas

[Audacity](https://www.audacityteam.org/) (editar y recortar),
[sfxr / jsfxr](https://sfxr.me/) (generar efectos 8 bits),
[Freesound](https://freesound.org/) (buscar sonidos; revisa su licencia y anótala
en `assets/CREDITS.md`).

## Música

Para cambiar la música, sustituye `ambient.mp3` (mismo nombre) o cambia
`MUSIC_PATH` en `scripts/game.gd`. Se reproduce en bucle.
