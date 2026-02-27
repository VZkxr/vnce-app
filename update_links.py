import json
import re
import os
from urllib.parse import urlparse, urlunparse

def sobrescribir_urls_con_formato(nombre_archivo, nueva_url_base):
    # 1. Verificar existencia
    if not os.path.exists(nombre_archivo):
        print(f"Error: No se encuentra '{nombre_archivo}'")
        return

    print(f"Leyendo {nombre_archivo}...")
    with open(nombre_archivo, 'r', encoding='utf-8') as f:
        datos = json.load(f)

    # 2. Preparar URL base
    nueva_url_base = nueva_url_base.rstrip('/')
    parsed_new = urlparse(nueva_url_base)
    
    contador = 0

    # Función auxiliar para reconstruir la URL
    def construir_nueva_url(url_vieja, parsed_base):
        parsed_old = urlparse(url_vieja)
        return urlunparse((
            parsed_base.scheme,
            parsed_base.netloc,
            parsed_old.path,
            parsed_old.params,
            parsed_old.query,
            parsed_old.fragment
        ))

    # 3. Modificar datos en memoria
    for item in datos:
        
        # --- NIVEL PELÍCULA (Raíz) ---
        
        # Actualizar streamUrl principal
        if 'streamUrl' in item and item['streamUrl']:
            nueva_url = construir_nueva_url(item['streamUrl'], parsed_new)
            if item['streamUrl'] != nueva_url:
                item['streamUrl'] = nueva_url
                contador += 1
        
        # Actualizar subtítulos de la película
        if 'subtitulos' in item and isinstance(item['subtitulos'], list):
            for sub in item['subtitulos']:
                if 'url' in sub and sub['url']:
                    nueva_sub_url = construir_nueva_url(sub['url'], parsed_new)
                    if sub['url'] != nueva_sub_url:
                        sub['url'] = nueva_sub_url
                        contador += 1

        # --- NIVEL SERIE (Temporadas -> Episodios) ---
        
        if 'temporadas' in item and isinstance(item['temporadas'], list):
            for temporada in item['temporadas']:
                if 'episodios' in temporada and isinstance(temporada['episodios'], list):
                    for episodio in temporada['episodios']:
                        
                        # Actualizar streamUrl del episodio
                        if 'streamUrl' in episodio and episodio['streamUrl']:
                            nueva_url = construir_nueva_url(episodio['streamUrl'], parsed_new)
                            if episodio['streamUrl'] != nueva_url:
                                episodio['streamUrl'] = nueva_url
                                contador += 1
                        
                        # Actualizar subtítulos del episodio
                        if 'subtitulos' in episodio and isinstance(episodio['subtitulos'], list):
                            for sub in episodio['subtitulos']:
                                if 'url' in sub and sub['url']:
                                    nueva_sub_url = construir_nueva_url(sub['url'], parsed_new)
                                    if sub['url'] != nueva_sub_url:
                                        sub['url'] = nueva_sub_url
                                        contador += 1

    # 4. Convertir a Texto con indentación estándar primero
    json_str = json.dumps(datos, ensure_ascii=False, indent=4)

    # --- TRUCO DE FORMATO ---
    # Compactar arrays simples (genero, elenco) pero NO los arrays de objetos (subtitulos, temporadas)
    
    def compactar_array(match):
        contenido = match.group(0)
        # Si hay llaves '{' dentro, es un array de objetos (como subtitulos), NO lo compactamos
        if "{" in contenido: 
            return contenido
        # Si es simple, colapsar espacios y saltos de línea
        return re.sub(r'\s+', ' ', contenido)

    json_str = re.sub(r'\[\s*([^\[\]\{\}]*?)\s*\]', compactar_array, json_str, flags=re.DOTALL)

    # 5. Sobrescribir el archivo
    with open(nombre_archivo, 'w', encoding='utf-8') as f:
        f.write(json_str)

    print(f"Listo. Se ha sobrescrito '{nombre_archivo}' manteniendo el formato compacto.")
    print(f"Total de enlaces actualizados (Streams + Subs): {contador}")

# --- EJECUCIÓN ---
if __name__ == "__main__":
    ARCHIVO = 'datos.json' # Asegúrate de que este sea el nombre correcto
    
    nueva_input = input("Introduce la nueva URL base: ")
    sobrescribir_urls_con_formato(ARCHIVO, nueva_input)