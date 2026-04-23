#!/bin/bash

# ================= VARIABLES =================
APACHE_ROOT="/var/www"
APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
APACHE_SITES_ENABLED="/etc/apache2/sites-enabled"
CSV_FILE="${1:-/home/asixadmin/clientes/clientes.csv}"
LOG_FILE="/var/log/crear_clientes.log"

# ================= FUNCIONES =================

log() {
    local nivel=$1
    local mensaje=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$nivel] $mensaje" | tee -a "$LOG_FILE"
}

# Función para mostrar mensajes en pantalla
mensaje() {
    local tipo=$1
    local mensaje=$2
    echo -e "[${tipo}] $mensaje"
}

# Función para verificar si el archivo CSV existe
comprobar_archivo_csv() {
    if [[ ! -f "$CSV_FILE" ]]; then
        mensaje "ERROR" "ERROR" "No se encuentra el archivo CSV: $CSV_FILE"
        log "ERROR" "Archivo CSV no encontrado: $CSV_FILE"
        exit 1
    fi

    if [[ ! -r "$CSV_FILE" ]]; then
        mensaje "ERROR" "ERROR" "No hay permisos de lectura para: $CSV_FILE"
        log "ERROR" "Sin permisos de lectura: $CSV_FILE"
        exit 1
    fi

    mensaje "EXITOSO" "OK" "Archivo CSV encontrado: $CSV_FILE"
    log "INFO" "Archivo CSV verificado: $CSV_FILE"
}

# Función para extraer el nombre de usuario del dominio
obtener_usuario_de_dominio() {
    local dominio=$1
    # Extrae la primera parte antes del primer punto
    echo "$dominio" | cut -d'.' -f1
}

# Función para verificar si un usuario ya existe en el sistema
usuario_existe() {
    local usuario=$1

    if getent passwd "$usuario" > /dev/null 2>&1; then
        return 0  # El usuario existe
    else
        return 1  # El usuario no existe
    fi
}

# Función para verificar si un VirtualHost ya existe
vhost_existe() {
    local dominio=$1
    if [[ -f "$APACHE_SITES_AVAILABLE/${dominio}.conf" ]]; then
        return 0  # El VirtualHost existe
    else
        return 1  # El VirtualHost no existe
    fi
}

# Función para verificar si un directorio web ya existe
directorio_existe() {
    local dominio=$1
    if [[ -d "$APACHE_ROOT/${dominio}" ]]; then
        return 0  # El directorio existe
    else
        return 1  # El directorio no existe
    fi
}

# Función para crear el directorio web
crear_directorio_web() {
    local dominio=$1
    local web_path="$APACHE_ROOT/${dominio}/public_html"

    if directorio_existe "$dominio"; then
        mensaje "ADVERTENCIA" "PELIGRO" "El directorio para $dominio ya existe. Omitiendo creación."
        log "PELIGRO" "Directorio ya existe: $APACHE_ROOT/${dominio}"
        return 0
    fi

    # Crear estructura de directorios
    mkdir -p "$web_path"
    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo crear el directorio: $web_path"
        log "ERROR" "Fallo al crear directorio: $web_path"
        return 1
    fi

    mensaje "EXITOSO" "OK" "Directorio web creado: $web_path"
    log "INFO" "Directorio creado: $web_path"
    return 0
}

# Función para crear el usuario FTP
crear_usuario_ftp() {
    local usuario=$1
    local password=$2
    local dominio=$3
    local home_dir="$APACHE_ROOT/${dominio}"

    if usuario_existe "$usuario"; then
        mensaje "ADVERTENCIA" "PELIGRO" "El usuario $usuario ya existe. Omitiendo creación."
        log "PELIGRO" "Usuario ya existe: $usuario"
        return 0
    fi

    # Crear usuario sin shell, con home específico
    useradd -m -d "$home_dir" -s /bin/false "$usuario"
    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo crear el usuario: $usuario"
        log "ERROR" "Fallo al crear usuario: $usuario"
        return 1
    fi

    # Establecer contraseña
    echo "${usuario}:${password}" | chpasswd
    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo establecer contraseña para: $usuario"
        log "ERROR" "Fallo al establecer contraseña para: $usuario"
        return 1
    fi

    mensaje "EXITOSO" "OK" "Usuario FTP creado: $usuario"
    log "INFO" "Usuario creado: $usuario"
    return 0
}

# Función para configurar permisos correctos
configurar_permisos() {
    local dominio=$1
    local usuario=$2
    local web_path="$APACHE_ROOT/${dominio}"

    # Cambiar propietario: usuario dueño, grupo www-data
    chown -R "${usuario}:www-data" "$web_path"
    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudieron asignar propietarios para: $dominio"
        log "ERROR" "Fallo al asignar propietarios: $dominio"
        return 1
    fi

    # Permisos
    chmod -R 750 "$web_path"
    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudieron asignar permisos para: $dominio"
        log "ERROR" "Fallo al asignar permisos: $dominio"
        return 1
    fi

    mensaje "EXITO" "OK" "Permisos configurados para: $dominio"
    log "INFO" "Permisos asignados para: $dominio (750)"
    return 0
}

# Función para crear archivo index.html por defecto
crear_index_defecto() {
    local dominio=$1
    local index_path="$APACHE_ROOT/${dominio}/public_html/index.html"

    if [[ -f "$index_path" ]]; then
        mensaje "ADVERTENCIA" "PELIGRO" "El archivo index.html ya existe para $dominio. No se sobrescribe."
        return 0
    fi

    cat > "$index_path" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${dominio}</title>
</head>
<body>
    <h1>Bienvenido a ${dominio}</h1>
    <p>Sitio web creado automáticamente el $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p>FTP activo: puedes subir tus archivos a este directorio.</p>
</body>
</html>
EOF

    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo crear index.html para: $dominio"
        log "ERROR" "Fallo al crear index.html: $dominio"
        return 1
    fi

    mensaje "EXITO" "OK" "Index.html creado para: $dominio"
    log "INFO" "Index.html creado: $dominio"
    return 0
}

# Función para crear el VirtualHost de Apache
crear_virtualhost() {
    local dominio=$1
    local vhost_file="$APACHE_SITES_AVAILABLE/${dominio}.conf"

    if vhost_existe "$dominio"; then
        mensaje "ADVERTENCIA" "PELIGRO" "El VirtualHost para $dominio ya existe. Omitiendo creación."
        log "PELIGRO" "VirtualHost ya existe: $dominio"
        return 0
    fi

    cat > "$vhost_file" << EOF
<VirtualHost *:80>
    ServerName ${dominio}
    DocumentRoot ${APACHE_ROOT}/${dominio}/public_html

    <Directory ${APACHE_ROOT}/${dominio}/public_html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${dominio}_error.log
    CustomLog \${APACHE_LOG_DIR}/${dominio}_access.log combined
</VirtualHost>
EOF

    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo crear VirtualHost para: $dominio"
        log "ERROR" "Fallo al crear VirtualHost: $dominio"
        return 1
    fi

    # Habilitar el sitio
    a2ensite "${dominio}.conf" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo habilitar el sitio: $dominio"
        log "ERROR" "Fallo al habilitar VirtualHost: $dominio"
        return 1
    fi

    mensaje "EXITO" "OK" "VirtualHost creado y habilitado: $dominio"
    log "INFO" "VirtualHost creado: $dominio"
    return 0
}

# Función para procesar un cliente individual
proceso_crear_cliente() {
    local dominio=$1
    local password=$2
    local usuario=$(obtener_usuario_de_dominio "$dominio")

    mensaje "INFO" "INFO" "========================================="
    mensaje "INFO" "INFO" "Procesando cliente: $dominio"
    mensaje "INFO" "INFO" "Usuario: $usuario"
    mensaje "INFO" "INFO" "========================================="

    # 1. Crear directorio web
    crear_directorio_web "$dominio" || return 1

    # 2. Crear usuario FTP
    crear_usuario_ftp "$usuario" "$password" "$dominio" || return 1

    # 3. Configurar permisos (ejecutar después de crear usuario)
    configurar_permisos "$dominio" "$usuario" || return 1

    # 4. Crear index.html por defecto
    crear_index_defecto "$dominio" || return 1

    # 5. Crear VirtualHost
    crear_virtualhost "$dominio" || return 1

    mensaje "EXITO" "SUCCESS" "Cliente $dominio procesado correctamente"
    log "INFO" "Cliente procesado exitosamente: $dominio"
    return 0
}

# Función para recargar Apache después de procesar todos
recargar_apache() {
    mensaje "INFO" "INFO" "Recargando configuración de Apache..."
    systemctl reload apache2

    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo recargar Apache"
        log "ERROR" "Fallo al recargar Apache"
        return 1
    fi

    mensaje "EXITO" "OK" "Apache recargado correctamente"
    log "INFO" "Apache recargado exitosamente"
    return 0
}

# Función para mostrar resumen
mostrar_resumen() {
    local total=$1
    local success=$2
    local failed=$3

    echo ""
    mensaje "INFO" "RESUMEN" "========================================="
    mensaje "INFO" "RESUMEN" "Total clientes procesados: $total"
    mensaje "EXITO" "RESUMEN" "Exitosos: $success"
    if [[ $failed -gt 0 ]]; then
        mensaje "ERROR" "RESUMEN" "Fallidos: $failed"
    fi
    mensaje "INFO" "RESUMEN" "========================================="

    log "INFO" "Resumen final - Total: $total, Exitosos: $success, Fallidos: $failed"
}

# ================= MAIN =================

main() {
    # Inicializar variables
    local total_clientes=0
    local clientes_exitosos=0
    local clientes_fallidos=0

    # Limpiar pantalla
    clear

    mensaje "INFO" "INICIO" "Script de creación de clientes web"
    mensaje "INFO" "INICIO" "========================================="
    log "INFO" "========== INICIO DE EJECUCIÓN =========="

    # Validaciones iniciales
    comprobar_archivo_csv

    mensaje "INFO" "INFO" "Procesando archivo CSV: $CSV_FILE"
    log "INFO" "Iniciando procesamiento del CSV"

    # Leer CSV línea por línea
    while IFS=',' read -r dominio password || [[ -n "$dominio" ]]; do
        if [[ -z "$dominio" ]]; then
            continue
        fi

        # Limpiar posibles espacios en blanco
        dominio=$(echo "$dominio" | xargs)
        password=$(echo "$password" | xargs)

        # Validar que no estén vacíos
        if [[ -z "$password" ]]; then
            mensaje "ERROR" "ERROR" "Contraseña vacía para dominio: $dominio"
            log "ERROR" "Contraseña vacía para: $dominio"
            ((clientes_fallidos++))
            continue
        fi

        ((total_clientes++))

        # Procesar cliente
        if proceso_crear_cliente "$dominio" "$password"; then
            ((clientes_exitosos++))
        else
            ((clientes_fallidos++))
            mensaje "ERROR" "ERROR" "Fallo al procesar: $dominio"
            log "ERROR" "Cliente fallido: $dominio"
        fi

    done < "$CSV_FILE"

    recargar_apache

    mostrar_resumen "$total_clientes" "$clientes_exitosos" "$clientes_fallidos"

    log "INFO" "========== FIN DE EJECUCIÓN =========="

    # Salir con código de error si hubo fallos
    if [[ $clientes_fallidos -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Ejecutar función main con todos los argumentos
main "$@"