# Integración de MikroTik RouterOS con Wazuh SIEM mediante Syslog

Este repositorio contiene los archivos de configuración necesarios para integrar un router MikroTik RouterOS con Wazuh SIEM, permitiendo centralizar eventos de firewall y sistema, interpretar sus registros y generar alertas de seguridad sin instalar agentes en el router.

La integración utiliza Syslog sobre UDP/514, decoders personalizados y reglas locales de Wazuh para identificar eventos relevantes y facilitar su análisis desde el dashboard.

## Arquitectura

```text
┌──────────────────────┐
│  MikroTik RouterOS   │
│  Firewall / System   │
└──────────┬───────────┘
           │ Syslog UDP/514
           ▼
┌──────────────────────┐
│   Wazuh Manager      │
│  Recepción de logs   │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Custom Decoders      │
│ Extracción de campos │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Local Rules          │
│ Generación de alertas│
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Wazuh Indexer        │
│ Wazuh Dashboard      │
└──────────────────────┘
```

## Estructura del repositorio

| Archivo | Descripción |
|---|---|
| `mikrotik_decoders.xml` | Decoders personalizados para reconocer eventos de MikroTik y extraer campos de tráfico de firewall. |
| `mikrotik_rules.xml` | Reglas locales para clasificar eventos y generar alertas. |
| `mikrotik_config.rsc` |  Script de configuración RouterOS | Comandos para crear el destino Syslog y habilitar el envío de eventos al servidor Wazuh. |

Consulta los archivos del repositorio para obtener el contenido completo de cada configuración.

## Requisitos

- MikroTik RouterOS con acceso administrativo.
- Servidor Debian con Wazuh Manager instalado y operativo.
- Conectividad IP entre el router y el servidor.
- Puerto UDP/514 permitido entre ambos dispositivos.
- Acceso administrativo al sistema Debian.

## Guía de implementación

### 1. Configurar la recepción de Syslog en Wazuh

En el servidor Wazuh, edita la configuración principal:

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Dentro de la configuración, verifica que exista un bloque `remote` para recibir conexiones Syslog. Si todavía no existe, agrega el bloque correspondiente utilizando los valores de tu entorno.

| Parámetro | Valor de ejemplo |
|---|---|
| Protocolo | UDP |
| Puerto | 514 |
| IP del servidor | `192.168.1.200` |
| IP del MikroTik | `192.168.1.1` |

**Importante:** sustituye las direcciones de ejemplo por las de tu laboratorio. En `allowed-ips`, utiliza la IP individual del router con máscara `/32` si deseas limitar la recepción a ese dispositivo.

La configuración de archivado global (`logall` y `logall_json`) es opcional para esta integración básica. Habilítala únicamente si necesitas conservar los eventos originales y has evaluado sus requisitos de almacenamiento y configuración de archivos de alertas.

Permite el tráfico Syslog desde el router, si utilizas UFW:

```bash
sudo ufw allow from 192.168.1.1 to any port 514 proto udp
```

### 2. Configurar el envío desde MikroTik

Abre la terminal de RouterOS y ejecuta el script de configuración incluido en el repositorio.


El script configura:

- Un destino remoto Syslog.
- El envío de eventos del firewall.
- El envío de eventos del sistema.
- El envío de eventos críticos.


### 3. Instalar los decoders personalizados

Copia el archivo `mikrotik_decoders.xml` al directorio de decoders locales:

```bash
sudo cp mikrotik_decoders.xml /var/ossec/etc/decoders/
```

Los decoders permiten que Wazuh reconozca determinados formatos de mensajes de MikroTik y extraiga campos estructurados de los registros de firewall.

Para los eventos compatibles con el decoder de firewall, se contemplan campos como:

- `interface`
- `protocol`
- `srcip`
- `srcport`
- `dstip`
- `dstport`

La extracción depende de que el mensaje recibido coincida con el formato esperado por las expresiones regulares.

### 4. Instalar las reglas de alerta

Copia el archivo `mikrotik_rules.xml` al directorio de reglas locales:

```bash
sudo cp mikrotik_rules.xml /var/ossec/etc/rules/
```

Las reglas permiten clasificar los eventos decodificados y asignarles un nivel de alerta.

En esta implementación se utilizan los siguientes identificadores:

| ID | Función |
|---|---|
| `100100` | Regla base para eventos reconocidos de MikroTik. |
| `100101` | Alerta para eventos de firewall asociados con `dstnat`. |

Los niveles de alerta configurados son los definidos en el archivo de reglas del repositorio.

**Nota:** una alerta de nivel 3 indica que el evento ha sido clasificado por la regla; no significa necesariamente que se haya confirmado un ataque o una intrusión.

### 5. Validar los decoders y las reglas

Antes de reiniciar el servicio, ejecuta la herramienta de pruebas de Wazuh:

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Introduce un evento de ejemplo compatible con el formato que espera el decoder de firewall:

```text
firewall,info NATKALI dstnat: in:ether1-WAN IPT LIBXXX out:(unknown 0), connection-state:new src-mac 08:EC:F5:4F:D7:F8, proto TCP (SYN), 181.110.118.118:23440->192.115.101.250:22, len 52
```

Comprueba que:

1. La fase 1 reconoce el mensaje de entrada.
2. La fase 2 identifica el decoder y extrae los campos esperados.
3. La fase 3 activa la regla de alerta correspondiente.

El resultado esperado para el evento de ejemplo es la activación de la regla `100101`, siempre que el decoder y las reglas instaladas coincidan con la configuración del repositorio.

Si los resultados son correctos, reinicia el servicio:

```bash
sudo systemctl restart wazuh-manager
sudo systemctl status wazuh-manager --no-pager
```

### 6. Consultar los eventos en Wazuh Dashboard

Accede al dashboard de Wazuh y abre la vista de alertas o Discover, según la configuración de tu instalación.

A continuación:

1. Selecciona un rango de tiempo que incluya los eventos de la prueba.
2. Filtra por el identificador de regla `100101`.
3. Abre una alerta y examina los campos decodificados.
4. Comprueba las direcciones IP, los puertos y el protocolo cuando estén disponibles.

Puedes utilizar una consulta como:

```text
rule.id: 100101
```

También puedes buscar por la IP del router o por otros campos que estén presentes en los documentos indexados.

Los nombres y rutas de los campos pueden variar según la versión de Wazuh, el decoder utilizado y la estructura del evento indexado.


## Objetivo del laboratorio

Demostrar cómo integrar un dispositivo de red sin agente con un SIEM, transformar registros Syslog en eventos estructurados y aplicar reglas de detección personalizadas para mejorar la visibilidad del tráfico de red.

Esta implementación puede ampliarse con detecciones para escaneos de puertos, intentos de acceso administrativo, cambios de configuración y otros comportamientos relevantes para la seguridad de la infraestructura.
