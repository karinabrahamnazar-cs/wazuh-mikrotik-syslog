# Guardar logs de MikroTik en Wazuh (vía Syslog)
Este repositorio contiene la configuración necesaria para recibir, decodificar y visualizar la telemetría y eventos de firewall de un router MikroTik RouterOS en Wazuh SIEM sin instalar agentes, usando el protocolo Syslog estándar.

 Resumen de la Arquitectura
MikroTik envía eventos en texto plano por puerto 514 UDP.
Debian (Wazuh Manager) abre el puerto de escucha y valida que solo esa IP entregue logs.
Wazuh Engine procesa el texto usando expresiones regulares (decoders).
Wazuh Rules genera alertas indexables (Nivel 3).
Filebeat empuja las alertas hacia el Dashboard de OpenSearch.

 Guía Paso a Paso
Paso 1: Habilitar Syslog en Wazuh Manager
Conéctate por SSH a tu servidor Wazuh (192.168.1.200) y edita el archivo de configuración principal:
bash
sudo nano /var/ossec/etc/ossec.conf

Asegúrate de tener habilitado el bloque <logall> en la sección <global> para auditoría, y añade el bloque remoto para escuchar el puerto 514:
xml
<global>
  <logall>yes</logall>
  <logall_json>yes</logall_json>
</global>

<remote>
  <connection>syslog</connection>
  <port>514</port>
  <protocol>udp</protocol>
  <allowed-ips>192.168.1.1/32</allowed-ips>
  <local_ip>192.168.1.200</local_ip>
</remote>

Nota: Cambia 192.168.1.1 por la IP de tu MikroTik.
Abre el puerto en el firewall de Debian y reinicia el servicio:
bash
sudo ufw allow from 192.168.1.1 to any port 514 proto udp
sudo systemctl restart wazuh-manager


Paso 2: Configurar el envío en MikroTik (RouterOS)
Abre la terminal de tu MikroTik y ejecuta los siguientes comandos para crear la acción remota y redirigir los logs de firewall y sistema:
routeros
# 1. Crear el destino remoto hacia el servidor Debian
/system logging action add name=wazuhserver target=remote remote=192.168.1.200 remote-port=514 remote-log-format=syslog remote-protocol=udp

# 2. Asignar las reglas de telemetría que se enviarán
/system logging add action=wazuhserver topics=firewall
/system logging add action=wazuhserver topics=system
/system logging add action=wazuhserver topics=critical

Paso 3: Añadir Decodificadores Personalizados
Para romper la cadena de texto cruda del MikroTik y extraer variables limpias (IPs, puertos, interfaces), crea este archivo en Debian:
bash
sudo nano /var/ossec/etc/decoders/mikrotik_decoders.xml


Pega el siguiente código XML:
xml
<decoder name="mikrotik">
  <prematch>^firewall,info|^system,info|^dhcp,info|^critical</prematch>
</decoder>

<decoder name="mikrotik-firewall">
  <parent>mikrotik</parent>
  <prematch>dstnat:</prematch>
  <regex>in:(\S+)\s+out:\S+\s+connection-state:\S+\s+src-mac\s+\S+,\s+proto\s+(\S+)\s+\S+\s+(\d+.\d+.\d+.\d+):(\d+)->(\d+.\d+.\d+.\d+):(\d+)</regex>
  <order>interface, protocol, srcip, srcport, dstip, dstport</order>
</decoder>

Paso 4: Añadir Reglas de Alerta
Crea el archivo de reglas para que Wazuh asigne severidad a los eventos detectados:
bash
sudo nano /var/ossec/etc/rules/mikrotik_rules.xml


Pega el siguiente bloque:
xml
<group name="mikrotik,firewall,">
  <!-- Regla madre para agrupar todo lo que sea MikroTik -->
  <rule id="100100" level="0">
    <decoded_as>mikrotik</decoded_as>
    <description>Eventos generales de MikroTik RouterOS.</description>
  </rule>

  <!-- Regla para alertar intentos de conexión por NAT / Firewall -->
  <rule id="100101" level="3">
    <if_sid>100100</if_sid>
    <match>dstnat</match>
    <description>MikroTik: Intento de conexión detectado en NAT (dstnat).</description>
  </rule>
</group>

Paso 5: Testear y Aplicar Cambios
Prueba un log crudo con la herramienta de testeo nativa:
bash
/var/ossec/bin/wazuh-logtest


Pega una línea de log como esta:
firewall,info NATKALI dstnat: in:ether1-WAN IPT LIBERTY out:(unknown 0), connection-state:new src-mac 08:EC:F5:4F:D7:F8, proto TCP (SYN), 181.110.118.118:23440->192.115.101.250:2223, len 52
Deberías ver que la Fase 2 decodifica los campos por separado y la Fase 3 dispara la regla 100101.
Si todo es correcto, reinicia los servicios:
bash
sudo systemctl restart wazuh-manager
sudo systemctl restart filebeat



Visualización en el Dashboard
Ve a tu panel de Wazuh web y entra a OpenSearch Dashboards > Discover.
Cambia el rango de tiempo de búsqueda a "Today" o "Last 24 hours".
En la barra de filtrado rápido busca:
text
rule.id: "100101"
Usa el código con precaución.
Despliega cualquier registro recibido. Ahora verás los campos indexados por separado de forma estructurada (data.srcip, data.dstport, data.interface), listos para crear visualizaciones o mapas de calor de ataques.


