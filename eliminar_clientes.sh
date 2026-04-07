#!/bin/bash
##############################################################################
# Script: eliminar_clientes.sh
# Descripción: Elimina sitios web y usuarios FTP creados por crear_clientes.sh
# Autor: Juanjo Gomez
# Fecha: 03-31-2026
# Uso: sudo ./eliminar_clientes.sh [ruta_al_csv]
##############################################################################

# ================= CONFIGURACIÓN =================
APACHE_ROOT="/var/www"
APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
CSV_FILE="${1:-/home/asixadmin/clientes/clientes.csv}"
LOG_FILE="/var/log/eliminar_clientes.log"

# ================= FUNCIONES =================
log() {
    local nivel=$1
    local mensaje=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$nivel] $mensaje" | tee -a "$LOG_FILE"
}

mensaje() {
    local tipo=$1
    local mensaje=$2
    echo -e "[${tipo}] $mensaje"
}

obtener_usuario_de_dominio() {
    echo "$1" | cut -d'.' -f1
}

usuario_existe() {
    getent passwd "$1" > /dev/null 2>&1
}

eliminar_usuario() {
    local usuario=$1
    
    if ! usuario_existe "$usuario"; then
        mensaje "PELIGRO" "Usuario $usuario no existe. Omitiendo."
        return 0
    fi
    
    # Eliminar usuario y su home
    userdel -r "$usuario" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        mensaje "OK" "Usuario eliminado: $usuario"
        log "INFO" "Usuario eliminado: $usuario"
    else
        mensaje "ERROR" "ERROR" "No se pudo eliminar usuario: $usuario"
        log "ERROR" "Fallo al eliminar usuario: $usuario"
        return 1
    fi
}

eliminar_vhost() {
    local dominio=$1
    local vhost_file="$APACHE_SITES_AVAILABLE/${dominio}.conf"
    
    if [[ ! -f "$vhost_file" ]]; then
        mensaje "ADVERTENCIA" "VirtualHost para $dominio no existe. Omitiendo."
        return 0
    fi
    
    # Deshabilitar el sitio
    a2dissite "${dominio}.conf" > /dev/null 2>&1
    
    # Eliminar el archivo de configuración
    rm -f "$vhost_file"
    
    mensaje "EXITOSO" "VirtualHost eliminado: $dominio"
    log "INFO" "VirtualHost eliminado: $dominio"
}

eliminar_directorio_web() {
    local dominio=$1
    local web_path="$APACHE_ROOT/${dominio}"
    
    if [[ ! -d "$web_path" ]]; then
        mensaje "ADVERTENCIA" "PELIGRO" "Directorio para $dominio no existe. Omitiendo."
        return 0
    fi
    
    # Confirmación para producción (opcional)
    rm -rf "$web_path"
    
    mensaje "EXITOSO" "Directorio web eliminado: $web_path"
    log "INFO" "Directorio eliminado: $web_path"
}

proceso_eliminacion_cliente() {
    local dominio=$1
    local usuario=$(obtener_usuario_de_dominio "$dominio")
    
    mensaje "INFO" "Eliminando: $dominio"
    
    eliminar_vhost "$dominio"
    eliminar_usuario "$usuario"
    eliminar_directorio_web "$dominio"
    
    mensaje "EXITOSO" "Cliente $dominio eliminado"
    log "INFO" "Cliente eliminado: $dominio"
}

recargar_apache() {
    systemctl reload apache2
    mensaje "EXITOSO" "Apache recargado"
}

main() {
    clear
    
    mensaje "ERROR" "Este script ELIMINARÁ clientes y TODOS sus datos"
    mensaje "ERROR" "¿Estás seguro? (escribe 'CONFIRMAR' para continuar)"
    read -r confirmacion
    
    if [[ "$confirmacion" != "CONFIRMAR" ]]; then
        mensaje "ADVERTENCIA" "Operación cancelada"
        exit 0
    fi
        
    if [[ ! -f "$CSV_FILE" ]]; then
        mensaje "ERROR" "Archivo CSV no encontrado: $CSV_FILE"
        exit 1
    fi
    
    log "INFO" "========== INICIO DE ELIMINACIÓN =========="
    
    while IFS=',' read -r dominio password || [[ -n "$dominio" ]]; do
        [[ -z "$dominio" ]] && continue
        dominio=$(echo "$dominio" | xargs)
        proceso_eliminacion_cliente "$dominio"
    done < "$CSV_FILE"
    
    recargar_apache
    
    log "INFO" "========== FIN DE ELIMINACIÓN =========="
    mensaje "COMPLETADO" "Proceso de eliminación finalizado"
}

main "$@"