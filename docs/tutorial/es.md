# Legacy Downloader — Tutorial

Legacy Downloader instala **Legacy Offline PC** y sus paquetes de canciones
en tu ordenador, y los mantiene actualizados. No necesitas ningún
conocimiento técnico para usarlo — solo sigue las imágenes de abajo, en
orden.

Otros idiomas: [English](en.md) · [Français](fr.md) · [Filipino](fil.md) ·
[Deutsch](de.md) ·
[Italiano](it.md) · [Português](pt.md) · [Nederlands](nl.md) · [日本語](ja.md) ·
[한국어](ko.md) · [简体中文](zh-Hans.md) · [繁體中文](zh-Hant.md) · [Русский](ru.md)

---

## Inicio rápido

Para quien solo quiera la versión corta:

1. Descarga el zip desde la [página de Releases](https://github.com/VenB304/LegacyDownloader/releases) y
   extráelo.
2. Haz doble clic en `LegacyDownloader-GUI.bat`.
3. Sigue los pasos de la pantalla de bienvenida, elige tus canciones y haz
   clic en **«Descargar / Buscar actualizaciones»**.
4. Cuando aparezca el mensaje **«Estás al día»**, abre `Legacy.exe` en tu
   carpeta del juego para jugar.

Si algo te resulta confuso o no coincide con lo descrito, la guía detallada
de abajo tiene una imagen para cada pantalla.

---

## 1. Descargar y extraer

1. Consigue el último `LegacyDownloaderVX.zip` desde la [página de Releases](https://github.com/VenB304/LegacyDownloader/releases).
2. Extráelo — clic derecho en el zip → **Extraer todo...** → elige una
   carpeta normal (el Escritorio sirve). No lo ejecutes desde dentro de la
   ventana del zip.
3. Abre la carpeta extraída y haz doble clic en **`LegacyDownloader-GUI.bat`**.

![Contenido de la carpeta extraída](images/01-extracted-folder.png)

> Si tu antivirus marca `rclone.exe` (un archivo dentro de la carpeta `bin`),
> consulta la sección de [Solución de problemas](#solución-de-problemas) más
> abajo — es un falso positivo conocido, no un problema real con la
> descarga.

## 2. Primer inicio — pantalla de bienvenida

A continuación aparece una ventana de **«Bienvenido»**.

![Ventana de bienvenida con selector de idioma (banderas)](images/03-welcome-es.png)

- **¿Sale el idioma equivocado?** Haz clic en el menú desplegable de la
  bandera en la esquina y elige el tuyo — el programa cambia al instante.
- Luego responde a la única pregunta que hace:
  - **«Ya lo tengo»** — elige esto si Legacy Offline PC ya está en algún
    sitio de este PC.
  - **«Descárgamelo»** — elige esto si aún no tienes el juego. Todo lo que
    sigue es automático.

### Si ya tienes el juego
Se abre una ventana para elegir carpeta. Busca y haz clic en la carpeta
que tenga **`Legacy.exe`** directamente dentro (no en una subcarpeta),
luego haz clic en **Seleccionar carpeta**.

### Si aún no tienes el juego
Se abre una ventana para elegir dónde va a vivir el juego — una carpeta
vacía, o una nueva que crees ahí mismo (hay un botón «Nueva carpeta» en esa
ventana). Haz clic en **Seleccionar carpeta**, y el juego empieza a
descargarse de inmediato — sin ningún botón adicional que pulsar.

Esta primera descarga es grande — unos **1,2 GB**, normalmente entre 5 y 20
minutos según tu conexión. **Deja la ventana abierta** hasta que termine;
verás el progreso avanzando en la ventana.

> Las canciones **no** forman parte de esta primera descarga — es solo el
> juego base, así que no te preocupes si todavía no aparece ninguna
> canción.

## 3. Comprobar los requisitos de software

Legacy necesita algunos programas adicionales que Windows no trae de
serie — Kinect SDKs y tiempos de ejecución de Visual C++. Legacy
Downloader los comprueba automáticamente, una sola vez:

- **Si ya tenías el juego**, esta comprobación ocurre de inmediato, antes
  de que aparezca la ventana principal.
- **Si elegiste «Descárgamelo»**, ocurre automáticamente en cuanto termina
  la descarga de arriba.

![Diálogo de requisitos de software](images/07-requirements-es.png)

Lo que aparece en rojo falta — haz clic en **Instalar** junto a ese
elemento para descargarlo e instalarlo, o haz clic en el nombre con
enlace para abrir la página oficial de descarga de Microsoft en su lugar.
Cuando todo esté en verde, haz clic en **Cerrar** para continuar. Puedes
volver a abrir esta comprobación cuando quieras desde el botón
**Requisitos** de la ventana principal.

## 4. La ventana principal

Una vez que el juego base está en su sitio, llegas aquí:

![Ventana principal de Legacy Downloader](images/04-main-window-es.png)

- **Carpeta del juego** — dónde vive tu juego. **Cambiar...** te permite
  apuntarlo a otro sitio si alguna vez mueves el juego.
- **Canciones** — elige:
  - **Todo** — todas las ediciones de Just Dance disponibles, y recogerá
    las nuevas automáticamente a medida que se publiquen. Esta es la
    opción más sencilla si no estás seguro — elige esta.
  - **Solo ediciones concretas** — elige exactamente lo que quieres en su
    lugar. Haz clic en **«Elegir mapas / canciones»** para abrir el
    selector — lo vemos en el siguiente paso.
  - **Ver seguidos** — abre una lista de tus canciones con códigos de color: verde = «Descargada», amarillo = «Siguiendo, aún no descargada», rojo = «Descargada, no seguida». Útil para ver qué descargaría una comprobación o para detectar restos.
- **«Descargar / Buscar actualizaciones»** — el botón grande. Haz clic para
  obtener lo que elegiste, y vuelve a hacer clic más adelante para buscar
  canciones nuevas o actualizaciones.
- **Requisitos** — vuelve a abrir la comprobación del paso anterior, cuando
  quieras volver a comprobar o instalar algo que te hubieras saltado.
- **Configuración** — comprobación automática, inicio automático, un límite de velocidad de descarga y más; ver el paso 8.

## 5. Elegir canciones individuales

Haz clic en **«Elegir mapas / canciones»** (desde la ventana principal, en
cualquier momento) para abrir el selector:

![Selector de canciones y ediciones](images/06-songbrowser-es.png)

- **Ediciones**, a la izquierda — marca la casilla de una edición completa
  para llevártelo todo. Una casilla que se ve medio rellena significa que
  solo algunas canciones de esa edición están marcadas.
- **Canciones**, a la derecha — cada canción individual, con su edición,
  dificultad y esfuerzo (intensidad del ejercicio) cuando se conocen. Marca
  o desmarca cualquier canción por su cuenta — no hace falta llevarte una
  edición entera de golpe.
- **Buscar** — escribe un título, artista o nombre en código para filtrar
  la lista al instante.
- **Filtros** — reduce más la lista por Dificultad o Esfuerzo con los menús
  desplegables de la esquina superior derecha.
- **Marcar todas las mostradas / Desmarcar todas las mostradas** — marca en
  bloque lo que muestre tu búsqueda o filtro actual, en vez de hacer clic
  canción por canción.
- **Columnas...** — muestra u oculta las columnas Artista, Dificultad o
  Esfuerzo si prefieres una vista más simple.
- **Conservar mi versión** — ¿has modificado una canción tú mismo (por ejemplo, con un vídeo de mayor calidad)? Haz clic en la fila de la canción en la lista (no en su casilla) y luego en este botón. Las actualizaciones nunca sobrescribirán tu copia: la canción sigue en seguimiento y aparece con ✓ en la columna **Mía**. Vuelve a hacer clic para soltarla. Solo se pueden conservar canciones ya descargadas.

Haz clic en **OK** para guardar tu selección, o en **Cancelar** para salir
sin cambiar nada.

> Las canciones que la lista comunitaria todavía no tiene nombradas
> igualmente aparecen (solo con su nombre de archivo en vez de un título) —
> se descargarán y funcionarán bien, solo que sin un nombre amigable hasta
> que alguien lo añada.

## 6. Comprobación de actualizaciones

Hacer clic en el botón grande no descarga nada de inmediato — primero
**comprueba** qué te falta o ha cambiado. Mientras comprueba, la barra de
progreso puede simplemente moverse de un lado a otro sin mostrar
porcentaje — es normal, significa que todavía está comparando tus archivos
con el servidor, no que esté bloqueada.

![Ventana de comprobación de actualizaciones](images/05-preview-es.png)

Cuando termina de comprobar, una ventana muestra lo que encontró, con un
tamaño total. Haz clic en **«Descargar ahora»** para obtener los archivos,
o en **«Cancelar»** si solo querías ver qué hay disponible. Si no ha
cambiado nada desde la última vez, simplemente dice **«Todo está ya
actualizado»** y se detiene ahí — no hay nada que pulsar.

**Canciones que se reemplazarían.** Si la copia de una canción en el servidor difiere de la que ya tienes en el disco (mismo nombre de archivo, distinto tamaño) —una actualización oficial o tu propia copia modificada de una canción oficial—, la vista previa lo indica y muestra esas canciones con casillas. **Marcada** (por defecto) = se reemplaza; el archivo antiguo se mueve antes a una carpeta de copias de seguridad (`.legacydownloader-backups` dentro de tu carpeta del juego). **Desmarcada** = conservas tu versión; la canción se marca como **Conservar mi versión** y las actualizaciones nunca la reemplazarán.

<details>
<summary>Si has modificado tus archivos del juego (mod de Kinect, exe parcheado) — haz clic para desplegar</summary>

Si un archivo que has modificado tú mismo (`Legacy.exe` o una DLL de
Kinect) difiere de la versión del servidor, recibe su propia casilla en
vez de incluirse automáticamente:
- **Marcada** = reemplazarlo con la copia del servidor (elige esto si no
  has modificado nada — es solo una actualización normal del juego).
- **Sin marcar** = conservar tu propia copia tal cual.

Tus ajustes dentro del juego (resolución, pantalla completa/ventana) nunca
se tocan con una actualización, esté modificado o no.
</details>

## 7. Durante la descarga

La barra de progreso y el registro de abajo se actualizan en vivo — verás
el juego y cada paquete de canciones listados a medida que terminan, uno
por uno. **No cierres la ventana mientras esto se está ejecutando.** Cuando
todo termine, verás un aviso de **«Listo para jugar»** con un botón
**«Iniciar juego»** — haz clic en él para abrir `Legacy.exe` y cerrar
Legacy Downloader en un solo paso. (Activa **«Iniciar el juego
automáticamente y cerrar, en cuanto ya no haga falta nada más»** en
Configuración si prefieres saltarte este aviso e ir directamente a jugar
cada vez).

![Aviso «Listo para jugar»](images/09-quicklaunch-es.png)

## 8. Volver más tarde por canciones nuevas

Simplemente ejecuta `LegacyDownloader-GUI.bat` de nuevo cuando quieras. Recuerda
tu carpeta y tus canciones elegidas, y hacer clic en **«Descargar / Buscar
actualizaciones»** obtiene todo lo nuevo desde tu última visita.

- **Añadir o quitar canciones**: haz clic otra vez en **Elegir mapas / canciones**, marca o desmarca lo que quieras y pulsa Aceptar. Si desmarcas canciones que ya descargaste —una edición entera o solo unas pocas— se te pregunta una sola vez: **Borrar los archivos** elimina esos archivos, **Conservar los archivos y no actualizar** los deja en el disco pero deja de actualizarlos, y **Cancelar** deja tu selección sin cambios. Las canciones que marcaste con «Conservar mi versión» nunca se borran aquí. Tus propias canciones personalizadas (archivos que no están en el servidor de canciones) nunca se borran aquí. Una copia modificada de una canción oficial solo está protegida si la marcaste con «Conservar mi versión». Todo lo que se borra queda registrado en `bin\logs\deleted-files.txt`.
- **Cambiar de idioma**: el menú desplegable de la bandera, arriba a la
  derecha, en cualquier momento.
- **Ajustar la configuración**: haz clic en **Configuración** en la ventana
  principal para el chequeo automático, el inicio automático, un límite de
  velocidad de descarga, buscar actualizaciones de LegacyDownloader
  automáticamente y una URL de share personalizada avanzada.

  ![Ventana de ajustes](images/08-settings-es.png)
- **Copias de seguridad de canciones**: en **Configuración**, **Copias de seguridad de canciones** controla si los archivos de canciones reemplazados se respaldan antes (activado por defecto), cuántos días se conservan las copias (30) y el espacio máximo que pueden ocupar (5 GB); las copias más antiguas se eliminan automáticamente. **Abrir carpeta de copias de seguridad** las muestra: para recuperar una canción, cópiala a la carpeta correspondiente dentro de `maps`.
- **Actualizar el propio Legacy Downloader**: cuando hay una nueva versión
  disponible, aparece un botón junto a **Configuración** en la ventana
  principal. Haz clic en él y la herramienta se actualiza en el mismo sitio y
  se reabre automáticamente — sin necesidad de volver a descargar nada
  manualmente.

  ![Diálogo de actualización disponible](images/10-update-es.png)

---

## Versión de texto/consola (avanzado — la mayoría no la necesita)

También existe una versión de menú de texto, para solución de problemas o
si la prefieres: haz doble clic en **`LegacyDownloader-Console.bat`** en su
lugar. Mismas funciones, navegando con teclas numéricas:

```
[1] Descargar / buscar canciones nuevas
[2] Elegir qué canciones descargar
[3] Cambiar la carpeta del juego
[4] Idioma
[5] Configuración
[6] Comprobar requisitos de software
[7] Salir
```

> **Nota sobre la fuente:** la versión gráfica muestra todos los idiomas
> correctamente. Esta versión de texto necesita una fuente con los
> caracteres adecuados — el japonés, coreano, chino y ruso pueden aparecer
> como cuadrados (□) aquí. Si quieres alguno de esos idiomas, quédate con
> la versión gráfica.

---

## Solución de problemas

- **El antivirus pone en cuarentena o borra `rclone.exe`** — un falso
  positivo conocido. Algunos antivirus marcan `rclone` como una
  «herramienta de hackeo» porque los atacantes también pueden usarla, pero
  es una herramienta de código abierto legítima y muy usada, y es lo único
  que usa este programa para obtener archivos. Restáuralo desde la
  cuarentena/historial de tu antivirus, permítelo, y vuelve a ejecutar
  `LegacyDownloader-GUI.bat`.
- **Aparece un aviso de seguridad al hacer doble clic en
  `LegacyDownloader-GUI.bat`** — esto puede pasar la primera vez que ejecutas
  cualquier script descargado. Haz clic para continuar («Más información →
  Ejecutar de todas formas», o algo similar) — es normal para una
  herramienta pequeña e independiente, no una señal de que algo va mal.
- **Mensaje «falta rclone.exe»** — vuelve a descargar el zip y extráelo de
  nuevo; no ejecutes la herramienta desde dentro del visor del zip.
- **No pasa nada al hacer clic en un botón de carpeta** — la ventana de
  selección puede haberse abierto *detrás* de la ventana principal;
  revisa tu barra de tareas.
- **Dice «al día» pero me faltan canciones** — abre **«Elegir mapas /
  canciones»** y comprueba que realmente has marcado las que quieres (o
  elige **«Todo»**).
- **Una actualización sustituyó una canción que modifiqué** — antes de actualizar, abre **Elegir mapas / canciones**, haz clic en la fila de la canción y pulsa **Conservar mi versión** (ver paso 5). Las canciones conservadas nunca se sobrescriben. Si ya ocurrió, el archivo antiguo está en la carpeta de copias de seguridad: **Configuración** → **Abrir carpeta de copias de seguridad**, y cópialo de vuelta a la carpeta correspondiente dentro de `maps`.
- **¿Sigues atascado?** Publica en el hilo de Legacy Downloader en Discord
  con una captura de lo que ves y en qué paso estás — alguien te ayudará.
