# Configuración de Syslog Remoto hacia Wazuh Manager
# Reemplazar la IP remota por la de tu servidor Debian (Wazuh)

/system logging action add name=wazuhserver target=remote remote=192.168.1.200 remote-port=514 remote-log-format=syslog remote-protocol=udp

/system logging add action=wazuhserver topics=firewall
/system logging add action=wazuhserver topics=system
/system logging add action=wazuhserver topics=critical
