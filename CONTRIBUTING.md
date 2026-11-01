# Cómo contribuir

¡Gracias por querer ayudar!

> ⚠️ **Antes de hacer cualquier contribución es imprescindible leer el
> [moodboard](moodboard/README.md)**: [Pinterest](https://pin.it/3eSmdPFaN) y el
> archivo [Moodboard sk8.psb](moodboard/Moodboard%20sk8.psb). Los PR que no respeten la
> dirección artística no se aceptarán.

Flujo básico:

1. Busca en los [issues](../../issues) algo con la etiqueta `good first issue` o
   `help wanted`, o abre uno nuevo para proponer tu idea **antes** de hacer
   cambios grandes.
2. Haz un fork y crea una rama: `git checkout -b feat/mi-cambio`.
3. Haz cambios pequeños y enfocados (un PR = una cosa).
4. Prueba el juego (en escritorio y, si tocas controles, en un móvil real).
5. Abre un Pull Request explicando qué cambia y por qué; añade capturas o vídeo
   si afecta a lo visual o a la sensación de control.

## Estilo de código

- GDScript con tipos estáticos siempre que se pueda.
- Respeta `.editorconfig` (UTF-8, LF).
- Constantes en `MAYUSCULAS`, nombres en `snake_case`, clases en `PascalCase`.
- Comentarios `##` para documentar clases y constantes; en español, como el resto.

## Assets

- Edita los fuentes en `assets/` (ver [assets/README.md](assets/README.md)).
- **Solo sube assets con licencia compatible** y añade su entrada a
  `assets/CREDITS.md` (autor, fuente, licencia). Sin crédito, no se acepta el PR.
- Evita subir ficheros grandes (>5 MB) sin hablarlo antes.

## Qué NO subir

APKs, `.godot/`, claves de firma (`*.keystore`). Los builds se publican en Releases.

## Conducta

Sé amable y respetuoso. Seguimos el [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
