
import os
import re
import subprocess
import shutil
import sys

# Forces UTF-8 output for Windows console
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

# --- CONFIGURACIÓN ---
DIRECTORIO_ARCHIVOS = r"." 
EXTENSION = '.mkv'

def renombrar_archivo_individual(nombre_archivo, directorio):
    patterns = [
        re.compile(r"^S(\d+)X(\d+)\s+(.*)" + re.escape(EXTENSION) + r"$", re.IGNORECASE),
        re.compile(r"^(\d+)[Xx](\d+)[-\s]+(.*)" + re.escape(EXTENSION) + r"$", re.IGNORECASE),
        re.compile(r".*?[S|s](\d+)[E|e](\d+)\.(.+?)\.(?:1080p|720p|2160p|4k|WEB|HDTV|BluRay|HDR|DV|DDP|H\.265|x264|x265|HEVC|AVC|MAX|AMZN|NF|HMAX).*" + re.escape(EXTENSION) + r"$", re.IGNORECASE),
        re.compile(r".*?[S|s](\d+)[E|e](\d+)\.(.+?)" + re.escape(EXTENSION) + r"$", re.IGNORECASE)
    ]

    try:
        # Try each pattern
        match = None
        for i, p in enumerate(patterns):
            try:
                m = p.match(nombre_archivo)
                if m:
                    match = m
                    break
            except Exception:
                continue
        
        if match:
            temporada = int(match.group(1))
            episodio = int(match.group(2))
            titulo_raw = match.group(3)
            
            # Clean title
            titulo_limpio = titulo_raw.replace('.', ' ').strip()
            titulo_limpio = titulo_limpio.strip('- ')

            # 1. Definir nuevos nombres
            titulo_final = f"T{temporada}.E{episodio} - {titulo_limpio}"
            nuevo_nombre_archivo = f"{titulo_final}{EXTENSION}"
            nombre_temporal = f"temp_{nombre_archivo}"

            # Skip if already named correctly
            if nombre_archivo == nuevo_nombre_archivo:
                print(f"Skipping {nombre_archivo} (already correct)")
                return False

            ruta_original = os.path.join(directorio, nombre_archivo)
            ruta_temp = os.path.join(directorio, nombre_temporal)
            ruta_final = os.path.join(directorio, nuevo_nombre_archivo)

            print(f"Procesando: {nombre_archivo}")
            print(f"  -> Nuevo nombre: {nuevo_nombre_archivo}")
            
            # Check for existing destination
            if os.path.exists(ruta_final):
                 print(f"  ⚠️ El archivo destino '{nuevo_nombre_archivo}' ya existe. Saltando.")
                 return False

            # 2. Comando FFmpeg / mkvpropedit
            use_mkvpropedit = False
            if shutil.which("mkvpropedit"):
                use_mkvpropedit = True
            
            try:
                if use_mkvpropedit:
                    # Rename first
                    try:
                        os.rename(ruta_original, ruta_final)
                    except OSError as e:
                        print(f"  ❌ Error renombrando archivo: {e}")
                        return False
                        
                    # Update metadata in place
                    subprocess.run([
                        "mkvpropedit", ruta_final,
                        "--edit", "info",
                        "--set", f"title={titulo_final}"
                    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, encoding='utf-8', errors='replace')
                    print("  ✅ Renombrado y Metadatos actualizados (mkvpropedit).")
                else:
                    # Fallback to ffmpeg copy
                    comando = [
                        'ffmpeg',
                        '-i', ruta_original,
                        '-map', '0',       # Copia todo
                        '-map_metadata', '0', # Preservar todos los metadatos originales
                        '-c', 'copy',      
                        '-metadata', f'title={titulo_final}',
                        '-loglevel', 'error',
                        '-y',
                        ruta_temp
                    ]
                    subprocess.run(comando, check=True)
                    if os.path.exists(ruta_original):
                        os.remove(ruta_original)
                    os.rename(ruta_temp, ruta_final)
                    print("  ✅ Renombrado y Metadatos actualizados (ffmpeg).")
                
                return True

            except subprocess.CalledProcessError as e:
                print(f"  ❌ Error subprocess: {e}")
                if os.path.exists(ruta_temp):
                    try: os.remove(ruta_temp)
                    except: pass
                return False
            except Exception as e:
                print(f"  ❌ Error inesperado: {e}")
                return False
        else:
            print(f"Skipping {nombre_archivo} (no pattern match)")
            return False
            
    except Exception as e:
        print(f"❌ Error crítico en archivo '{nombre_archivo}': {e}")
        return False

def renombrar_y_etiquetar_mkv(target_file=None):
    if target_file:
         # Process single file
         if os.path.exists(target_file):
             dirname, filename = os.path.split(target_file)
             if not dirname: dirname = os.getcwd() # Handle local file name only
             renombrar_archivo_individual(filename, dirname)
         else:
             print(f"File not found: {target_file}")
    else:
        # Batch process
        print(f"Procesando archivos desde carpeta actual: {os.getcwd()}")
        archivos = [f for f in os.listdir(DIRECTORIO_ARCHIVOS) if f.lower().endswith(EXTENSION)]
        
        if not archivos:
            print("No se encontraron archivos MKV en el directorio actual.")
            return

        count = 0
        errors = 0

        for nombre_archivo in archivos:
            if renombrar_archivo_individual(nombre_archivo, DIRECTORIO_ARCHIVOS):
                count += 1
            else:
                # We can consider 'False' as error or just skipped/no match.
                # Let's assume if it prints error it's error.
                pass 
                
        print(f"\nResumen: {count} archivos procesados.")

if __name__ == "__main__":
    try:
        if len(sys.argv) > 1:
            renombrar_y_etiquetar_mkv(sys.argv[1])
        else:
            renombrar_y_etiquetar_mkv()
            
    except Exception as e:
        print(f"❌ Error fatal en script: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)