import json
import requests
import os
import re

# Tu API Key
API_KEY = "d17af68828b64225260e4828503f98f9"
FILE_NAME = "datos.json"

def get_titled_backdrop_url(tmdb_id, media_type):
    """
    Busca un backdrop que contenga texto (título), priorizando español e inglés.
    """
    base_url = "https://api.themoviedb.org/3"
    # Consultamos el endpoint de imágenes pidiendo idiomas es, en y null
    endpoint = f"{base_url}/{media_type}/{tmdb_id}/images?api_key={API_KEY}&include_image_language=es,en,null"
    
    try:
        response = requests.get(endpoint)
        if response.status_code == 200:
            data = response.json()
            backdrops = data.get("backdrops", [])
            
            if not backdrops:
                return None

            # 1. Intentar encontrar uno en Español (alto chance de tener título en español)
            for img in backdrops:
                if img.get("iso_639_1") == "es":
                    return f"https://image.tmdb.org/t/p/w780{img['file_path']}"
            
            # 2. Intentar encontrar uno en Inglés (alto chance de tener título original)
            for img in backdrops:
                if img.get("iso_639_1") == "en":
                    return f"https://image.tmdb.org/t/p/w780{img['file_path']}"
            
            # 3. Si no hay con idioma específico, tomamos el más votado (el primero de la lista)
            # Aunque este suele ser "textless", es mejor que nada.
            if backdrops:
                 return f"https://image.tmdb.org/t/p/w780{backdrops[0]['file_path']}"

    except Exception as e:
        print(f"Error obteniendo imagen para ID {tmdb_id}: {e}")
    
    return None

def compact_json_lists(json_str):
    """
    Mantiene el formato compacto (una sola línea) para géneros y elenco.
    """
    def replacer(match):
        content = match.group(0)
        compacted = re.sub(r'\s*\n\s*', ' ', content)
        compacted = re.sub(r'\[\s+', '[', compacted)
        compacted = re.sub(r'\s+\]', ']', compacted)
        return compacted

    json_str = re.sub(r'"genero":\s*\[[^\]]*\]', replacer, json_str)
    json_str = re.sub(r'"elenco":\s*\[[^\]]*\]', replacer, json_str)
    return json_str

def main():
    if not os.path.exists(FILE_NAME):
        print(f"No se encontró el archivo {FILE_NAME}")
        return

    print("Leyendo archivo datos.json...")
    with open(FILE_NAME, 'r', encoding='utf-8') as f:
        data = json.load(f)

    updated_count = 0
    total = len(data)

    print(f"Procesando {total} elementos buscando imágenes con título...")

    for index, item in enumerate(data):
        tmdb_id = item.get("tmdbId")
        tipo_str = item.get("tipo")
        titulo = item.get("titulo", "Desconocido")
        
        media_type = "movie" if tipo_str == "Película" else "tv"

        if tmdb_id:
            # Llamamos a la nueva función de búsqueda
            new_image_url = get_titled_backdrop_url(tmdb_id, media_type)
            
            # Si encontramos algo diferente al backdrop actual, genial.
            # Si no, usamos el backdrop normal como fallback dentro de la lógica.
            final_url = new_image_url if new_image_url else item.get("backdrop")

            # Reconstruimos el diccionario para mantener el orden
            new_item = {}
            for key, value in item.items():
                new_item[key] = value
                if key == "backdrop":
                    # Insertamos continue_watching
                    new_item["continue_watching"] = final_url
            
            data[index] = new_item
            updated_count += 1
            
            # Feedback visual simple en consola
            estado = "Con Título (ES/EN)" if new_image_url else "Default (Sin texto)"
            print(f"[{index+1}/{total}] {titulo[:20]}... -> {estado}")

    print(f"\nGuardando cambios en {FILE_NAME}...")
    
    json_output = json.dumps(data, indent=4, ensure_ascii=False)
    final_json = compact_json_lists(json_output)

    with open(FILE_NAME, 'w', encoding='utf-8') as f:
        f.write(final_json)

    print("¡Listo! Imágenes actualizadas.")

if __name__ == "__main__":
    main()