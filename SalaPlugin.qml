//  Sala de máquinas: qué está corriendo en esta máquina, y poder pararlo.
//
//  Hermano de `puertos`, y a propósito no el mismo: aquel contesta «¿qué
//  escucha?» y este «¿qué está levantado?». Se parecen en la forma —una lista
//  con acciones en cada fila— y no en la pregunta.
//
//  Junta dos mundos que uno mira por separado y con dos órdenes distintas:
//
//   · **Contenedores** de docker o de podman, los que estén, incluidos los
//     parados: querer arrancar uno que se cayó es la mitad del motivo de
//     abrir esto.
//   · **Servicios de usuario** de systemd, y solo los que están EN MARCHA o
//     han fallado. Listar los cientos que están parados sería ruido: de un
//     servicio parado uno no se acuerda, y si se acuerda usa el terminal.
//
//  ── lo que NO hace, y por qué ────────────────────────────────────
//
//  Los servicios del SISTEMA no se tocan. Pararlos necesita root, y pedirlo
//  desde la barra solo se puede de dos maneras: una elevación gráfica de
//  privilegios, o una regla de sudo que no pida contraseña. Las dos las
//  bloquea `tools/plugins.py` con la regla `sudo-sin-contrasena`, y con razón:
//  cualquier proceso que corra como tú podría invocar eso como root, y un
//  plugin no está en ninguna jaula. Los nombres concretos están en el README,
//  que no lo lee el validador — y que lo revise una persona es justo el punto.
//
//  Los contenedores sí, y sin root: podman rootless o tu usuario en el grupo
//  `docker`. No se escala nada, se usa lo que ya tienes.
//
//  ── y cuándo pregunta ────────────────────────────────────────────
//
//  Solo con la vista abierta, como `puertos`. `docker ps` tarda bastante más
//  que un `ss`, así que hacerlo todo el día para responder algo que se
//  pregunta dos veces por semana sería justo el gasto que una barra no debe
//  tener.

import QtQuick
import K4 as K4

K4.Plugin {
    id: raiz

    name: "sala"
    title: K4.Idioma.t("Engine room")

    //  Por encima de las vistas de reposo —reloj 50, reproductor 55— o el
    //  reloj se queda con el panel en cuanto acercas el ratón. Ver docs/PLUGINS.md.
    priority: 62

    islandWidth: 520
    islandHeight: 440

    // ── abrir y cerrar ────────────────────────────────────────────
    property bool abierto: false
    active: abierto

    function toggle() {
        abierto = !abierto
        if (abierto)
            mirar()
    }

    function close() { abierto = false }

    //  Se abre, se lee y se cierra. Y aquí además se escribe para filtrar, así
    //  que sin `grabKeyboard` las teclas solo llegarían pinchando la
    //  superficie — y a esto se llega por atajo o desde el centro de
    //  aplicaciones, donde nadie pincha.
    grabKeyboard: abierto

    //  Un toque en el fondo cierra. Sin declararlo, el host entiende que el
    //  toque no es suyo y abre el centro de control ENCIMA del panel.
    handlesBackgroundTap: true
    onBackgroundTapped: raiz.close()

    // ── lo que se sabe ────────────────────────────────────────────
    //
    //  El estado vive en el plugin: la vista se destruye al perder la island y
    //  con ella se irían la lista y el filtro.
    property var cosas: []
    property string filtro: ""
    property bool mirando: false
    property string nota: ""

    //  Motores que están instalados pero no contestan. No es lo mismo que no
    //  tener ninguno, y decirlo ahorra el rato de mirar una lista vacía
    //  preguntándose por qué: casi siempre es el demonio parado.
    property var caidos: []

    //  ¿Hay algún motor de contenedores instalado? Si no, la lista no está
    //  vacía por casualidad y hay que decirlo con esas palabras.
    property bool hayMotor: false

    readonly property int cuantos: cosas.length
    readonly property int enMarcha: {
        let n = 0
        for (let i = 0; i < cosas.length; ++i)
            if (cosas[i].estado === "running")
                n += 1
        return n
    }

    //  Lo que se pinta, ya filtrado y con sus cabeceras de sección. Se busca
    //  por nombre y por imagen, que son las dos formas de acordarse de un
    //  contenedor.
    readonly property var visibles: {
        const q = String(raiz.filtro).trim().toLowerCase()
        const pasa = raiz.cosas.filter(function (c) {
            if (q.length === 0)
                return true
            return c.nombre.toLowerCase().indexOf(q) >= 0
                || String(c.sub).toLowerCase().indexOf(q) >= 0
        })

        //  Las cabeceras se calculan DESPUÉS de filtrar: una sección que se
        //  ha quedado sin filas no debe dejar su título flotando solo.
        const fuera = []
        let ultimo = ""
        for (let i = 0; i < pasa.length; ++i) {
            if (pasa[i].tipo !== ultimo) {
                ultimo = pasa[i].tipo
                fuera.push({ cabecera: ultimo === "contenedor"
                    ? K4.Idioma.t("Containers")
                    : K4.Idioma.t("User services") })
            }
            fuera.push(pasa[i])
        }
        return fuera
    }

    // ── el sondeo ─────────────────────────────────────────────────
    //
    //  Todo en UN proceso. En varios serían varios `onSalida` y una máquina de
    //  estados para juntarlos; así llega en el mismo texto, separado por
    //  marcas, y de paso el guión se detecta solo qué hay instalado.
    //
    //  `--format` con separadores propios y no la tabla de siempre: la tabla
    //  alinea con espacios y un nombre con espacios dentro la rompe.
    K4.Process {
        id: sonda

        command: ["sh", "-c",
            "for m in docker podman; do "
          + "  command -v $m >/dev/null 2>&1 || continue; "
          + "  echo \"===MOTOR:$m===\"; "
          + "  if s=$($m ps -a --format "
          + "'{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}' "
          + "2>/dev/null); then printf '%s\\n' \"$s\"; "
          + "  else echo \"===CAIDO:$m===\"; fi; "
          + "done; "
          + "echo '===SERVICIOS==='; "
          + "systemctl --user list-units --type=service "
          + "--state=running,failed,activating --no-legend --no-pager --plain "
          + "2>/dev/null"]

        onArrancado: raiz.mirando = true
        onSalida: function (texto) { raiz._leer(String(texto)) }
        onTerminado: {
            raiz.mirando = false
            perro.stop()
        }
    }

    //  Un perro guardián, que lo pide la guía: una sonda colgada se apila.
    //  Aquí con más motivo que en `puertos`: `docker ps` con el demonio a
    //  medio arrancar se queda esperando de verdad.
    Timer {
        id: perro
        interval: 8000
        onTriggered: if (sonda.running) sonda.running = false
    }

    function mirar() {
        if (sonda.running)
            return
        sonda.running = true
        perro.restart()
    }

    //  Mientras la vista está delante, se refresca sola. Al cerrarla, nada.
    Timer {
        id: repaso
        interval: 4000
        repeat: true
        running: raiz.abierto
        onTriggered: raiz.mirar()
    }

    // ── leer lo que han contestado ────────────────────────────────

    function _leer(texto) {
        const lineas = texto.split("\n")
        const contenedores = []
        const servicios = []
        const rotos = []
        let motor = ""
        let hubo = false
        let seccion = "contenedores"

        for (let i = 0; i < lineas.length; ++i) {
            const l = lineas[i].replace(/\s+$/, "")
            if (l.length === 0)
                continue

            if (l.indexOf("===MOTOR:") === 0) {
                motor = l.substring(9, l.length - 3)
                hubo = true
                continue
            }
            if (l.indexOf("===CAIDO:") === 0) {
                rotos.push(l.substring(9, l.length - 3))
                continue
            }
            if (l === "===SERVICIOS===") {
                seccion = "servicios"
                continue
            }

            if (seccion === "contenedores")
                _leerContenedor(l, motor, contenedores)
            else
                _leerServicio(l, servicios)
        }

        raiz.hayMotor = hubo
        raiz.caidos = rotos
        raiz.cosas = contenedores.concat(servicios)
    }

    //  `abc123|web|nginx:alpine|running|Up 3 minutes|0.0.0.0:8080->80/tcp`
    //
    //  Podman devuelve los nombres como una LISTA —`[web]`— porque por dentro
    //  un contenedor puede tener varios alias; se le quitan los corchetes y se
    //  enseña el primero, que es el que la gente usa.
    //
    //  Y ese recorte se hace SOLO si venía entre corchetes. Partir por el
    //  espacio siempre sería más corto y estaría mal: un nombre con espacios
    //  se quedaría a medias sin avisar. Hoy ni docker ni podman los permiten,
    //  pero «hoy no pasa» no es lo mismo que «no puede pasar», y un nombre
    //  cortado en una lista de cosas que se pueden PARAR es de las
    //  equivocaciones caras.
    function _leerContenedor(linea, motor, fuera) {
        const c = linea.split("|")
        if (c.length < 4)
            return
        const bruto = String(c[1])
        const enLista = bruto.indexOf("[") === 0
        const nombre = enLista
            ? bruto.replace(/^\[|\]$/g, "").split(" ")[0]
            : bruto
        if (nombre.length === 0)
            return
        fuera.push({
            tipo: "contenedor",
            motor: motor,
            id: c[0],
            nombre: nombre,
            sub: c[2],                       //  la imagen
            estado: String(c[3]).toLowerCase(),
            detalle: c[4] || "",             //  «Up 3 minutes»
            puertos: c[5] || ""
        })
    }

    //  `pipewire.service loaded active running PipeWire Multimedia Service`
    //
    //  La descripción lleva espacios, así que se parte por los cuatro primeros
    //  campos y lo que queda es la descripción entera.
    function _leerServicio(linea, fuera) {
        const c = linea.trim().split(/\s+/)
        if (c.length < 4)
            return
        const activo = c[2]
        const sub = c[3]
        fuera.push({
            tipo: "servicio",
            motor: "systemd",
            id: c[0],
            nombre: String(c[0]).replace(/\.service$/, ""),
            sub: c.slice(4).join(" "),
            //  Se traduce al mismo vocabulario que los contenedores para que
            //  el color y los botones no tengan que saber de dónde viene cada
            //  fila. `failed` se queda como está: es lo que hay que ver.
            estado: activo === "failed" ? "failed"
                : (sub === "running" ? "running" : sub),
            detalle: activo,
            puertos: ""
        })
    }

    // ── las acciones ──────────────────────────────────────────────
    //
    //  Un proceso para las órdenes, otro distinto del de la sonda: si
    //  compartieran, parar algo a la vez que toca repaso se pisaría el
    //  `command` a medio arrancar.
    K4.Process { id: mando }

    property string nombreEnCurso: ""

    function _ordenar(c, verbo) {
        if (c.tipo === "contenedor")
            return [c.motor, verbo, c.id]
        //  systemd usa otras palabras para lo mismo.
        const s = verbo === "unpause" ? "start"
                : (verbo === "pause" ? "stop" : verbo)
        return ["systemctl", "--user", s, c.id]
    }

    function _hacer(c, verbo, dicho) {
        desarmar()
        mando.running = false
        mando.command = _ordenar(c, verbo)
        mando.running = true
        nombreEnCurso = c.nombre
        _decir(K4.Idioma.f(dicho, c.nombre))
        //  Un repaso poco después: la fila cambiando de color es la única
        //  señal de que aquello funcionó. `docker stop` se toma sus segundos,
        //  así que se mira dos veces.
        repescaCorta.restart()
        repescaLarga.restart()
    }

    function arrancar(c)  { _hacer(c, "start",   K4.Idioma.t("starting %1")) }
    function reiniciar(c) { _hacer(c, "restart", K4.Idioma.t("restarting %1")) }
    function pausar(c)    { _hacer(c, "pause",   K4.Idioma.t("pausing %1")) }
    function reanudar(c)  { _hacer(c, "unpause", K4.Idioma.t("resuming %1")) }
    function parar(c)     { _hacer(c, "stop",    K4.Idioma.t("stopping %1")) }

    Timer { id: repescaCorta; interval: 900;  onTriggered: raiz.mirar() }
    Timer { id: repescaLarga; interval: 4000; onTriggered: raiz.mirar() }

    //  Pausar, reanudar y reiniciar se deshacen solos; parar corta el servicio
    //  y punto, así que ese pregunta. No con un diálogo encima —taparía la
    //  lista— sino armando la fila: el primer toque la pone en rojo y pide
    //  confirmación, el segundo para. Y se desarma sola: un botón de parar
    //  armado esperando indefinidamente es una trampa.
    property string armada: ""

    Timer {
        id: desarme
        interval: 4000
        onTriggered: raiz.armada = ""
    }

    function armar(c) {
        armada = c.tipo + "/" + c.id
        desarme.restart()
    }

    function desarmar() {
        armada = ""
        desarme.stop()
    }

    function estaArmada(c) {
        return raiz.armada === c.tipo + "/" + c.id
    }

    // ── el aviso del pie ──────────────────────────────────────────
    property string _nota: ""

    Timer {
        id: avisoNota
        interval: 2400
        onTriggered: raiz.nota = ""
    }

    function _decir(t) {
        nota = t
        avisoNota.restart()
    }

    view: Component {
        SalaView { plugin: raiz }
    }

    // ── por dónde se llega ────────────────────────────────────────
    //
    //  Hijos sueltos y no propiedades con nombre: `services` es la propiedad
    //  por defecto de K4.Plugin y es donde el gestor busca los IpcHandler para
    //  darlos de baja al destruir el plugin.
    K4.Atajo {
        name: "sala"
        description: "Sala de máquinas: contenedores y servicios"
        onPressed: raiz.toggle()
    }

    //  En el lanzador aporto solo los nombres que el título NO lleva. El
    //  manifiesto ya mete «Engine room» en el buscador con `aplicacion: true`;
    //  aportar otra entrada genérica lo haría salir DOS VECES. Pero quien
    //  busca esto teclea «docker», y por ahí no llegaría nunca.
    K4.Lanzador {
        plugin: "sala"
        onBuscando: function (texto) {
            const q = String(texto).trim().toLowerCase()
            if (q.length < 3) {
                resultados = []
                return
            }
            const alias = ["docker", "podman", "contenedores", "containers",
                           "servicios", "services", "systemd"]
            let casa = false
            for (let i = 0; i < alias.length; ++i)
                if (alias[i].indexOf(q) === 0)
                    casa = true
            resultados = casa ? [{
                id: "abrir",
                titulo: K4.Idioma.t("Engine room"),
                desc: K4.Idioma.t("Containers and user services, with the buttons")
            }] : []
        }
        onElegido: function (id) {
            raiz.abierto = true
            raiz.mirar()
        }
    }

    K4.Ipc {
        target: "k4.sala"

        function abrir(): void { raiz.abierto = true; raiz.mirar() }
        function cerrar(): void { raiz.close() }
        function alternar(): void { raiz.toggle() }

        //  Devuelve, no imprime: así `quickshell ipc call` lo escribe en tu
        //  terminal en vez de dejarlo en el log de la barra.
        function lista(): string {
            return JSON.stringify(raiz.cosas)
        }
    }
}
