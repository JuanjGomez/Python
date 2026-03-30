#print("Estoy programando en Python 🔥")

# with open("texto.txt", "r") as archivo:
#     contenido = archivo.read()
#     print(contenido)

# 2. Contar palabras
# with open("texto.txt", "r") as archivo:
#     contenido = archivo.read()
#     palabras = contenido.split()
#     print("Numero de palabras:", len(palabras))

# 3. Contar cuantas veces aparece una palabra
palabra = "python"

with open("texto.txt", "r") as archivo:
    contenido = archivo.read().lower()
    contador = contenido.count(palabra)

print(f"La palabra '{palabra}' aparece {contador} veces")