import json
import requests
import re
import os

# --- CONFIGURACIÓN ---
API_KEY = "d17af68828b64225260e4828503f98f9"
FILE_PATH = "datos.json"
IMG_BASE_URL = "https://media.themoviedb.org/t/p/w227_and_h127_face"

# --- UTILIDADES ---

def limpiar_ruta_arrastrada(ruta_raw):
    """Limpia la basura que agrega PowerShell al arrastrar archivos."""
    if not ruta_raw: return ""
    ruta = ruta_raw.strip()
    if ruta.startswith("&"): ruta = ruta[1:].strip()
    return ruta.strip("'").strip('"')

def limpiar_para_url(texto):
    """
    Aplica las reglas estrictas para la URL:
    1. Elimina puntos (.) -> T1.E1 queda T1E1
    2. Reemplaza ñ por n -> Vccñs queda Vccns
    """
    if not texto: return ""
    
    # Reemplazo de caracteres específicos
    texto_limpio = texto.replace(".", "")
    texto_limpio = texto_limpio.replace("ñ", "n").replace("Ñ", "N")
    
    return texto_limpio

def obtener_id_desde_input(input_str):
    match = re.search(r'/tv/(\d+)', input_str)
    if match: return int(match.group(1))
    if input_str.isdigit(): return int(input_str)
    return None

def get_json_data(url):
    try:
        response = requests.get(url)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        return None

def get_tmdb_data_con_fallback(endpoint):
    """
    Intenta obtener datos en Español (es-MX). 
    Si la sinopsis está vacía, intenta obtenerlos en Inglés (en-US).
    """
    url_es = f"https://api.themoviedb.org/3/{endpoint}?api_key={API_KEY}&language=es-MX"
    data = get_json_data(url_es)
    
    sinopsis_vacia = False
    if data:
        overview = data.get('overview')
        if overview is None or overview == "":
            sinopsis_vacia = True
            
    if not data or sinopsis_vacia:
        print("   (Datos en español incompletos, intentando en inglés...)")
        url_en = f"https://api.themoviedb.org/3/{endpoint}?api_key={API_KEY}&language=en-US"
        data_en = get_json_data(url_en)
        if data_en: return data_en
            
    return data

def cargar_mapa_nombres_txt(ruta_txt):
    mapa = {}
    if not ruta_txt or not os.path.exists(ruta_txt): return mapa

    print(f"📂 Leyendo nombres de archivos desde: {ruta_txt}")
    try:
        with open(ruta_txt, 'r', encoding='utf-8') as f:
            lineas = f.readlines()
        patron_detectar = r'[Tt](\d+)[\s\.]*[Ee](\d+)' 
        for linea in lineas:
            nombre_clean = linea.strip()
            if not nombre_clean: continue
            match = re.search(patron_detectar, nombre_clean)
            if match:
                s_num = int(match.group(1))
                e_num = int(match.group(2))
                mapa[(s_num, e_num)] = nombre_clean
    except Exception as e:
        print(f"⚠️ Error leyendo el archivo TXT: {e}")
    return mapa

def buscar_temporada_local(numero, temporadas_existentes):
    if not temporadas_existentes: return None
    for temp in temporadas_existentes:
        if temp.get("numero") == numero:
            return temp
    return None

def gener_label_idioma(lang_code):
    mapa = {
        "es": "Español",
        "en": "Inglés",
        "ko": "Coreano",
        "pt": "Portugués",
        "fr": "Francés",
        "it": "Italiano",
        "de": "Alemán",
        "ru": "Ruso",
        "ja": "Japonés",
        "hi": "Hindi"
    }
    return mapa.get(lang_code, lang_code.upper())

def generar_estructura_subtitulos(stream_url, lista_idiomas, lista_forced):
    """
    Genera la lista de subtítulos basada en la carpeta del stream y las listas de idiomas.
    lista_idiomas: ej. ['es', 'en', 'ko']
    lista_forced: ej. ['es']
    """
    if not stream_url: return None
    
    # Quitamos 'master.m3u8' para obtener la carpeta base
    base_folder = stream_url.rsplit('/', 1)[0]
    
    lista_subs = []

    # Para cada idioma solicitado
    for lang in lista_idiomas:
        # Modificación: Solo permitir español (completos y forzados)
        if lang != "es": continue

        label_base = gener_label_idioma(lang)
        
        # 1. Checar si este idioma lleva forzados
        if lang in lista_forced:
            lista_subs.append({
                "label": f"{label_base} (Forzados)",
                "lang": f"{lang}-forced",
                "url": f"{base_folder}/subs_{lang}_forced.vtt",
                "default": True
            })
            # El normal pasa a default=False si hay forzado
            is_default = False
        else:
            # Si no hay forzado para este idioma, ¿es el primero de la lista global?
            # Asumiremos que el primer idioma de la lista es el default si no hay forzados globales.
            # Ojo: la logica original ponía default=False a todo menos al forzado español.
            is_default = False 
            
        # 2. Agregar el subtítulo normal
        lista_subs.append({
            "label": label_base,
            "lang": lang,
            "url": f"{base_folder}/subs_{lang}.vtt",
            "default": is_default
        })
    
    return lista_subs

def obtener_datos_temporadas(tmdb_id, ruta_base_srv, mapa_archivos_txt, incluir_subs, target_langs, target_forced, temporadas_existentes=None, temporada_target=None):
    endpoint_serie = f"tv/{tmdb_id}"
    detalles_serie = get_tmdb_data_con_fallback(endpoint_serie)
    
    if not detalles_serie: 
        print("Error: No se pudo conectar con TMDB.")
        return None

    lista_temporadas_nuevas = []
    print(f"Serie encontrada: {detalles_serie.get('name')}")
    
    seasons_list = detalles_serie.get("seasons", [])
    generar_urls = (ruta_base_srv is not None and ruta_base_srv != "")
    
    for season in seasons_list:
        season_num = season.get("season_number")
        if season_num == 0: continue 
        
        if temporada_target is not None and season_num != temporada_target:
            temp_antigua = buscar_temporada_local(season_num, temporadas_existentes)
            if temp_antigua:
                lista_temporadas_nuevas.append(temp_antigua)
            continue
        
        print(f"  -> Procesando Temporada {season_num}...")
        
        endpoint_season = f"tv/{tmdb_id}/season/{season_num}"
        data_season = get_tmdb_data_con_fallback(endpoint_season)
        if not data_season: continue

        episodios_procesados = []
        for ep in data_season.get("episodes", []):
            ep_num = ep.get("episode_number")
            
            #LÓGICA DE URL
            stream_url = None
            
            #Generación nueva con limpieza
            if generar_urls and mapa_archivos_txt:
                nombre_archivo_raw = mapa_archivos_txt.get((season_num, ep_num))
                
                if nombre_archivo_raw:
                    #LIMPIEZA (T1.E1 -> T1E1, ñ -> n)
                    nombre_carpeta_final = limpiar_para_url(nombre_archivo_raw)
                    
                    # Construimos ruta
                    nombre_m3u8 = "master.m3u8"
                    if not incluir_subs:
                        nombre_m3u8 = f"{nombre_carpeta_final}.m3u8"
                    
                    url_temp = f"{ruta_base_srv}/T{season_num}/{nombre_carpeta_final}/{nombre_m3u8}"
                    stream_url = url_temp.replace("//", "/")
            
            # 2. Si no se generó nueva, intentamos recuperar la vieja
            if not stream_url and temporadas_existentes:
                temp_local = buscar_temporada_local(season_num, temporadas_existentes)
                if temp_local:
                    for ep_loc in temp_local.get("episodios", []):
                        if ep_loc.get("episodio") == ep_num:
                            stream_url = ep_loc.get("streamUrl")
                            break
            # ---------------------

            # --- LÓGICA DE SUBTÍTULOS ---
            subs_data = None
            if incluir_subs and stream_url:
                subs_data = generar_estructura_subtitulos(stream_url, target_langs, target_forced)
            # ----------------------------

            imagen_path = ep.get("still_path")
            
            ep_obj = {
                "episodio": ep_num,
                "titulo": ep.get("name"),
                "sinopsis": ep.get("overview", ""),
                "duracion": f"{ep.get('runtime')} min" if ep.get("runtime") else "N/A",
                "imagen": f"{IMG_BASE_URL}{imagen_path}" if imagen_path else None,
                "streamUrl": stream_url
            }

            if subs_data:
                ep_obj["subtitulos"] = subs_data
            
            episodios_procesados.append(ep_obj)
            
        lista_temporadas_nuevas.append({
            "numero": season_num,
            "nombre": season.get("name"),
            "episodios": episodios_procesados
        })
    
    lista_temporadas_nuevas.sort(key=lambda x: x["numero"])
    return lista_temporadas_nuevas

def reordenar_item(item, nuevas_temporadas):
    nuevo_item = {}
    llaves = list(item.keys())
    if "sinopsis" not in llaves: pass
    ya_insertado = False
    for k in llaves:
        if k == "temporadas": continue
        nuevo_item[k] = item[k]
        if k == "sinopsis":
            nuevo_item["temporadas"] = nuevas_temporadas
            ya_insertado = True
    if not ya_insertado: nuevo_item["temporadas"] = nuevas_temporadas
    return nuevo_item

def formatear_compacto(json_str):
    return re.sub(r'\[\s+((?:"[^"]+"\s*,\s*)+"[^"]+")\s+\]', lambda m: '[' + re.sub(r'\s+', ' ', m.group(1)) + ']', json_str)

def main():
    if not os.path.exists(FILE_PATH):
        print(f"Error: No se encuentra {FILE_PATH}")
        return

    with open(FILE_PATH, 'r', encoding='utf-8') as f:
        try: db_data = json.load(f)
        except json.JSONDecodeError: return

    # 1. ID SERIE
    user_input = input("Serie para actualizar (URL o ID): ").strip()
    tmdb_id = obtener_id_desde_input(user_input)
    if not tmdb_id: return

    # 2. AUDIO Y SUBTÍTULOS
    print("\n¿Agregar audio y subtítulo a la serie?")
    print("1. Si")
    print("2. No")
    opc_subs = input("Selecciona (1 o 2): ").strip()
    incluir_subs = (opc_subs == "1")
    
    target_langs = []
    target_forced = []

    if incluir_subs:
        print("\n--- CONFIGURACIÓN DE IDIOMAS ---")
        print("Ejemplo: es,en,ko")
        langs_input = input("Idiomas a incluir (separados por coma): ").strip()
        if langs_input:
            target_langs = [l.strip() for l in langs_input.split(",") if l.strip()]
        
        print("\nEjemplo: es (esto agregará subs_es_forced.vtt)")
        forced_input = input("Idiomas con forzados (separados por coma, opcional): ").strip()
        if forced_input:
            target_forced = [l.strip() for l in forced_input.split(",") if l.strip()]

    # 3. RUTA BASE
    print("\n--- CONFIGURACIÓN DE URLS ---")
    print(" - Escribe la ruta (ej: /series/DR-(1997)) para generar URLs nuevas.")
    print(" - Escribe 'SALTAR' (o deja vacío) para solo actualizar metadatos.")
    
    ruta_base_raw = input("Ruta base: ")
    ruta_base = limpiar_ruta_arrastrada(ruta_base_raw)
    
    modo_skip_urls = False
    if not ruta_base or ruta_base.upper() == "SALTAR":
        modo_skip_urls = True
        ruta_base = None
        print(">> MODO: Solo actualizar metadatos.")
    else:
        if ruta_base.endswith("/"): ruta_base = ruta_base[:-1]

    # 4. ARCHIVO TXT
    mapa_archivos = {}
    if not modo_skip_urls:
        print("\nArrastra aquí el archivo .txt generado por names_hls.py")
        print("(O presiona Enter si se llama 'nombres_hls.txt' y está aquí)")
        
        ruta_txt_input = input("Archivo TXT: ")
        ruta_txt = limpiar_ruta_arrastrada(ruta_txt_input)
        
        if not ruta_txt: ruta_txt = "nombres_hls.txt"
        mapa_archivos = cargar_mapa_nombres_txt(ruta_txt)

    # 5. OPERACIÓN
    print("\nOperación:")
    print("1. Agregar/Actualizar todas las temporadas")
    print("2. Una temporada específica")
    opcion = input("Opción (1/2): ").strip()

    target = None
    if opcion == "2":
        t = input("Nº Temporada: ").strip()
        if t.isdigit(): target = int(t)
    
    # PROCESO
    idx = -1
    for i, item in enumerate(db_data):
        if item.get("tmdbId") == tmdb_id:
            idx = i
            break
    
    if idx == -1:
        print("Serie no encontrada en JSON local.")
        return

    item_actual = db_data[idx]
    temp_viejas = item_actual.get("temporadas", [])
    
    # Pasamos las nuevas configuraciones a la lógica principal
    temp_nuevas = obtener_datos_temporadas(
        tmdb_id, 
        ruta_base, 
        mapa_archivos, 
        incluir_subs, 
        target_langs,
        target_forced,
        temp_viejas, 
        target
    )
    
    if temp_nuevas:
        db_data[idx] = reordenar_item(item_actual, temp_nuevas)
        print("Guardando...")
        with open(FILE_PATH, 'w', encoding='utf-8') as f:
            f.write(formatear_compacto(json.dumps(db_data, ensure_ascii=False, indent=4)))
        print("¡Listo! Base de datos actualizada correctamente.")
    else:
        print("Sin cambios.")

if __name__ == "__main__":
    main()