#!/bin/bash

# ================= VARIABLES =================
APACHE_ROOT="/var/www"
APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
APACHE_SITES_ENABLED="/etc/apache2/sites-enabled"
CSV_FILE="${1:-/home/asixadmin/clientes/clientes.csv}"
LOG_FILE="/var/log/eliminar_clientes.log"

# ================= FUNCIONES =================
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

directorio_web_existe() {
    [[ -d "$APACHE_ROOT/${1}" ]]
}

vhost_existe() {
    [[ -f "$APACHE_SITES_AVAILABLE/${1}.conf" ]]
}

eliminar_usuario() {
    local usuario=$1

    if ! usuario_existe "$usuario"; then
        mensaje "ADVERTENCIA" "Usuario $usuario no existe. Omitiendo."
        return 0
    fi

    pkill -u "$usuario" 2>/dev/null

    userdel -r "$usuario" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        mensaje "EXITO" "Usuario eliminado: $usuario"
    else
        mensaje "ERROR" "ERROR" "No se pudo eliminar usuario: $usuario"
        return 1
    fi
    return 0
}

eliminar_vhost() {
    local dominio=$1
    local vhost_file="$APACHE_SITES_AVAILABLE/${dominio}.conf"

    if ! vhost_existe "$dominio"; then
        mensaje "ADVERTENCIA" "VirtualHost para $dominio no existe. Omitiendo."
        return 0
    fi

    a2dissite "${dominio}.conf" > /dev/null 2>&1

    rm -f "$vhost_file"

    mensaje "EXITO" "VirtualHost eliminado: $dominio"
    return 0
}

eliminar_directorio_web() {
    local dominio=$1
    local web_path="$APACHE_ROOT/${dominio}"

    if ! directorio_web_existe "$dominio"; then
        mensaje "ADVERTENCIA" "Directorio para $dominio no existe. Omitiendo."
        return 0
    fi

    rm -rf "$web_path"

    if [[ $? -eq 0 ]]; then
        mensaje "EXITO" "Directorio web eliminado: $web_path"
    else
        mensaje "ERROR" "ERROR" "No se pudo eliminar directorio: $web_path"
        return 1
    fi
    return 0
}

proceso_eliminacion_cliente() {
    local dominio=$1
    local usuario=$(obtener_usuario_de_dominio "$dominio")

    echo ""
    mensaje "INFO" "========================================="
    mensaje "INFO" "Eliminando cliente: $dominio"
    mensaje "INFO" "Usuario asociado: $usuario"
    mensaje "INFO" "========================================="

    eliminar_vhost "$dominio"

    eliminar_usuario "$usuario"

    eliminar_directorio_web "$dominio"

    mensaje "EXITO" "Cliente $dominio eliminado completamente"
    return 0
}

recargar_apache() {
    mensaje "INFO" "Recargando servicios..."

    systemctl reload apache2
    if [[ $? -eq 0 ]]; then
        mensaje "EXITO" "Apache recargado correctamente"
    else
        mensaje "ERROR" "ERROR" "No se pudo recargar Apache"
    fi
}

main() {
    local total_clientes=0
    local clientes_eliminados=0
    local clientes_con_error=0

    # Verificar que se ejecuta como root
    if [[ $EUID -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "Este script debe ejecutarse como root (sudo)"
        exit 1
    fi

    clear

    echo ""
    mensaje "ERROR" "╔══════════════════════════════════════════════════╗"
    mensaje "ERROR" "║  ATENCIÓN: Este script ELIMINARÁ clientes y      ║"
    mensaje "ERROR" "║  TODOS sus datos (web, usuarios, configuraciones)║"
    mensaje "ERROR" "╚══════════════════════════════════════════════════╝"
    echo ""
    mensaje "ERROR" "¿Estás seguro? (escribe 'CONFIRMAR' para continuar)"
    read -r confirmacion

    if [[ "$confirmacion" != "CONFIRMAR" ]]; then
        mensaje "ADVERTENCIA" "Operación cancelada por el usuario"
        exit 0
    fi

    if [[ ! -f "$CSV_FILE" ]]; then
        mensaje "ERROR" "ERROR" "Archivo CSV no encontrado: $CSV_FILE"
        exit 1
    fi

    if [[ ! -r "$CSV_FILE" ]]; then
        mensaje "ERROR" "ERROR" "No hay permisos de lectura para: $CSV_FILE"
        exit 1
    fi

    mensaje "EXITO" "Archivo CSV encontrado: $CSV_FILE"

    while IFS=',' read -r dominio password || [[ -n "$dominio" ]]; do
        [[ -z "$dominio" ]] && continue

        # Limpiar espacios en blanco
        dominio=$(echo "$dominio" | xargs)

        ((total_clientes++))

        if proceso_eliminacion_cliente "$dominio"; then
            ((clientes_eliminados++))
        else
            ((clientes_con_error++))
            mensaje "ERROR" "ERROR" "Fallo al eliminar: $dominio"
            log "ERROR: Fallo al eliminar cliente: $dominio"
        fi

    done < "$CSV_FILE"

    recargar_apache

    echo ""
    mensaje "INFO" "Los logs se han guardado en: $LOG_FILE"

    if [[ $clientes_con_error -gt 0 ]]; then
        mensaje "ERROR" "Proceso completado con errores"
        exit 1
    else
        mensaje "EXITO" "Proceso de eliminación completado exitosamente"
        exit 0
    fi
}

main "$@"