#!/bin/bash

# ================= VARIABLES =================
APACHE_ROOT="/var/www"
APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
CSV_FILE="${1:-/home/asixadmin/clientes/clientes.csv}"

# ================= FUNCIONES =================
mensaje() {
    local tipo=$1
    local mensaje=$2
    echo -e "[${tipo}] $mensaje"
}

comprobar_archivo_csv() {
    if [[ ! -f "$CSV_FILE" ]]; then
        mensaje "ERROR" "ERROR" "No se encuentra el archivo CSV: $CSV_FILE"
        exit 1
    fi
    mensaje "EXITOSO" "OK" "Archivo CSV encontrado: $CSV_FILE"
}

obtener_usuario_de_dominio() {
    local dominio=$1
    echo "$dominio" | cut -d'.' -f1
}

usuario_existe() {
    getent passwd "$1" > /dev/null 2>&1
}

directorio_existe() {
    [[ -d "$APACHE_ROOT/${1}" ]]
}

vhost_existe() {
    [[ -f "$APACHE_SITES_AVAILABLE/${1}.conf" ]]
}

crear_directorio_web() {
    local dominio=$1
    local web_path="$APACHE_ROOT/${dominio}/public_html"

    if directorio_existe "$dominio"; then
        mensaje "ADVERTENCIA" "PELIGRO" "El directorio para $dominio ya existe. Omitiendo."
        return 0
    fi

    mkdir -p "$web_path"
    if [[ $? -eq 0 ]]; then
        mensaje "EXITOSO" "OK" "Directorio web creado: $web_path"
        return 0
    else
        mensaje "ERROR" "ERROR" "No se pudo crear el directorio: $web_path"
        return 1
    fi
}

crear_usuario_ftp() {
    local usuario=$1
    local password=$2
    local dominio=$3
    local home_dir="$APACHE_ROOT/${dominio}"

    if usuario_existe "$usuario"; then
        mensaje "ADVERTENCIA" "PELIGRO" "El usuario $usuario ya existe. Omitiendo."
        return 0
    fi

    useradd -m -d "$home_dir" -s /bin/false "$usuario"
    if [[ $? -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "No se pudo crear el usuario: $usuario"
        return 1
    fi

    echo "${usuario}:${password}" | chpasswd
    mensaje "EXITOSO" "OK" "Usuario FTP creado: $usuario (home: $home_dir)"
    return 0
}

configurar_permisos() {
    local dominio=$1
    local usuario=$2
    local web_path="$APACHE_ROOT/${dominio}"

    chown -R "${usuario}:www-data" "$web_path"
    chmod -R 750 "$web_path"
    mensaje "EXITO" "OK" "Permisos configurados para: $dominio"
    return 0
}

crear_index_defecto() {
    local dominio=$1
    local index_path="$APACHE_ROOT/${dominio}/public_html/index.html"

    if [[ -f "$index_path" ]]; then
        return 0
    fi

    cat > "$index_path" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>${dominio}</title>
</head>
<body>
    <h1>Bienvenido a ${dominio}</h1>
    <p>FTP activo: puedes subir tus archivos.</p>
</body>
</html>
EOF
    mensaje "EXITO" "OK" "Index.html creado para: $dominio"
    return 0
}

crear_virtualhost() {
    local dominio=$1
    local vhost_file="$APACHE_SITES_AVAILABLE/${dominio}.conf"

    if vhost_existe "$dominio"; then
        mensaje "ADVERTENCIA" "PELIGRO" "VirtualHost para $dominio ya existe. Omitiendo."
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

    a2ensite "${dominio}.conf" > /dev/null 2>&1
    mensaje "EXITO" "OK" "VirtualHost creado: $dominio"
    return 0
}

proceso_crear_cliente() {
    local dominio=$1
    local password=$2
    local usuario=$(obtener_usuario_de_dominio "$dominio")

    mensaje "INFO" "INFO" "========================================="
    mensaje "INFO" "INFO" "Dominio: $dominio | Usuario FTP: $usuario"
    mensaje "INFO" "INFO" "========================================="

    crear_directorio_web "$dominio" || return 1
    crear_usuario_ftp "$usuario" "$password" "$dominio" || return 1
    configurar_permisos "$dominio" "$usuario" || return 1
    crear_index_defecto "$dominio" || return 1
    crear_virtualhost "$dominio" || return 1

    mensaje "EXITO" "SUCCESS" "Cliente $dominio procesado correctamente"
    return 0
}

main() {
    local total=0 exitosos=0 fallidos=0

    # Verificar que el script se ejecute con privilegios de root
    if [[ $EUID -ne 0 ]]; then
        mensaje "ERROR" "ERROR" "Ejecutar con sudo"
        exit 1
    fi

    clear
    mensaje "INFO" "INICIO" "Script de creación de clientes web"
    comprobar_archivo_csv

    while IFS=',' read -r dominio password || [[ -n "$dominio" ]]; do
        [[ -z "$dominio" ]] && continue
        dominio=$(echo "$dominio" | xargs)
        password=$(echo "$password" | xargs)

        [[ -z "$password" ]] && { ((fallidos++)); continue; }

        ((total++))
        if proceso_crear_cliente "$dominio" "$password"; then
            ((exitosos++))
        else
            ((fallidos++))
        fi
    done < "$CSV_FILE"

    systemctl reload apache2

    echo ""
    mensaje "INFO" "RESUMEN" "Total: $total | Exitosos: $exitosos | Fallidos: $fallidos"

    exit $((fallidos > 0 ? 1 : 0))
}

main "$@"