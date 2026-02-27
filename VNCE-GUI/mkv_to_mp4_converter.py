
import os
import subprocess
import json
import sys

# --- Configuración de Colores para Terminal ---
# Esto habilita el soporte de colores ANSI en la consola de Windows
os.system('color')

class Colores:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    END = '\033[0m'
    BOLD = '\033[1m'

def obtener_stream_espanol(archivo):
    """
    Analiza el archivo con ffprobe y busca un stream de audio en español.
    """
    cmd = [
        'ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', archivo
    ]
    
    try:
        resultado = subprocess.check_output(cmd).decode('utf-8')
        datos = json.loads(resultado)
        
        streams_audio = [s for s in datos.get('streams', []) if s.get('codec_type') == 'audio']
        
        if not streams_audio:
            return None

        for s in streams_audio:
            tags = s.get('tags', {})
            titulo = tags.get('title', '').lower()
            lenguaje = tags.get('language', '').lower()
            
            if 'español' in titulo or 'spanish' in titulo or lenguaje in ['spa', 'es']:
                return f"0:{s['index']}"
                
        return None

    except Exception as e:
        print(f"{Colores.FAIL}  [Error] No se pudo analizar tracks: {e}{Colores.END}")
        return None

def procesar_lista_archivos(archivos_procesar):
    """
    Recibe una lista de nombres de archivos y ejecuta la lógica de conversión.
    """
    if not archivos_procesar:
        print(f"{Colores.FAIL}No se encontraron archivos válidos o la lista está vacía.{Colores.END}")
        return

    print(f"{Colores.HEADER}Se procesarán {len(archivos_procesar)} archivos...{Colores.END}\n")

    for archivo in archivos_procesar:
        # Check if file exists
        if not os.path.exists(archivo):
            print(f"{Colores.FAIL}Archivo no encontrado: {archivo}{Colores.END}")
            continue

        nombre_base, extension = os.path.splitext(archivo)
        extension = extension.lower()
        titulo_metadata = nombre_base
        
        # Ignorar archivos temporales si se colaron en la lista
        if archivo.startswith("temp_"):
            continue

        print(f"{Colores.CYAN}--------------------------------------------------{Colores.END}")
        print(f"{Colores.BOLD}Procesando: {archivo}{Colores.END}")

        # --- Detección de Audio ---
        map_opcion_base = ['-map', '0', '-map', '-0:i'] # Mapea todo, pero excluye imágenes (carátulas)
        map_opcion = []
        track_audio = obtener_stream_espanol(archivo)
        msg_audio = ""
        
        if track_audio:
            # Si hay audio español, usa solo video y ese track de audio, excluyendo el resto
            map_opcion = ['-map', '0:v:0', '-map', track_audio, '-map', '-0:i']
            msg_audio = f"{Colores.GREEN}Audio Español detectado (Stream {track_audio}). Carátulas eliminadas.{Colores.END}"
        else:
            # Si no hay audio español, usa el mapa base que conserva todo menos las carátulas.
            map_opcion = map_opcion_base
            msg_audio = f"{Colores.WARNING}No se detectó etiqueta 'Español'. Se conservan todas las pistas, excepto carátulas.{Colores.END}"

        print(f"  └── {msg_audio}")

        # --- C1: Archivos MKV ---
        if extension == '.mkv':
            archivo_salida = f"{nombre_base}.mp4"
            
            comando = [
                'ffmpeg', '-i', archivo, *map_opcion, # *** map_opcion YA INCLUYE EXCLUSIÓN DE CARÁTULA ***
                '-c', 'copy', '-metadata', f'title={titulo_metadata}',
                '-y', '-loglevel', 'error', archivo_salida
            ]

            try:
                subprocess.run(comando, check=True)
                os.remove(archivo)
                print(f"  └── {Colores.GREEN}Éxito. Convertido a MP4 y original eliminado.{Colores.END}")
            except subprocess.CalledProcessError:
                print(f"  └── {Colores.FAIL}[ERROR] Falló la conversión.{Colores.END}")

        # --- C2: Archivos MP4 ---
        elif extension == '.mp4':
            if track_audio:
                print(f"  └── {Colores.WARNING}Limpiando pistas extra (inglés/otros) y carátulas...{Colores.END}")
            
            archivo_temporal = f"temp_{archivo}"

            comando = [
                'ffmpeg', '-i', archivo, *map_opcion, # *** map_opcion YA INCLUYE EXCLUSIÓN DE CARÁTULA ***
                '-metadata', f'title={titulo_metadata}', '-c', 'copy',
                '-map_metadata', '0', '-y', '-loglevel', 'error', archivo_temporal
            ]

            try:
                subprocess.run(comando, check=True)
                os.replace(archivo_temporal, archivo)
                print(f"  └── {Colores.GREEN}Éxito. Archivo actualizado.{Colores.END}")
            except subprocess.CalledProcessError:
                print(f"  └── {Colores.FAIL}[ERROR] Falló al actualizar.{Colores.END}")
                if os.path.exists(archivo_temporal):
                    os.remove(archivo_temporal)
        else:
             print(f"  └── {Colores.FAIL}[Saltado] Formato no soportado.{Colores.END}")

    print(f"\n{Colores.HEADER}--- Proceso terminado ---{Colores.END}")

def menu_principal():
    # CLI Mode Check
    if len(sys.argv) > 1:
        param = sys.argv[1]
        
        # If param is a file
        if os.path.isfile(param):
             procesar_lista_archivos([param])
             return
        # If param is "batch" or similar, or just loop current dir
        elif param.lower() == "batch":
             # Process all in current dir
             todos_archivos = os.listdir('.')
             lista_final = [f for f in todos_archivos if f.lower().endswith(('.mp4', '.mkv')) and not f.startswith("temp_")]
             procesar_lista_archivos(lista_final)
             return

    # Interactive Mode
    print(f"{Colores.CYAN}{Colores.BOLD}=== AUTOMATIZACIÓN DE VIDEO ==={Colores.END}")
    print("Selecciona una opción:")
    print(f"{Colores.GREEN}1.{Colores.END} Leer toda la carpeta actual")
    print(f"{Colores.GREEN}2.{Colores.END} Leer un archivo específico")
    
    opcion = input(f"\n{Colores.BOLD}Tu elección (1/2): {Colores.END}")

    lista_final = []

    if opcion == '1':
        # Leer directorio actual
        todos_archivos = os.listdir('.')
        lista_final = [f for f in todos_archivos if f.lower().endswith(('.mp4', '.mkv')) and not f.startswith("temp_")]
        
        if not lista_final:
            print(f"\n{Colores.WARNING}No hay archivos .mkv o .mp4 en esta carpeta.{Colores.END}")
            return

    elif opcion == '2':
        # Leer archivo específico
        nombre_input = input(f"\nIntroduce el nombre del archivo (ej. {Colores.CYAN}pelicula.mkv{Colores.END}): ")
        
        # Limpiar comillas por si el usuario arrastra el archivo a la terminal
        nombre_input = nombre_input.strip('"').strip("'")
        
        if os.path.isfile(nombre_input):
            if nombre_input.lower().endswith(('.mp4', '.mkv')):
                lista_final = [nombre_input]
            else:
                print(f"\n{Colores.FAIL}Error: El archivo debe ser .mp4 o .mkv{Colores.END}")
        else:
            print(f"\n{Colores.FAIL}Error: El archivo '{nombre_input}' no existe.{Colores.END}")
            
    else:
        print(f"\n{Colores.FAIL}Opción inválida.{Colores.END}")
        return

    # Si tenemos archivos, ejecutamos
    if lista_final:
        print("") # Espacio visual
        procesar_lista_archivos(lista_final)

if __name__ == "__main__":
    try:
        menu_principal()
    except KeyboardInterrupt:
        print(f"\n{Colores.FAIL}Operación cancelada por el usuario.{Colores.END}")