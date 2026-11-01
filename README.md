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
tools/     Scripts de editor para regenerar assets (p. ej. el personaje)
```

## Assets

Todo lo editable (modelos fuente `.obj`, textura, fuentes, música) está en
[`assets/`](assets/README.md), con instrucciones para modificarlo y regenerar
lo que se deriva de ello.

## Licencia

Código: [MIT](LICENSE). Assets: licencias propias, ver [assets/CREDITS.md](assets/CREDITS.md).
