# Chalona WhatsApp — API y cliente FoxPro

Manda WhatsApp **desde el número de tu empresa**, desde tu sistema: un texto, o un
archivo (el PDF de una factura, una foto, un Excel) con el texto como pie. Después
consultas si salió y lees lo que te contestaron.

El número de la empresa se vincula una sola vez en el **agente**, un programa que
corre en una PC de tu oficina (como WhatsApp Web). Los mensajes salen de ahí. Tu
sistema no habla con el agente: habla con el API, que pone cada mensaje en la cola
de ese número.

Una empresa puede tener **varios números** (en una misma PC o en varias), cada uno
con su cola, sus topes y sus respuestas. Cada envío dice por cuál número sale
(`desde`, el número de origen). Si la empresa tiene un solo número no hace falta
decirlo; si tiene varios y no se dice, el envío se rechaza con
`whatsapp.desde_requerido` y la lista de los números: nunca se adivina.

| | |
|---|---|
| Servidor | `https://whatsapp.chalonasoft.com/api/` |
| Autenticación | `Authorization: Bearer cst_…` (token de cuenta de servicio) |
| Cliente FoxPro | [`chalona-whatsapp.prg`](chalona-whatsapp.prg) (VFP 9, un solo archivo, sin dependencias) |
| Ejemplo | [`ejemplo-whatsapp.prg`](ejemplo-whatsapp.prg) |

## Antes de empezar

1. **El agente instalado y el número vinculado.** Lo ves en la página
   `https://whatsapp.chalonasoft.com` (Números: «Listo»), o con `Numeros()` desde
   Fox.
2. **Un token de cuenta de servicio** (`cst_…`) de tu empresa, con el perfil
   «Envíos» de WhatsApp. Te lo da tu proveedor. Es una credencial: va en la
   configuración del sistema, nunca en el código ni en un correo.

## FoxPro

```foxpro
Set Procedure To chalona-whatsapp.prg Additive

loWa = Createobject("ChalonaWhatsapp", lcToken)

* Un texto
loR = loWa.EnviarTexto("8095551234", "Buenos días, Juan. Su balance es RD$ 12,500.00.", "EC-2026-10-C0045")

* Un PDF, con el texto de pie
loR = loWa.EnviarArchivo("8095551234", "C:\facturas\FT-000123.pdf", "Su factura FT-000123", "FT-000123")

* Con varios números: por cuál sale (el último parámetro)...
loR = loWa.EnviarTexto("8095551234", "Su balance es RD$ 12,500.00.", "EC-2026-10-C0045", "18295550000")
loR = loWa.EnviarArchivo("8095551234", "C:\facturas\FT-000123.pdf", "Su factura", "FT-000123", "", "18295550000")
* ...o para todos los envíos de este objeto:
loWa.Desde = "18295550000"

If !loR.ok
  Messagebox(loR.mensaje, 16, "WhatsApp")    && el error ya viene en español
Else
  * Guarda loR.id en tu documento para consultar el estado después.
Endif
```

El número va solo con dígitos. Uno dominicano de 10 dígitos (809, 829, 849) puede ir
sin el 1; de otro país, con su código (`34612345678`). Guiones, espacios y paréntesis
se quitan solos.

### Métodos

| Método | Qué hace |
|---|---|
| `EnviarTexto(numero, texto, [control], [desde])` | Pone un texto en la cola. `desde`: el número de la empresa por el que sale (obligatorio si tiene varios). |
| `EnviarArchivo(numero, ruta, [texto], [control], [nombre], [desde])` | Pone un archivo en la cola, con `texto` de pie. Fotos (jpg, png, webp) salen como imagen; lo demás como documento con su nombre. `nombre` cambia el que ve el cliente. Hasta 10 MB desde Fox. |
| `Estado(id)` / `EstadoPorControl(control)` | Cómo va un envío (`.estado`, `.desde` = por cuál número salió, `.registro`). |
| `Mensajes([numero], [estado], [desde], [hasta], [limite], [saltar], [por_numero])` | Lo enviado, del más nuevo al más viejo (`.lista`, `.total`); cada uno con `.desde`. Fechas ISO: `"2026-10-01"`. `por_numero`: solo lo que salió por ese número de la empresa. |
| `Cancelar(id)` | Cancela un envío que todavía está `pendiente`. |
| `Respuestas([despues_de], [numero], [limite], [para])` | Lo que te contestaron (`.lista`, `.ultimo_id`); cada una con `.para` = a cuál número de la empresa llegó. |
| `RespuestasACursor(cursor, [despues_de], [numero], [limite], [para])` | Igual, en un cursor `(id, de, nombre, texto, tipo, hora, agente, para, linea)`. |
| `Numeros()` | Los números de la empresa y cómo están (`.lista`: `numero`, `nombre`, `vinculado`, `conectado`, lo de hoy). |
| `Agentes()` | Las PC (agentes) de la empresa, cada una con sus números. |

Propiedades: `Token`, `BaseUrl`, `Desde` (el número de origen para todos los envíos
del objeto, si no se pasa en cada uno; vacío = el único de la empresa), `Agente`
(de la versión 1.0: vale si ese agente tiene un solo número), `ComponenteHttp` (por defecto
`MSXML2.XMLHTTP`, el mismo del cliente ECF), `UltimaPeticion` (el JSON de la
última llamada, sin el base64, para tu log).

### La respuesta

Todo método devuelve un objeto con:

| | |
|---|---|
| `ok` | `.T.` / `.F.` |
| `mensaje` | El error, en español, para mostrarlo tal cual. |
| `codigo` | El código del error (`whatsapp.tope_dia`…), para decidir en tu código. |
| `id`, `estado`, `registro` | El mensaje (en los envíos, `Estado`, `Cancelar`). |
| `repetido` | `.T.` si ese `control` ya existía: no se mandó otra vez. |
| `lista`, `total`, `ultimo_id` | En las consultas. |
| `data`, `crudo`, `http_status` | Lo que devolvió el servidor, como objeto y como texto. |

### El control: nunca dos veces

Pasa siempre un `control`: la llave de ese envío en tu sistema (`FT-000123`,
`FT-000123-pdf`, `EC-2026-10-C0045`). Si lo repites —se cortó la red, el usuario
le dio dos veces— el servidor no manda otro mensaje: devuelve el que ya existe con
`repetido = .T.`. Para mandar de verdad otra vez, usa otro control
(`FT-000123-pdf-2`).

## Estados de un envío

| Estado | Qué quiere decir |
|---|---|
| `pendiente` | En la cola. Sale en segundos o minutos (hay pausas entre envíos, como una persona). |
| `enviando` | El agente lo está mandando. |
| `enviado` | Salió del teléfono de la empresa. |
| `fallido` | No salió. `registro.error`: `sin_whatsapp` (ese número no tiene WhatsApp), `whatsapp_desconectado` (el agente perdió WhatsApp), u otro. |
| `incierto` | Se le entregó al agente y no confirmó (se apagó la PC, se fue el internet). **Pudo haber salido**: no se reintenta solo. Míralo antes de repetir. |
| `cancelado` | Lo cancelaste, o se desactivó el agente con el mensaje en la cola. |

Si el agente está apagado, los mensajes esperan en la cola y salen cuando vuelva.

## Frenos

Protegen el número de un bloqueo de WhatsApp. Los pone el servidor y no se saltan:

| Freno | Por defecto | Código |
|---|---|---|
| Mensajes al día por número | 100 | `whatsapp.tope_dia` |
| Números nuevos al día (a los que nunca se les había escrito) | 20 | `whatsapp.tope_nuevos` |
| El mismo texto (de 20 caracteres o más) a personas distintas en el día | 10 | `whatsapp.mismo_texto` |
| Ritmo | 6 por minuto, con pausas de 8 a 25 s | (la cola espera sola) |

Para que una tanda de facturas no choque con `mismo_texto`, **personaliza el
texto**: el nombre del cliente, el número de la factura, el monto. Eso es además
lo que hace que el cliente lo lea.

Nada a grupos: solo números.

## Errores

`mensaje` ya trae el texto en español. Los códigos:

| Código | Qué pasa |
|---|---|
| `whatsapp.numero_invalido` | El número no tiene forma de número (o es un grupo). |
| `whatsapp.texto_requerido` | Ni texto ni archivo. |
| `whatsapp.texto_muy_largo` | Más de 4,000 caracteres. |
| `whatsapp.archivo_invalido` / `whatsapp.archivo_muy_grande` | Archivo sin nombre, base64 roto, o más de 16 MB. |
| `archivo.no_existe` / `archivo.muy_grande` / `archivo.vacio` / `archivo.no_se_pudo_leer` | Lo detecta el `.prg` antes de mandar. |
| `whatsapp.sin_agente` / `whatsapp.sin_vincular` | La empresa no tiene agente activo o no ha vinculado el número. |
| `whatsapp.desde_requerido` | La empresa tiene varios números y no dijiste por cuál sale: pasa `desde` o pon `loWa.Desde`. El mensaje trae la lista. |
| `whatsapp.desde_no_encontrado` | Ese `desde` no es un número activo de la empresa (el mensaje trae los que hay). |
| `whatsapp.tope_dia` / `whatsapp.tope_nuevos` / `whatsapp.mismo_texto` | Frenos (arriba). |
| `whatsapp.no_cancelable` | Ya salió o no existe. |
| `whatsapp.mensaje_no_encontrado` | `Estado` de un id o control que no existe. |
| `err.sistema_token_login.*` | El token no sirve: mal copiado, revocado o vencido. |
| `err.ejecutar.*` | La cuenta de servicio no tiene permiso para eso. |
| `http.sin_respuesta` / `http.429` / `http.respuesta_invalida` | Red caída, demasiadas peticiones seguidas, o algo que no es el API. |

## Respuestas de los clientes

Se guardan las respuestas de los chats a los que les escribiste desde aquí en los
últimos 30 días (los demás chats del número no salen de la PC del agente), por 90
días.

Para leer solo lo nuevo, guarda el último id leído y pásalo la próxima vez:

```foxpro
lnUltimo = 0   && léelo de tu tabla de configuración
Do While .T.
  loR = loWa.RespuestasACursor("curResp", lnUltimo)
  If !loR.ok Or Reccount("curResp") = 0
    Exit
  Endif
  * ... procesar curResp ...
  lnUltimo = loR.ultimo_id
Enddo
* guardar lnUltimo
```

Si tu sistema tiene una dirección https pública, en la página puedes poner un
**webhook** y recibir un aviso (firmado con HMAC) en cuanto un mensaje sale, falla
o llega una respuesta. Desde Fox lo normal es consultar.

## Sin Fox: HTTP directo

Es un `POST` con JSON, con el token en la cabecera. El endpoint va en la ruta:

```bash
curl https://whatsapp.chalonasoft.com/api/whatsapp_enviar \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"a":"18095551234","texto":"Su factura FT-000123","control":"FT-000123",
       "archivo":{"nombre":"FT-000123.pdf","mime":"application/pdf","data":"<base64>"},
       "locale":"es"}'
```

```json
{"ok":true,"message":"","data":{"result":{"id":4,"a":"18095551234","tipo":"archivo","estado":"pendiente",
 "control":"FT-000123","archivo":{"nombre":"FT-000123.pdf","mime":"application/pdf","bytes":48211}, …}}}
```

| Endpoint | Parámetros |
|---|---|
| `whatsapp_enviar` | `a`, `desde` (número de origen; o `linea`, su id), `texto`, `archivo {nombre, mime, data}`, `control` |
| `whatsapp_mensaje_select` | `id`, `control`, `a`, `estado`, `desde` y `hasta` (fechas), `desde_numero` o `linea` (por cuál salió), `limit` (≤ 200), `offset` → `result[]` (con `desde`, `linea`), `total` |
| `whatsapp_mensaje_cancelar` | `id` |
| `whatsapp_recibido_select` | `despues_de`, `de`, `para` o `linea` (a cuál número llegó), `limit`, `offset` → `result[]` (`id, linea, para, de, nombre, texto, tipo, hora`), `total` |
| `whatsapp_linea_select` | `id`, `agente` → `result[]` (los números: `id, numero, nombre, vinculado, conectado, frenos, hoy`) |
| `whatsapp_agente_select` | `id` → `result[]` (las PC, con sus `lineas`) |

Toda respuesta es `{ok, message, data}`. Con `"locale":"es"`, si `ok` es `false`,
`message` trae el error en español y `data.message_code` el código.
