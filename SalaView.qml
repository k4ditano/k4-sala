//  La sala, en una lista.
//
//  El orden de lectura es a propósito: primero cuántas cosas hay corriendo
//  —que es el titular—, luego los contenedores y después los servicios. Los
//  contenedores van antes porque son lo que uno viene a tocar; los servicios
//  de usuario casi siempre son fontanería del escritorio que está bien como
//  está.
//
//  El `plugin` se lo pasa el propio plugin —`view: Component { SalaView {
//  plugin: raiz } }`— porque el host no inyecta nada. Sin esa línea la vista
//  arranca con «Required property plugin was not initialized» y sale en blanco.

import QtQuick
import QtQuick.Layouts
import K4 as K4

K4.Aparicion {
    id: vista

    required property var plugin

    anchors.fill: parent

    //  El teclado escribe el filtro. Sin campo: se teclea y se filtra.
    //
    //  `grabKeyboard` del plugin lleva las teclas a la SUPERFICIE, pero no a
    //  este Item: `K4.Aparicion` es un Item pelado, no un FocusScope, así que
    //  `focus: true` por sí solo no da foco activo y `Keys.onPressed` no
    //  dispara nunca. Hay que pedirlo, y la capa tarda un poco en concederlo:
    //  de ahí el reintento, que es lo mismo que hace el lanzador.
    focus: true

    property int intentos: 0

    Component.onCompleted: {
        forceActiveFocus()
        reintento.start()
    }

    Timer {
        id: reintento
        interval: 140
        onTriggered: {
            if (!vista.plugin.abierto)
                return
            vista.forceActiveFocus()
            if (!vista.activeFocus && vista.intentos < 6) {
                vista.intentos += 1
                restart()
            }
        }
    }

    Keys.onPressed: function (ev) {
        if (ev.key === Qt.Key_Backspace) {
            vista.plugin.filtro = vista.plugin.filtro.slice(0, -1)
            ev.accepted = true
            return
        }
        //  ESC deshace primero lo de dentro y solo cierra cuando ya no hay
        //  nada que deshacer.
        if (ev.key === Qt.Key_Escape) {
            if (vista.plugin.armada.length > 0) {
                vista.plugin.desarmar()
                ev.accepted = true
                return
            }
            if (vista.plugin.filtro.length > 0) {
                vista.plugin.filtro = ""
                ev.accepted = true
                return
            }
            return
        }
        if (ev.text.length > 0 && ev.text.charCodeAt(0) >= 0x20) {
            vista.plugin.filtro += ev.text
            ev.accepted = true
        }
    }

    //  El botón de una acción de fila. Expone su propio `encima` porque el
    //  MouseArea de aquí tapa al de la Baldosa —está por encima en la pila— y
    //  con él se lleva el hover: sin este dato los botones desaparecerían
    //  justo en el momento de ir a pulsarlos.
    component Accion: Rectangle {
        id: boton

        property string glifo: ""
        property color tinte: K4.Tema.apagado
        readonly property alias encima: zona.containsMouse

        signal pulsado()

        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: zona.containsMouse ? K4.Tema.superficieAlta : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }

        scale: zona.pressed ? 0.9 : 1
        Behavior on scale {
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        K4.Glifo {
            anchors.centerIn: parent
            text: boton.glifo
            color: boton.tinte
            font.pixelSize: 15

            //  Render nativo a propósito. La Nerd Font trae ~13.500 glifos y
            //  el atlas de distance field de Qt Quick se equivoca con los
            //  códices de fuera del PMB —los `md-*` viven en U+F0000+—: el
            //  MISMO códice sale bien en una vista y dibuja OTRO icono en
            //  otra, según lo que se cacheara antes. Sin esta línea el aspa
            //  salía como un cursor de ratón.
            renderType: Text.NativeRendering
        }

        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: boton.pulsado()
        }
    }

    //  El aspa. Se cierra con ESC y tocando el fondo, pero eso hay que
    //  saberlo: el aspa se ve. Va por `Accion` y no por `K4.Boton` solo por lo
    //  del render nativo, que `K4.Boton` no deja tocar.
    Accion {
        z: 3
        glifo: String.fromCodePoint(0xF0156)   // md-close
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 10
        onPulsado: vista.plugin.close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        spacing: 12

        // ── el titular ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                K4.Etiqueta {
                    text: K4.Idioma.f("%1 running", vista.plugin.enMarcha)
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                K4.Etiqueta {
                    //  Lo que hay que saber en una línea, y lo primero es
                    //  cuando algo no se puede mirar: una lista corta porque
                    //  el demonio está parado se lee como «no tengo nada».
                    text: {
                        if (vista.plugin.caidos.length > 0)
                            return K4.Idioma.f("%1 is installed but not answering",
                                               vista.plugin.caidos.join(", "))
                        if (!vista.plugin.hayMotor)
                            return K4.Idioma.t("no docker or podman here · user services only")
                        return K4.Idioma.f("%1 in total", vista.plugin.cuantos)
                    }
                    color: vista.plugin.caidos.length > 0
                        ? K4.Tema.rojo : K4.Tema.apagado
                    font.pixelSize: 12
                }
            }

            K4.Etiqueta {
                visible: vista.plugin.filtro.length > 0
                text: "⌕ " + vista.plugin.filtro
                color: K4.Tema.tinta
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            K4.Etiqueta {
                visible: vista.plugin.mirando
                text: K4.Idioma.t("looking…")
                color: K4.Tema.apagado
                font.pixelSize: 11
            }

            //  El sitio del aspa, que está anclada y no ocupa en la fila.
            Item { implicitWidth: 18; implicitHeight: 1 }
        }

        // ── la lista ──────────────────────────────────────────────
        K4.Rodillo {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: vista.plugin.visibles

                    delegate: Loader {
                        required property var modelData
                        width: parent.width
                        sourceComponent: modelData.cabecera !== undefined
                            ? titulo : fila
                        property var dato: modelData
                    }
                }

                //  Ni una cosa: o no hay nada, o el filtro no casa. Son dos
                //  situaciones distintas y se dicen distintas.
                K4.Etiqueta {
                    visible: vista.plugin.visibles.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 40
                    text: vista.plugin.filtro.length > 0
                        ? K4.Idioma.f("Nothing matches “%1”", vista.plugin.filtro)
                        : K4.Idioma.t("Nothing is running")
                    color: K4.Tema.apagado
                    font.pixelSize: 12
                }
            }
        }

        // ── el pie ────────────────────────────────────────────────
        K4.Etiqueta {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: vista.plugin.nota.length > 0
                ? vista.plugin.nota
                : K4.Idioma.t("type to filter · system services need root, so they are not here")
            color: vista.plugin.nota.length > 0
                ? K4.Tema.verde : K4.Tema.tenue
            font.pixelSize: 11
        }
    }

    // ── las dos formas de fila ────────────────────────────────────

    Component {
        id: titulo

        Item {
            height: 26
            K4.Etiqueta {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: parent.parent.dato.cabecera
                color: K4.Tema.tenue
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }

    Component {
        id: fila

        K4.Baldosa {
            id: tarjeta

            readonly property var cosa: parent.dato
            readonly property bool armada: vista.plugin.estaArmada(cosa)
            readonly property bool viva: cosa.estado === "running"
            readonly property bool dormida: cosa.estado === "paused"

            //  Ni una cosa ni la otra: está cambiando ahora mismo. Salió
            //  probando contra podman de verdad — parar un contenedor lo deja
            //  unos segundos en `stopping`, y ahí mi fila ofrecía un ▶, que es
            //  mentira: no está parado, se está parando. systemd tiene lo
            //  mismo con `activating` y `deactivating`. Mientras dure, ningún
            //  botón: la fila dice lo que está pasando y ya cambiará sola en
            //  el siguiente repaso.
            readonly property bool enTransito:
                cosa.estado === "stopping" || cosa.estado === "removing"
                || cosa.estado === "activating" || cosa.estado === "deactivating"
                || cosa.estado === "start" || cosa.estado === "start-pre"
                || cosa.estado === "stop" || cosa.estado === "stop-sigterm"

            //  Los botones se ven si el ratón está en la fila O en uno de
            //  ellos: el hover no atraviesa. El hueco entre botones pertenece
            //  a la Baldosa, así que nunca hay un fotograma con todos falsos
            //  y no parpadean.
            readonly property bool tocada: roce.containsMouse || bArranca.encima
                || bPausa.encima || bReinicia.encima || bPara.encima

            height: 58

            colorBase: tarjeta.armada
                ? Qt.rgba(K4.Tema.rojo.r, K4.Tema.rojo.g, K4.Tema.rojo.b, 0.16)
                : K4.Tema.superficie

            //  La fila entera no se pulsa: aquí no hay una acción obvia que
            //  merezca el clic —parar es lo bastante gordo como para pedir su
            //  botón— así que `pulsable: false`, que además quita el cursor de
            //  mano y el aclarado al pasar, y así no promete nada.
            pulsable: false

            //  Pero el hover hay que recuperarlo aparte: `K4.Baldosa` ata su
            //  MouseArea a `pulsable` (`enabled: baldosa.pulsable`), así que
            //  apagarlo se lleva por delante `containsMouse` y los botones no
            //  aparecerían NUNCA. Con `Qt.NoButton` esta zona solo escucha el
            //  roce y no se queda ningún clic.
            MouseArea {
                id: roce
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 10
                spacing: 12

                //  El estado, de un vistazo y sin leer: verde en marcha,
                //  ámbar en pausa, rojo si ha fallado, gris si está parado.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: tarjeta.cosa.estado === "failed" ? K4.Tema.rojo
                        : tarjeta.viva ? K4.Tema.verde
                        : (tarjeta.dormida || tarjeta.enTransito)
                          ? K4.Tema.amarillo
                        : K4.Tema.tenue

                    //  Y late mientras cambia, que es la forma de decir «esto
                    //  no se ha quedado así» sin escribir una palabra más.
                    SequentialAnimation on opacity {
                        running: tarjeta.enTransito
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 480 }
                        NumberAnimation { to: 1;    duration: 480 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    K4.Etiqueta {
                        Layout.fillWidth: true
                        //  El nombre viene del sistema, así que va por
                        //  K4.Etiqueta —que ya fuerza texto plano— y recortado
                        //  por el final.
                        text: tarjeta.cosa.nombre
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    K4.Etiqueta {
                        Layout.fillWidth: true
                        text: tarjeta.armada
                            ? K4.Idioma.t("press again to stop it")
                            : tarjeta.cosa.sub
                        color: tarjeta.armada ? K4.Tema.rojo : K4.Tema.apagado
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    K4.Etiqueta {
                        Layout.fillWidth: true
                        visible: !tarjeta.armada && text.length > 0
                        text: tarjeta.cosa.detalle
                            + (tarjeta.cosa.puertos.length > 0
                               ? " · " + tarjeta.cosa.puertos : "")
                        color: K4.Tema.tenue
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    opacity: (tarjeta.tocada || tarjeta.armada)
                             && !tarjeta.enTransito ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }

                    //  Arrancar lo que está parado, y reanudar lo que está en
                    //  pausa: son el mismo gesto y el mismo icono.
                    Accion {
                        id: bArranca
                        visible: !tarjeta.viva && !tarjeta.armada
                        glifo: String.fromCodePoint(0xF040A)   // md-play
                        tinte: K4.Tema.verde
                        onPulsado: tarjeta.dormida
                            ? vista.plugin.reanudar(tarjeta.cosa)
                            : vista.plugin.arrancar(tarjeta.cosa)
                    }

                    //  Pausar es de contenedores: systemd no congela un
                    //  servicio, lo para, y ofrecer las dos cosas con el mismo
                    //  botón sería mentir sobre lo que va a pasar.
                    Accion {
                        id: bPausa
                        visible: tarjeta.viva && !tarjeta.armada
                                 && tarjeta.cosa.tipo === "contenedor"
                        glifo: String.fromCodePoint(0xF03E4)   // md-pause
                        onPulsado: vista.plugin.pausar(tarjeta.cosa)
                    }

                    Accion {
                        id: bReinicia
                        visible: tarjeta.viva && !tarjeta.armada
                        glifo: String.fromCodePoint(0xF0709)   // md-restart
                        onPulsado: vista.plugin.reiniciar(tarjeta.cosa)
                    }

                    //  Parar sí pregunta: pausar y reiniciar se deshacen
                    //  solos, esto corta el servicio y punto.
                    Accion {
                        id: bPara
                        visible: tarjeta.viva || tarjeta.dormida
                        glifo: String.fromCodePoint(0xF04DB)   // md-stop
                        tinte: tarjeta.armada ? K4.Tema.rojo : K4.Tema.apagado
                        onPulsado: tarjeta.armada
                            ? vista.plugin.parar(tarjeta.cosa)
                            : vista.plugin.armar(tarjeta.cosa)
                    }
                }
            }
        }
    }
}
