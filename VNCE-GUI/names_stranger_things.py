import os
import re
import subprocess

# --- CONFIGURACIÓN AUTOMÁTICA ---
# Obtiene la ruta absoluta de la carpeta donde está este archivo script
DIRECTORIO_ARCHIVOS = os.path.dirname(os.path.abspath(__file__))

EXTENSION = '.mkv'
NOMBRE_CARPETA_SALIDA = "LISTOS"

def limpiar_titulo_stranger_things(texto_sucio):
    # Eliminar grupo de release (después del último guion)
    if '-' in texto_sucio:
        texto_sucio = texto_sucio.rsplit('-', 1)[0]
    
    # Reemplazar puntos por espacios
    texto_limpio = texto_sucio.replace('.', ' ')
    
    # Eliminar "Chapter One", "Chapter Two", etc.
    texto_limpio = re.sub(r'^Chapter\s+\w+\s+', '', texto_limpio, flags=re.IGNORECASE)
    
    return texto_limpio.strip()

def procesar_stranger_things_seguro():
    # Regex ajustada para tus archivos
    REGEX_PATRON = re.compile(r"\.S(\d+)E(\d+)\.(.*)" + re.escape(EXTENSION) + r"$", re.IGNORECASE)

    print(f"📂 Trabajando en: {DIRECTORIO_ARCHIVOS}")

    # Crear carpeta de salida "LISTOS"
    ruta_carpeta_salida = os.path.join(DIRECTORIO_ARCHIVOS, NOMBRE_CARPETA_SALIDA)
    if not os.path.exists(ruta_carpeta_salida):
        os.makedirs(ruta_carpeta_salida)
        print(f"📁 Carpeta de salida creada: {NOMBRE_CARPETA_SALIDA}")

    for nombre_archivo in os.listdir(DIRECTORIO_ARCHIVOS):
        # Ignoramos la carpeta de salida y el propio script
        if nombre_archivo == NOMBRE_CARPETA_SALIDA or nombre_archivo == os.path.basename(__file__):
            continue
        
        if nombre_archivo.lower().endswith(EXTENSION):
            
            match = REGEX_PATRON.search(nombre_archivo)

            if match:
                temporada = int(match.group(1))
                episodio = int(match.group(2))
                resto_nombre = match.group(3)

                # --- LIMPIEZA ---
                titulo_real = limpiar_titulo_stranger_things(resto_nombre)

                # --- NOMBRES ---
                titulo_final = f"T{temporada}.E{episodio} - {titulo_real}"
                nuevo_nombre_archivo = f"{titulo_final}{EXTENSION}"

                ruta_original = os.path.join(DIRECTORIO_ARCHIVOS, nombre_archivo)
                # Guardamos en la subcarpeta "LISTOS" para evitar errores de bloqueo
                ruta_final = os.path.join(ruta_carpeta_salida, nuevo_nombre_archivo)

                print(f"Procesando: {nombre_archivo}")
                print(f"  -> Título: '{titulo_real}'")

                # --- FFmpeg ---
                comando = [
                    'ffmpeg', 
                    '-n',  # No sobrescribir si ya existe en destino
                    '-i', ruta_original,
                    '-map', '0',       # Copiar todo
                    '-c', 'copy',      # Sin recodificar
                    '-metadata', f'title={titulo_final}',
                    '-loglevel', 'error',
                    ruta_final
                ]

                try:
                    subprocess.run(comando, check=True)
                    print(f"  ✅ Guardado en: {NOMBRE_CARPETA_SALIDA}\\{nuevo_nombre_archivo}")

                except subprocess.CalledProcessError:
                    print(f"  ⚠️ Error o el archivo ya existe en '{NOMBRE_CARPETA_SALIDA}'.")
                except Exception as e:
                    print(f"  ❌ Error general: {e}")

                print("-" * 30)

if __name__ == "__main__":
    procesar_stranger_things_seguro()
    print("--- PROCESO TERMINADO ---")
    input("Presiona Enter para salir...") # Descomenta esto si quieres que la ventana no se cierre sola