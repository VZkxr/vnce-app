import requests
import re
import json
import os

API_KEY = "d17af68828b64225260e4828503f98f9"
BASE_URL = "https://api.themoviedb.org/3"
ARCHIVO_JSON = "datos.json"

# === Funciones base  ===

def obtener_id_y_tipo(entrada):
    entrada = entrada.strip()
    if entrada.isdigit():
        return int(entrada), "movie"
    match = re.search(r"themoviedb\.org/(movie|tv)/(\d+)", entrada)
    if match:
        tipo = match.group(1)
        id_obra = int(match.group(2))
        return id_obra, tipo
    return entrada, "movie"

def buscar_obra(nombre, tipo):
    url = f"{BASE_URL}/search/{tipo}?api_key={API_KEY}&language=es-MX&query={nombre}"
    r = requests.get(url).json()
    if not r.get("results"):
        print("❌ No se encontró la obra.")
        return None
    return r["results"][0]

def obtener_detalles(id_obra, tipo):
    url = f"{BASE_URL}/{tipo}/{id_obra}?api_key={API_KEY}&language=es-MX&append_to_response=credits,images&include_image_language=es,null"
    return requests.get(url).json()

# === Función de generación ===

def generar_bloque_json(datos, tipo):
    """
    Genera el bloque JSON con las reglas de negocio solicitadas:
    1. Estructura y orden específicos.
    2. continue_watching con imagen horizontal (mejor backdrops en español).
    3. enlaceTelegram en null.
    4. post-play_experience en 1.0.
    """
    
    # ID 
    tmdb_id = datos.get("id")

    # --- LÓGICA DE FORMATOS, FECHAS Y DIRECTOR ---
    director = "Desconocido"
    
    if tipo == "movie":
        titulo = datos.get("title", "Desconocido")
        duracion = f"{datos.get('runtime', 0)} min"
        fecha = datos.get("release_date", "Desconocida")
        tipo_formato = "Película"
        
        # Obtener director para películas
        crew = datos.get("credits", {}).get("crew", [])
        directores = [member["name"] for member in crew if member.get("job") == "Director"]
        if directores:
            director = ", ".join(directores)
            
    else: # Serie
        titulo = datos.get("name", "Desconocido")
        temporadas = datos.get("number_of_seasons", 0)
        episodios = datos.get("number_of_episodes", 0)
        fecha = datos.get("first_air_date", "Desconocida")
        tipo_formato = "Serie"
        if temporadas == 1:
            duracion = f"{episodios} episodios"
        else:
            duracion = f"{temporadas} temporadas"

        # Obtener creadores para series
        creadores = datos.get("created_by", [])
        if creadores:
            director = ", ".join([c["name"] for c in creadores])

    sinopsis = datos.get("overview", "")
    
    # --- LÓGICA DE GÉNEROS ---
    generos_raw = [g["name"] for g in datos.get("genres", [])]
    
    if "Animación" in generos_raw:
        permitidos = ["Animación", "Aventura", "Familia"]
        generos = [g for g in generos_raw if g in permitidos]
        if "Animación" not in generos: 
            generos.insert(0, "Animación")
    else:
        generos = generos_raw

    # --- CALIFICACIÓN ---
    calificacion = round(datos.get("vote_average", 0), 1)
    
    # --- ELENCO ---
    elenco = [actor["name"] for actor in datos.get("credits", {}).get("cast", [])[:5]]
    
    # --- IMÁGENES ---
    base_img_original = "https://image.tmdb.org/t/p/original"
    base_img_w780 = "https://image.tmdb.org/t/p/w780"
    
    poster_path = datos.get("poster_path")
    portada = base_img_original + poster_path if poster_path else ""
    
    backdrop_path = datos.get("backdrop_path")
    backdrop = base_img_original + backdrop_path if backdrop_path else "" 
    
    # Logic for continue_watching (Backdrop con título en español preferentemente, o fallback)
    continue_watching_path = backdrop_path # Fallback por defecto
    
    backdrops = datos.get("images", {}).get("backdrops", [])
    
    # Buscar backdrop en español
    backdrops_es = [b for b in backdrops if b.get("iso_639_1") == "es"]
    
    if backdrops_es:
        # Tomar el mejor puntúado en español
        continue_watching_path = backdrops_es[0].get("file_path")
    elif backdrops:
         # Si no hay español, intentar buscar uno con 'null' (sin texto) o 'en'
         # o simplemente dejar el backdrop principal (que tmdb ya seleccionó como mejor)
         pass

    continue_watching = base_img_w780 + continue_watching_path if continue_watching_path else ""

    enlace_telegram = None
    post_play_experience = 1.0

    # --- CONSTRUCCIÓN DEL STRING JSON ---
    
    tmdb_id_json = json.dumps(tmdb_id)
    titulo_json = json.dumps(titulo, ensure_ascii=False)
    tipo_json = json.dumps(tipo_formato, ensure_ascii=False)
    sinopsis_json = json.dumps(sinopsis, ensure_ascii=False)
    generos_json = json.dumps(generos, ensure_ascii=False) 
    calificacion_json = json.dumps(calificacion)
    duracion_json = json.dumps(duracion, ensure_ascii=False)
    director_json = json.dumps(director, ensure_ascii=False)
    elenco_json = json.dumps(elenco, ensure_ascii=False)
    portada_json = json.dumps(portada, ensure_ascii=False)
    backdrop_json = json.dumps(backdrop, ensure_ascii=False)
    continue_watching_json = json.dumps(continue_watching, ensure_ascii=False)
    enlace_json = json.dumps(enlace_telegram) # null
    post_play_json = json.dumps(post_play_experience)
    fecha_json = json.dumps(fecha, ensure_ascii=False)

    # Armamos la lista respetando el orden solicitado
    partes_json = [
        "    {", 
        f'        "tmdbId": {tmdb_id_json},',
        '        "premium": true,',
        f'        "titulo": {titulo_json},',
        f'        "tipo": {tipo_json},',
        f'        "sinopsis": {sinopsis_json},',
        f'        "genero": {generos_json},',
        f'        "calificacion": {calificacion_json},',
        f'        "duracion": {duracion_json},',
        f'        "director": {director_json},',
        f'        "elenco": {elenco_json},',
        f'        "portada": {portada_json},',
        f'        "backdrop": {backdrop_json},',
        f'        "continue_watching": {continue_watching_json},',
        f'        "enlaceTelegram": {enlace_json},',
        f'        "post-play_experience": {post_play_json},',
        f'        "fecha": {fecha_json}',
        "    }" 
    ]
    
    return "\n".join(partes_json)

# === Función para Guardar en datos.json (Sin cambios) ===

def guardar_en_archivo_existente(nuevos_bloques_str):
    if not os.path.exists(ARCHIVO_JSON):
        with open(ARCHIVO_JSON, "w", encoding="utf-8") as f:
            f.write("[\n")
            f.write(",\n".join(nuevos_bloques_str))
            f.write("\n]")
        print(f"✅ Archivo '{ARCHIVO_JSON}' creado con los nuevos datos.")
        return

    with open(ARCHIVO_JSON, "r+", encoding="utf-8") as f:
        contenido = f.read().strip()
        indice_cierre = contenido.rfind("]")
        
        if indice_cierre != -1:
            f.seek(0)
            contenido_previo = contenido[:indice_cierre].strip()
            f.write(contenido_previo)
            
            if len(contenido_previo) > 1:
                f.write(",\n")
            else:
                f.write("\n")
            
            f.write(",\n".join(nuevos_bloques_str))
            f.write("\n]")
            f.truncate()
            print(f"✅ Datos agregados correctamente a '{ARCHIVO_JSON}'.")
        else:
            print(f"⚠️ Error: '{ARCHIVO_JSON}' no tiene un formato JSON válido (falta ']').")

# === Función principal ===

def procesar_entrada(entrada):
    if entrada.endswith(".txt") and os.path.exists(entrada):
        with open(entrada, "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()], True
    else:
        return [entrada.strip()], False

if __name__ == "__main__":
    print(f"📂 Trabajando sobre: {ARCHIVO_JSON}")
    entrada = input("🎬 Ingresa la URL o el nombre del archivo .txt: ").strip()
    entradas, es_archivo = procesar_entrada(entrada)

    bloques = []

    for url in entradas:
        id_o_nombre, tipo = obtener_id_y_tipo(url)
        detalles = None

        if isinstance(id_o_nombre, int):
            print(f"🔍 Extrayendo datos de {tipo.upper()} con ID {id_o_nombre}...")
            detalles = obtener_detalles(id_o_nombre, tipo)
        else:
            resultado = buscar_obra(id_o_nombre, tipo)
            if resultado:
                print(f"🔍 Buscando detalles de {resultado.get('title') or resultado.get('name')}...")
                detalles = obtener_detalles(resultado["id"], tipo)
            else:
                print(f"❌ No se encontró: {id_o_nombre}")

        if detalles:
            bloque_str = generar_bloque_json(detalles, tipo)
            bloques.append(bloque_str)

    if bloques:
        guardar_en_archivo_existente(bloques)
    else:
        print("⚠️ No se generaron bloques para guardar.")