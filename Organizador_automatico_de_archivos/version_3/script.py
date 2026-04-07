import os # Para manejar archivos y directorios del sistema operativo
import shutil # Para mover archivos de un lugar a otro

# Ruta de la carpeta de origen
ruta = "C:/proyects/Python/Organizador_automatico_de_archivos/version_3/"

# Tipos de archivos
extensiones = {
    "imagenes": [".jpg", ".png", ".jpeg"],
    "documentos": [".txt", ".pdf"],
    "musica": [".mp3", ".wav"],
    "codigo": [".py", ".js"],
    "archivos_comprimidos": [".zip", ".xlsx"] # Agregando una categoría para archivos comprimidos y hojas de cálculo
}

# Recorrer archivos
for archivo in os.listdir(ruta):
    ruta_archivo = os.path.join(ruta, archivo)

    if os.path.isfile(ruta_archivo):
        nombre, extension = os.path.splitext(archivo)

        for carpeta, exts in extensiones.items():
            if extension.lower() in exts:
                carpeta_destino = os.path.join(ruta, carpeta)
                
                # Crear carpeta si no existe
                if not os.path.exists(carpeta_destino):
                    os.makedirs(carpeta_destino)

                # Renombrar archivo si ya existe en la carpeta destino
                destino_final = os.path.join(carpeta_destino, archivo)
                i = 1
                while os.path.exists(destino_final):
                    nuevo_nombre = f"{nombre}_({i})"
                    destino_final = os.path.join(carpeta_destino, nuevo_nombre + extension)
                    i += 1

                # Mover archivo
                shutil.move(ruta_archivo, destino_final)
                print(f"Movido: {archivo} a {carpeta}")