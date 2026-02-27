import os
import sys
import json
import subprocess
import re
import shutil
from pathlib import Path

# === CONFIGURACIÓN ===
FALLBACK_AUDIO_CODEC = "aac"
FALLBACK_BITRATE = "192k"
FALLBACK_CHANNELS = 2  # Forzamos estéreo para compatibilidad web
# =====================

class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'

def sanitize_filename(name):
    """Limpia el nombre del archivo para evitar caracteres problemáticos."""
    if not name: return "Untitled"
    # Reemplazo básico, se puede mejorar con unicodedata si es necesario
    clean_name = re.sub(r'[^a-zA-Z0-9_\-]', '', name.replace(' ', '_'))
    return clean_name

def get_stream_info(input_file):
    """Obtiene la información de los streams usando ffprobe."""
    cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_streams", "-show_format", input_file
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, encoding='utf-8')
        return json.loads(result.stdout)
    except Exception as e:
        print(f"{Colors.FAIL}Error al analizar el archivo: {e}{Colors.ENDC}")
        return None

def extract_subtitles(input_file, output_dir, streams):
    """Extrae subtítulos a formato VTT con nombres estandarizados."""
    subs_map = []
    print(f"\n{Colors.HEADER}[1/4] Extrayendo Subtítulos...{Colors.ENDC}")
    
    sub_streams = [s for s in streams if s['codec_type'] == 'subtitle']
    
    # Contadores para evitar colisiones
    count_lang = {} 

    for s in sub_streams:
        idx = s['index']
        tags = s.get('tags', {})
        lang = tags.get('language', 'und').lower()
        title = tags.get('title', '')
        # Filtering logic for SDH/CC
        title_lower = title.lower()
        if 'sdh' in title_lower or 'cc' in title_lower:
            print(f"  -> Saltando track {idx} ({lang}): Detectado SDH/CC en título '{title}'")
            continue

        # Skip French subtitles as per request
        if lang in ['fra', 'fre', 'fr']:
            print(f"  -> Saltando track {idx} ({lang}): Subtítulos en Francés omitidos por configuración.")
            continue
            
        forced = s.get('disposition', {}).get('forced', 0) == 1
        
        # Normalizar lenguaje
        filesafe_lang = lang
        label_lang = lang.capitalize()
        
        if lang in ['spa', 'es', 'lat']:
            filesafe_lang = 'es'
            label_lang = 'Español'
        elif lang in ['eng', 'en']:
            filesafe_lang = 'en'
            label_lang = 'Inglés'
        elif lang in ['kor', 'ko']:
            filesafe_lang = 'ko'
            label_lang = 'Coreano'
        elif lang in ['jpn', 'ja']:
            filesafe_lang = 'ja'
            label_lang = 'Japonés'
            
        # Construir sufijos y labels
        suffix = ""
        label_suffix = ""
        
        if forced:
            suffix = "_forced"
            label_suffix = " (Forzados)"
        
        # Base name
        base_name = f"subs_{filesafe_lang}{suffix}"
        
        # Manejo de duplicados (e.g. dos tracks de Español normales)
        if base_name in count_lang:
            count_lang[base_name] += 1
            final_filename = f"{base_name}_{count_lang[base_name]}.vtt"
        else:
            count_lang[base_name] = 1
            final_filename = f"{base_name}.vtt"
            
        output_path = output_dir / final_filename
        
        final_label = f"{label_lang}{label_suffix}"
        
        # 1. Extraer VTT Raw (Para compatibilidad con datos.json y Plyr sidecar)
        print(f"  -> Extrayendo track {idx} ({lang}) a VTT: {final_filename}")
        
        cmd_vtt = [
            "ffmpeg", "-y", "-v", "error", 
            "-i", str(input_file), 
            "-map", f"0:{idx}", 
            "-f", "webvtt", 
            str(output_dir / final_filename)
        ]
        
        try:
            subprocess.run(cmd_vtt, check=True)
        except subprocess.CalledProcessError:
            print(f"     {Colors.FAIL}Error extrayendo VTT {lang}{Colors.ENDC}")
            continue

        # SOLO extraemos el VTT. NO lo agregamos al subs_map.
        # ¿Por qué?
        # 1. Si lo agregamos como URI="file.vtt", Hls.js falla ("Missing format identifier").
        # 2. Si intentamos convertir a Playlist HLS (segmentado), ffmpeg suele fallar con codecs de texto.
        # 3. El reproductor web (Plyr) ya carga los subtítulos desde 'datos.json', así que no necesitamos
        #    que estén dentro del master.m3u8. Esto mantiene el log limpio y el HLS compatible.
        
    return [] # Retornamos lista vacía para no ensuciar el master.m3u8

def convert_to_mp4(input_file, output_mp4, streams):
    """Convierte el MKV a MP4, copiando video y convirtiendo audio a AAC 2.0 si es necesario."""
    print(f"\n{Colors.HEADER}[2/4] Creando MP4 Intermedio (Video Copy + Audio AAC 2.0)...{Colors.ENDC}")
    
    # Identificar stream de video
    video_streams = [s for s in streams if s['codec_type'] == 'video']
    if not video_streams:
        print(f"{Colors.FAIL}No se encontró stream de video.{Colors.ENDC}")
        return None
        
    video_codec = video_streams[0].get('codec_name', 'unknown')
    print(f"  -> Codec de video detectado: {video_codec}")

    # Construir comando
    cmd = ["ffmpeg", "-y", "-v", "info", "-stats", "-i", str(input_file)]
    
    # Video: Copy (Revertido transcode a request del usuario)
    print(f"     {Colors.GREEN}Copiando video ({video_codec})...{Colors.ENDC}")
    cmd.extend(["-map", "0:v:0", "-c:v", "copy"])
    
    # Procesar audios
    audio_streams = [s for s in streams if s['codec_type'] == 'audio']
    audio_maps = []
    
    for i, audio in enumerate(audio_streams):
        # Mapeamos cada audio
        idx = audio['index']
        channels = audio.get('channels', 2)
        codec = audio.get('codec_name', 'unknown')
        tags = audio.get('tags', {})
        lang = tags.get('language', 'und').lower()
        title = tags.get('title', '')
        
        print(f"  -> Procesando Audio #{i} (Index {idx}): {codec} / {channels}ch / {lang}")
        
        cmd.extend(["-map", f"0:{idx}"])
        
        # Si es > 2 canales o no es AAC, convertimos a AAC estéreo
        if channels > 2 or codec != 'aac':
            print(f"     {Colors.WARNING}Detectado {channels} canales o codec {codec}. Convirtiendo a AAC 2.0...{Colors.ENDC}")
            cmd.extend([
                f"-c:a:{i}", "aac", 
                f"-b:a:{i}", FALLBACK_BITRATE, 
                f"-ac:a:{i}", str(FALLBACK_CHANNELS)
            ])
        else:
            print(f"     {Colors.GREEN}Format OK (AAC 2.0). Copiando...{Colors.ENDC}")
            # Even if copy, we should enforce the mapping logic. 
            # If we copy, we can't change channels.
            cmd.extend([f"-c:a:{i}", "copy"])
            
        # Logic for naming
        safe_name = f"Audio_{i+1}"
        display_name = title or f"Audio {i+1}"
        
        if lang in ['spa', 'es', 'lat']:
            safe_name = "Espanol"
            display_name = "Español Latino"
        elif lang in ['eng', 'en']:
            safe_name = "Ingles"
            display_name = "Inglés"
        elif lang in ['kor', 'ko']:
            safe_name = "Koreano"
            display_name = "Coreano"
        elif lang in ['jpn', 'ja']:
            safe_name = "Japones"
            display_name = "Japonés"
        elif lang in ['fra', 'fre', 'fr']:
            safe_name = "Frances"
            display_name = "Francés"
        
        # Metadata para identificar tracks luego si fuera necesario, 
        # aunque el orden en el MP4 será 0=Video, 1=Audio0, 2=Audio1...
        audio_maps.append({
            'index_in_mp4': i, # 0-based index of audio tracks in new mp4
            'lang': lang,
            'name': safe_name,       # Used for filenames (var_stream_map)
            'label': display_name,   # Used for Master Playlist NAME
            'group_id': 'audio-group'
        })

    # Opciones de MP4 para streaming (movflags)
    cmd.extend(["-movflags", "+faststart", str(output_mp4)])
    
    try:
        subprocess.run(cmd, check=True)
        return audio_maps
    except subprocess.CalledProcessError:
        print(f"{Colors.FAIL}Error al convertir a MP4.{Colors.ENDC}")
        return None

def generate_hls(input_mp4, output_dir, safe_name, audio_maps, subs_maps, video_codec=None):
    """Genera el HLS segmentado a partir del MP4 intermedio."""
    print(f"\n{Colors.HEADER}[3/4] Generando HLS Segmentado...{Colors.ENDC}")
    
    var_stream_map = ""
    
    # Map video explicitly named '0' to match standard patterns (filename_0.m3u8)
    var_stream_map += "v:0,agroup:audio-group,name:0 "
    
    # Audio maps
    for i, aud in enumerate(audio_maps):
        # En el MP4, los audios son a:0, a:1, etc.
        # Definimos language y name para el manifesto
        # Usamos nombres seguros y simples para evitar problemas en URIs
        simple_name = sanitize_filename(aud['name'])
        if not simple_name: simple_name = f"Audio_{i}"
        
        lang = aud['lang']
        var_stream_map += f"a:{i},agroup:audio-group,language:{lang},name:{simple_name} "
    
    var_stream_map = var_stream_map.strip()
    
    # Segment naming: filename_name_...
    # Using %v in segment filename might be too verbose if names are long.
    # Let's stick to the user's working pattern if possible.
    # Avatar pattern: Avtr-2009_0.m3u8 (Video)
    #                 Avtr-2009_Espanol.m3u8 (Audio)
    
    # SWITCH TO MPEG-TS (Back to basics as requested)
    # Use RELATIVE paths for ffmpeg output to avoid absolute paths in m3u8
    segment_filename = f"{safe_name}_%v_data%03d.ts"
    master_pl_name = "master.m3u8"
    
    cmd = [
        "ffmpeg", "-y", "-v", "info", "-i", str(input_mp4),
        "-c", "copy", 
        "-map", "0:v:0"
    ]
    
    # HEVC Support: Even in TS, sometimes tagging helps, but usually standard TS is fine.
    # We will remove the explicit fmp4 forcing.
    
    # Map all audios
    for i in range(len(audio_maps)):
        cmd.extend(["-map", f"0:a:{i}"])
        
    cmd.extend([
        "-f", "hls",
        "-hls_time", "6",
        "-hls_playlist_type", "vod",
        "-hls_flags", "independent_segments",
        "-hls_segment_type", "mpegts", # Explicit MPEG-TS
        "-master_pl_name", master_pl_name,
        "-hls_segment_filename", segment_filename,
        # "-hls_fmp4_init_filename" REMOVED for TS
        "-var_stream_map", var_stream_map,
        f"{safe_name}_%v.m3u8"
    ])
    
    # Run in output_dir so relative paths work
    subprocess.run(cmd, check=True, cwd=output_dir)
    
    return output_dir / master_pl_name

def patch_master_with_subs(master_path, subs_maps, audio_maps):
    """Limpia y estructura correctamente el master.m3u8."""
    print(f"\n{Colors.HEADER}[4/4] Actualizando Master Playlist...{Colors.ENDC}")
    
    if not master_path.exists():
        return

    with open(master_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    new_lines = []
    
    # 1. Definir Subtítulos (EXT-X-MEDIA:TYPE=SUBTITLES)
    subs_lines = []
    for sub in subs_maps:
        lang = sub['lang']
        name = sub['name']
        forced = "YES" if sub.get('forced') else "NO"
        default = "YES" if sub.get('forced') else "NO"
        uri = sub['path']
        # Definimos subtítulos
        line = f'#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="{name}",DEFAULT={default},AUTOSELECT=YES,FORCED={forced},LANGUAGE="{lang}",URI="{uri}"\n'
        subs_lines.append(line)
        
    # Agregamos subs al inicio (después del header)
    header_processed = False
    
    # Track audio defaults to ensure only one YES
    audio_default_set = False
    
    # Filtrar líneas
    full_content = []
    for line in lines:
        line = line.strip()
        if not line: continue
        
        # Header handling
        if line.startswith("#EXTM3U") or line.startswith("#EXT-X-VERSION"):
            full_content.append(line)
            if line.startswith("#EXT-X-VERSION") and not header_processed:
                full_content.extend([s.strip() for s in subs_lines])
                header_processed = True
            continue
            
        # Audio Handling
        if line.startswith("#EXT-X-MEDIA:TYPE=AUDIO"):
            # Fix Channels
            if 'CHANNELS=' in line:
                line = re.sub(r'CHANNELS="[^"]+"', 'CHANNELS="2"', line)
            else:
                line += ',CHANNELS="2"'
            
            # Fix Default
            if "DEFAULT=YES" in line:
                if audio_default_set:
                    line = line.replace("DEFAULT=YES", "DEFAULT=NO")
                else:
                    audio_default_set = True
            
            # Ensure Autoselect
            if "AUTOSELECT" not in line: line += ",AUTOSELECT=YES"

            # Fix NAME using audio_maps
            # Matching strategy: The URI usually contains the safe name we generated.
            # e.g. URI="Movie_Espanol.m3u8"
            for aud in audio_maps:
                # Our generated URI suffix in generate_hls uses the safe name.
                # Check if safe name is in the line (URI or NAME)
                # ffmpeg puts the name in NAME="..." AND usually in the URI too if using var_stream_map correctly
                safe_n = aud['name']
                label = aud['label']
                
                # Check if this line corresponds to this audio track
                # simple check: if the URI contains the safe name
                # or if the current NAME (put by ffmpeg) matches safe name
                if f'NAME="{safe_n}"' in line or f'_{safe_n}.m3u8' in line:
                    line = re.sub(r'NAME="[^"]+"', f'NAME="{label}"', line)
                    break
            
            full_content.append(line)
            continue
            
        # Stream Inf Handling
        if line.startswith("#EXT-X-STREAM-INF"):
            # Identificar si es un stream de VIDEO o AUDIO-ONLY disfrazado
            # Los streams de video suelen tener CODECS="avc..." o resoluciones altas
            # Los streams de audio-only en var_stream_map a veces salen aquí
            
            # Si apunta a un playlist que sabemos que es de audio (por el nombre o mapa)
            # mejor lo quitamos si no es el video principal.
            # Mi script genera nombres: {safe_name}_0.m3u8 (Video), {safe_name}_Espanol.m3u8 (Audio)
            # Pero ffmpeg a veces usa nombres genericos.
            
            # Estrategia: Si CODECS tiene solo mp4a (audio), es un audio-only stream-inf.
            # Lo QUITAMOS para no confundir al player.
            is_audio_only = "mp4a" in line and "avc1" not in line and "hvc1" not in line
            
            if is_audio_only:
                # Skip this line AND the next line (the URI)
                # Hack: Marcamos para saltar la siguiente
                full_content.append("__SKIP_NEXT__")
                continue
                
            # Es Video: Añadir referencia a subs
            if 'SUBTITLES="subs"' not in line:
                line += ',SUBTITLES="subs"'
            full_content.append(line)
            continue
            
        # URI lines handling
        if line.endswith(".m3u8"):
            if full_content and full_content[-1] == "__SKIP_NEXT__":
                full_content.pop() # Remove marker
                continue
            full_content.append(line)
            continue
            
        full_content.append(line)

    # Reconstruir con saltos de línea
    with open(master_path, 'w', encoding='utf-8') as f:
        for l in full_content:
            f.write(l + "\n")

def process_video(input_path):
    input_path = Path(input_path).resolve()
    if not input_path.exists():
        print(f"Archivo no encontrado: {input_path}")
        return

    safe_name = sanitize_filename(input_path.stem)
    output_dir = input_path.parent / safe_name
    
    if output_dir.exists():
        print(f"Carpeta '{output_dir}' ya existe. Sobrescribiendo...")
        try:
            shutil.rmtree(output_dir)
        except Exception as e:
            print(f"Error borrando carpeta existente: {e}")
            return
    
    output_dir.mkdir()
    
    # 1. Analizar
    info = get_stream_info(input_path)
    if not info: return
    streams = info.get('streams', [])
    
    # Detectar codec de video
    video_codec = None
    for s in streams:
        if s['codec_type'] == 'video':
            video_codec = s.get('codec_name')
            break
    
    # 2. Extract Subs
    subs_maps = extract_subtitles(input_path, output_dir, streams)
    
    # 3. MP4 Intermedio
    mp4_path = output_dir / f"{safe_name}_intermediate.mp4"
    audio_maps = convert_to_mp4(input_path, mp4_path, streams)
    
    if audio_maps is None: 
        print(f"{Colors.FAIL}Falló la conversión a MP4.{Colors.ENDC}")
        return
    
    # 4. HLS
    try:
        master_pl = generate_hls(mp4_path, output_dir, safe_name, audio_maps, subs_maps, video_codec)
    except Exception as e:
        print(f"{Colors.FAIL}Error generando HLS: {e}{Colors.ENDC}")
        return
    
    # 5. Patch Master
    patch_master_with_subs(master_pl, subs_maps, audio_maps)
    
    os.remove(mp4_path)
    
    print(f"\n{Colors.GREEN}¡Proceso completado!{Colors.ENDC}")
    print(f"Carpeta: {output_dir}")
    print(f"Master: {master_pl}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1].lower() == "batch":
            # Batch mode from CLI
            current_dir = Path.cwd()
            mkv_files = list(current_dir.glob("*.mkv"))
            if not mkv_files:
                print(f"\n{Colors.WARNING}No se encontraron archivos .mkv en la carpeta actual.{Colors.ENDC}")
            else:
                 print(f"\n{Colors.GREEN}Modo Batch: Se encontraron {len(mkv_files)} archivos.{Colors.ENDC}")
                 for i, mkv in enumerate(mkv_files, 1):
                     print(f"\n{Colors.HEADER}=== Procesando archivo {i}/{len(mkv_files)}: {mkv.name} ==={Colors.ENDC}")
                     process_video(str(mkv))
        else:
            # Single file mode from CLI
            process_video(sys.argv[1])
    else:
        # Menú interactivo
        print(f"\n{Colors.HEADER}--- CONVERTIDOR MKV A HLS ---{Colors.ENDC}")
        print("1. Convertir un archivo en específico")
        print("2. Convertir todos los mkv de la carpeta actual")
        
        choice = input("\nSeleccione una opción (1 o 2): ").strip()
        
        if choice == '1':
            path = input("\nArrastra el archivo MKV aquí: ").strip('"\'')
            if os.path.isfile(path):
                process_video(path)
            else:
                print(f"{Colors.FAIL}El archivo no existe.{Colors.ENDC}")
        
        elif choice == '2':
            current_dir = Path.cwd()
            mkv_files = list(current_dir.glob("*.mkv"))
            
            if not mkv_files:
                print(f"\n{Colors.WARNING}No se encontraron archivos .mkv en la carpeta actual.{Colors.ENDC}")
            else:
                print(f"\n{Colors.GREEN}Se encontraron {len(mkv_files)} archivos.{Colors.ENDC}")
                for i, mkv in enumerate(mkv_files, 1):
                    print(f"\n{Colors.HEADER}=== Procesando archivo {i}/{len(mkv_files)}: {mkv.name} ==={Colors.ENDC}")
                    process_video(str(mkv))
        
        else:
            print(f"{Colors.FAIL}Opción no válida.{Colors.ENDC}")
            
        # input("\nPresione Enter para salir...")
