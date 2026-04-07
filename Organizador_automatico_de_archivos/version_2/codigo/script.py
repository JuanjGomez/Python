import os # Para manejar archivos y directorios del sistema operativo
import shutil # Para mover archivos de un lugar a otro

# Ruta de la carpeta de origen
ruta = "C:/proyects/Python/Organizador_automatico_de_archivos/version_2/"

# Tipos de archivos
extensiones = {
    "imagenes": [".jpg", ".png", ".jpeg"],
    "documentos": [".txt", ".pdf"],
    "musica": [".mp3", ".wav"],
    "codigo": [".py", ".js"],
    "otros": [".zip", ".xlsx"] # Agregando una categoría para archivos comprimidos y hojas de cálculo
}

def obtener_carpeta(extension):
    for carpeta, exts in extensiones.items():
        if extension.lower() in exts:
            return carpeta
        return "otros" # Si no coincide con ninguna categoria, se asigna a otros
    
def mover_archivo(ruta_archivo, carpeta_destino, nombre, extension):
    if not os.path.exists(carpeta_destino):
        os.makedirs(carpeta_destino)

    destino_final = os.path.join(carpeta_destino, nombre + extension)
    i = 1

    while os.path.exists(destino_final):
        destino_final = os.path.join(
            carpeta_destino, f"{nombre}_({i}){extension}"
        )
        i += 1

    shutil.move(ruta_archivo, destino_final)
    print(f"Movido: {nombre + extension} -> {carpeta_destino}")

# Recorrer archivos
for archivo in os.listdir(ruta):
    ruta_archivo = os.path.join(ruta, archivo)

    if os.path.isfile(ruta_archivo):
        nombre, extension = os.path.splitext(archivo)
        extension = extension.lower()

        carpeta = obtener_carpeta(extension)
        carpeta_destino = os.path.join(ruta, carpeta)

        try:
            mover_archivo(ruta_archivo, carpeta_destino, nombre, extension)
        except Exception as e:
            print(f"Error al mover {archivo}: {e}")