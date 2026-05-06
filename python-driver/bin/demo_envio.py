#!/usr/bin/env python3
"""demo_envio.py — demostración standalone del cliente Python ECF.

Envía 10 comprobantes (tipos 31-32-33-34-41-43-44-45-46-47) al portal
testecf usando EcfClient. eNCF generado por servidor (portal testecf).
No requiere BD.

Uso:
  cd ecf/clients/python-driver
  python3 bin/demo_envio.py

Emisor: Vicortiz Softwares srl (RNC 131086268).
Portal: testecf (pruebas DGII — no afecta datos reales).
"""
from __future__ import annotations

import copy
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'src'))

from chalona_driver.ecf_client import EcfClient, EcfApiError  # noqa: E402

# ---------------------------------------------------------------------------
# Configuración emisor (Vicortiz Softwares srl — empresa de prueba)
# ---------------------------------------------------------------------------
_RNC = '131086268'
_NOMBRE = 'Vicortiz Softwares srl'
_DIRECCION = 'Santo Domingo, República Dominicana'
_EMAIL = 'victorortiz941@gmail.com'
_USUARIO = 'test@r131086268.com'
_CLAVE = '1234'
_PORTAL = 'testecf'
_BASE_URL = 'https://ecf-service.vicortiz.com'

# ---------------------------------------------------------------------------
# 10 comprobantes de certificación DGII (tipos 31-32-33-34-41-43-44-45-46-47)
# Fuente: documentos_certificacion_dgii — datos del emisor se sobreescriben
# en obtener_documentos().
# ---------------------------------------------------------------------------
_JSON_BASE = r'[{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"31","eNCF":"E310000000003","FechaVencimientoSecuencia":"31-12-2025","IndicadorMontoGravado":"0","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"260000.00","MontoGravadoI1":"260000.00","ITBIS1":"18","TotalITBIS":"46800.00","TotalITBIS1":"46800.00","MontoTotal":"306800.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"260000.00","MontoItem":"260000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"32","eNCF":"E320000000003","IndicadorMontoGravado":"0","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","Municipio":"320301","Provincia":"320000","TablaTelefonoEmisor":["809-472-7676","809-491-1918"],"CorreoEmisor":"DOCUMENTOSELECTRONICOSDE0612345678969789+9000000000000000000000000000001@123.COM","WebSite":"www.facturaelectronica.com","CodigoVendedor":"AA0000000100000000010000000002000000000300000000050000000006","NumeroFacturaInterna":"123456789016","NumeroPedidoInterno":"123456789016","ZonaVenta":"NORTE","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"260000.00","MontoGravadoI1":"260000.00","ITBIS1":"18","TotalITBIS":"46800.00","TotalITBIS1":"46800.00","MontoTotal":"306800.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"260000.00","MontoItem":"260000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"33","eNCF":"E310000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoExento":"1000.00","MontoTotal":"1000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"1000.00","MontoItem":"1000.00"}],"InformacionReferencia":{"NCFModificado":"E320000000002","FechaNCFModificado":"01-04-2020","CodigoModificacion":"3"}},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"34","eNCF":"E340000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoExento":"1000.00","MontoTotal":"1000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"1000.00","MontoItem":"1000.00"}],"InformacionReferencia":{"NCFModificado":"E320000000002","FechaNCFModificado":"01-04-2020","CodigoModificacion":"3"}},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"41","eNCF":"E410000000001","FechaVencimientoSecuencia":"31-12-2025","IndicadorMontoGravado":"0","TipoPago":"1","TablaFormasPago":[{"FormaPago":"1","MontoPago":"9000.00"}]},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020","Municipio":"010101","Provincia":"010000","TablaTelefonoEmisor":["809-472-7676","809-491-1918"]},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 02","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000"},"Totales":{"MontoGravadoTotal":"10000.00","MontoGravadoI1":"10000.00","ITBIS1":"18","TotalITBIS":"1800.00","TotalITBIS1":"1800.00","MontoTotal":"11800.00","ValorPagar":"11800.00","TotalITBISRetenido":"1800.00","TotalISRRetencion":"1000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","Retencion":{"IndicadorAgenteRetencionoPercepcion":"1","MontoITBISRetenido":"1800.00","MontoISRRetenido":"1000.00"},"NombreItem":"SERVICIO PUBLICIDAD","IndicadorBienoServicio":"2","DescripcionItem":"LOREM IPSUM DOLOR SITI AMET, CONSECTETUR ADIPISCI IT. VESTIBULUM 1234 FERMENTUM E-X, CONSEQUAT (IACULIS) ARCU. PELLENTESQUE RUTRUM DUI EGET SAPIEN DICTUM, EU MOLLIS LECTUS AUCTOR. NUNC ORNARE ERAT QUIS NISL IMPERDIET PORTA. NULLAM VEL PHARETRA LEO, PELLENTESQUE FERMENTUM LECTUS. VIVAMUS ORCI IPSUM, SCELERISQUE QUIS VEHICULA QUIS, TEMPUS VITAE PURUS. ALIQUAM SAGITTIS EROS VITAE ANTE FAUCIBUS AUCTOR. MAECENAS PELLENTESQUE VEL EST IN CONGUE. FUSCE ARCU LIGULA, HENDRERIT EU DOLOR A, FACILISIS GRAVIDA DOLOR. PELLENTESQUE SED ALIQUET DOLOR. MAURIS BIBENDUM VEHICULA DICTUM. ETIAM TEMPUS, ODIO NEC CONSECTETUR IACULIS, ODIO NIBH EGESTAS FELIS, SED VIVERRA MAGNA EX SUSCIPIT AUGUE. PELLENTESQUE VESTIBULUM, LACUS NON MATTIS MOLESTIE, NEQUE LEO FACILISIS URNA, AC SUSCIPIT ERAT NISI ET MAGNA. PRAESENT PLACERAT SED LEO A GRAVIDA. MORBI ID ELIT LACUS. CLASS APTENT TACITI SOCIOSQU AD LITORA TORQUENT PER CONUBIA NOSTRA, PER INCEPTOS HIMENAEOS, CONSECTETUR ADIPISCING ELIT. NUNC ORNARE ERAT QUIS NISL IMP.","CantidadItem":"1.00","UnidadMedida":"43","PrecioUnitarioItem":"10000.00","MontoItem":"10000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"43","eNCF":"E430000000001","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","Municipio":"010101","Provincia":"010000","TablaTelefonoEmisor":["809-472-7676","809-491-1918"],"CorreoEmisor":"DOCUMENTOSELECTRONICOSDE0612345678969789+9000000000000000000000000000001@123.COM","WebSite":"www.facturaelectronica.com","NumeroFacturaInterna":"123456789016","NumeroPedidoInterno":"123456789016","FechaEmision":"01-04-2020"},"Totales":{"MontoExento":"700.00","MontoTotal":"700.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Peajes viaje semana I","IndicadorBienoServicio":"2","CantidadItem":"7.00","UnidadMedida":"43","PrecioUnitarioItem":"100.00","MontoItem":"700.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"44","eNCF":"E440000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"","IdentificadorExtranjero":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoExento":"260000.00","MontoTotal":"260000.00","ValorPagar":"260000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"260000.00","MontoItem":"260000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"45","eNCF":"E450000000003","FechaVencimientoSecuencia":"31-12-2025","IndicadorMontoGravado":"0","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"30000.00","MontoGravadoI1":"30000.00","ITBIS1":"18","TotalITBIS":"5400.00","TotalITBIS1":"5400.00","MontoTotal":"35400.00","ValorPagar":"35400.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","NombreItem":"SERVICIO PUBLICIDAD","IndicadorBienoServicio":"2","DescripcionItem":"prestaci\u00f3n de servicios relacionados con la creaci\u00f3n, ejecuci\u00f3n y distribuci\u00f3n de campa\u00f1as publicitarias.","CantidadItem":"1.00","UnidadMedida":"43","PrecioUnitarioItem":"30000.00","MontoItem":"30000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"46","eNCF":"E460000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"1800000.00","MontoGravadoI3":"1800000.00","ITBIS3":"0","TotalITBIS":"0.00","TotalITBIS3":"0.00","MontoTotal":"1800000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"3","NombreItem":"AGUACATE CRIOLLO","IndicadorBienoServicio":"1","CantidadItem":"100.00","UnidadMedida":"43","PrecioUnitarioItem":"18000.00","MontoItem":"1800000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"47","eNCF":"E470000000003","FechaVencimientoSecuencia":"31-12-2025"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"IdentificadorExtranjero":"533445888","RazonSocialComprador":"ALEJA FERMIN SANTOS"},"Totales":{"MontoExento":"180000.00","MontoTotal":"180000.00","TotalISRRetencion":"48600.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","Retencion":{"IndicadorAgenteRetencionoPercepcion":"1","MontoISRRetenido":"48600.00"},"NombreItem":"LICENCIA WYI","IndicadorBienoServicio":"2","CantidadItem":"1.00","UnidadMedida":"43","PrecioUnitarioItem":"180000.00","MontoItem":"180000.00"}]}]'


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _fecha_hoy() -> str:
    d = date.today()
    return f'{d.day:02d}-{d.month:02d}-{d.year}'


def obtener_documentos() -> list:
    raw: list = json.loads(_JSON_BASE)
    docs: list = copy.deepcopy(raw)
    fecha = _fecha_hoy()

    for doc in docs:
        enc = doc['Encabezado']
        id_doc = enc['IdDoc']
        emisor = enc['Emisor']

        # Vaciar eNCF — el servidor lo genera para testecf.
        id_doc['eNCF'] = ''

        emisor['RNCEmisor'] = _RNC
        emisor['RazonSocialEmisor'] = _NOMBRE
        emisor['NombreComercial'] = _NOMBRE
        emisor['DireccionEmisor'] = _DIRECCION
        emisor['CorreoEmisor'] = _EMAIL
        emisor['FechaEmision'] = fecha

        # Tipos 33/34: FechaNCFModificado = hoy (días=0 → IndicadorNotaCredito=0).
        # NCFModificado se reemplaza en main() con el eNCF del tipo 32.
        ref = doc.get('InformacionReferencia')
        if ref:
            ref['FechaNCFModificado'] = fecha

    return docs


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main() -> None:
    docs = obtener_documentos()

    print('=== demo_certificacion (Python) ===')
    print(f'  baseUrl  : {_BASE_URL}')
    print(f'  usuario  : {_USUARIO}')
    print(f'  emisor   : {_RNC} / {_NOMBRE}')
    print(f'  portal   : {_PORTAL}')
    print(f'  docs     : {len(docs)} comprobantes (eNCF generado por servidor)')
    print()

    client = EcfClient(base_url=_BASE_URL)

    try:
        print('-- Login...')
        login_data = client.login(_USUARIO, _CLAVE)
        emp_nombre = (login_data.get('empresa') or {}).get('nombre', '')
        print(f'   OK — empresa: {emp_nombre}')
        print()
    except EcfApiError as e:
        print(f'Login falló: {e}', file=sys.stderr)
        sys.exit(1)

    ok_count = 0
    fail_count = 0
    resumen: list = []
    encf_tipo32: str | None = None

    for i, doc in enumerate(docs):
        enc = doc['Encabezado']
        id_doc = enc['IdDoc']
        tipo: str = id_doc['TipoeCF']

        # Inyectar NCFModificado real en ND (33) y NC (34).
        if tipo in ('33', '34') and encf_tipo32 is not None:
            ref = doc.get('InformacionReferencia')
            if ref:
                ref['NCFModificado'] = encf_tipo32

        encf: str = id_doc['eNCF']
        print(f'[{i + 1}/{len(docs)}] Tipo {tipo}  eNCF: {encf}')
        try:
            r = client.envia_ecf(rnc=_RNC, portal=_PORTAL, json_doc=doc)
            estado = r.get('estado') or 'ok'
            encf_result = r.get('numero') or encf
            print(f'  OK  - estado: {estado}  eNCF: {encf_result}')
            resumen.append(f'OK   Tipo {tipo}  {encf_result}  estado={estado}')
            ok_count += 1
            if tipo == '32':
                encf_tipo32 = encf_result
        except EcfApiError as e:
            print(f'  FAIL - {e.code}')
            resumen.append(f'FAIL Tipo {tipo}  {e.code}')
            fail_count += 1

    print()
    print('=========================================')
    print(f'  RESUMEN: {ok_count} ok / {fail_count} fail (de {len(docs)})')
    print('=========================================')
    for r in resumen:
        print(f'  {r}')
    print()

    sys.exit(1 if fail_count > 0 else 0)


if __name__ == '__main__':
    main()
