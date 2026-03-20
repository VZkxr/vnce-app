import re

def actualizar_json_solo_malcolm():
    ruta_archivo = 'datos.json'
    
    with open(ruta_archivo, 'r', encoding='utf-8') as f:
        contenido = f.read()

    # 1. Encontrar dónde está Malcolm
    inicio_malcolm = contenido.find('"titulo": "Malcolm el de en Medio"')
    
    if inicio_malcolm == -1:
        print("No se encontró a Malcolm en el archivo.")
        return

    # 2. Encontrar dónde empieza la siguiente serie para delimitar el bloque.
    # Buscamos el próximo '"tmdbId":' que aparezca después de Malcolm.
    fin_malcolm = contenido.find('"tmdbId":', inicio_malcolm)
    
    if fin_malcolm == -1:
        # Si no hay un tmdbId después, significa que Malcolm es la última serie del archivo
        fin_malcolm = len(contenido)

    # 3. Separar el texto en tres rebanadas: el inicio intacto, el bloque de Malcolm, y el resto intacto
    parte_superior = contenido[:inicio_malcolm]
    bloque_malcolm = contenido[inicio_malcolm:fin_malcolm]
    parte_inferior = contenido[fin_malcolm:]

    # 4. Expresión regular ajustada que respeta saltos y valores previos
    patron = re.compile(r'("imagen":\s*".*?",)(\n[ \t]*)("streamUrl":)')
    
    # 5. Aplicar el reemplazo SOLO al bloque de Malcolm
    bloque_malcolm_modificado = patron.sub(r'\1\2"time_next_episode": 1.19,\2\3', bloque_malcolm)

    # 6. Unir todo de nuevo en su formato original
    nuevo_contenido = parte_superior + bloque_malcolm_modificado + parte_inferior

    # 7. Sobreescribir el archivo
    with open(ruta_archivo, 'w', encoding='utf-8') as f:
        f.write(nuevo_contenido)
        
    print("¡Listo! El archivo 'datos.json' ha sido actualizado SOLO en los episodios de Malcolm.")

actualizar_json_solo_malcolm()