
import os
import subprocess
import json
import platform
import sys
from pathlib import Path

def convert_video(file_path):
    """
    Analyzes and converts a video file to HLS format with auto-audio correction.
    """
    filename = os.path.basename(file_path)
    base_name = os.path.splitext(filename)[0]
    
    print("-" * 48)
    print(f"Analizando: {filename}...")

    # 1. DIAGNÓSTICO CON FFPROBE
    codec = "desconocido"
    channels = 0
    
    # Check if file exists to avoid ffprobe errors
    if not os.path.exists(file_path):
        print(f"Error: El archivo '{file_path}' no existe.")
        return

    probe_cmd = [
        "ffprobe", 
        "-v", "error", 
        "-select_streams", "a:0", 
        "-show_entries", "stream=codec_name,channels", 
        "-of", "json", 
        file_path
    ]
    
    try:
        # Run ffprobe
        result = subprocess.run(probe_cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        
        if "streams" in data and len(data["streams"]) > 0:
            stream = data["streams"][0]
            codec = stream.get("codec_name", "desconocido")
            channels = stream.get("channels", 0)
    except Exception as e:
        print(f"Advertencia: No se pudo detectar audio. Se usará configuración estándar. ({e})")

    print(f"   > Audio detectado: {codec} | Canales: {channels}")

    # 2. DECISIÓN DE CONVERSIÓN
    audio_params = []
    
    # Logic from original script:
    # if ($codec -eq "aac" -and $channels -le 2)
    if codec == "aac" and channels <= 2:
        print("   > ESTADO: Compatible. Se usará copia directa (Rápido).")
        audio_params = ["-c:a", "copy"]
    else:
        print(f"   > ESTADO: Incompatible para Web ({codec}/{channels} ch). Recodificando a AAC Estéreo...")
        # $paramsAudio = "-c:a aac -ac 2 -b:a 192k"
        audio_params = ["-c:a", "aac", "-ac", "2", "-b:a", "192k"]

    # 3. PREPARAR CARPETA
    # $nombreBase = $archivo.BaseName -> base_name
    output_dir = os.path.join(os.getcwd(), base_name)
    if not os.path.exists(output_dir):
        try:
            os.makedirs(output_dir)
        except OSError as e:
            print(f"Error al crear directorio {output_dir}: {e}")
            return

    # 4. EJECUTAR FFMPEG
    # Output file: $nombreBase\$nombreBase.m3u8
    output_playlist = os.path.join(output_dir, f"{base_name}.m3u8")
    
    # Arguments: -i input -c:v copy [audio_params] -sn -hls_time 10 -hls_list_size 0 -f hls output
    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-i", file_path,
        "-c:v", "copy"
    ]
    
    ffmpeg_cmd.extend(audio_params)
    
    ffmpeg_cmd.extend([
        "-sn",
        "-hls_time", "10",
        "-hls_list_size", "0",
        "-f", "hls",
        output_playlist
    ])

    print("   > Procesando video... (Por favor espera)")
    
    try:
        # Run ffmpeg
        subprocess.run(ffmpeg_cmd, check=True)
        print(f"-> Listo: {base_name}\\{base_name}.m3u8")
    except subprocess.CalledProcessError as e:
        print(f"Error al convertir {filename}: {e}")
    except Exception as e:
        print(f"Error inesperado: {e}")
    
    print("")

def main():
    print("--- CONVERTIDOR MP4 A HLS ---")
    print("1. Convertir archivo especifico")
    print("2. Convertir todos los MP4 de la carpeta actual")
    
    # If arguments provided (for GUI/automation?)
    # If arguments provided (for GUI/automation?)
    if len(sys.argv) > 1:
        if sys.argv[1].lower() == "batch":
            files = list(Path('.').glob('*.mp4'))
            if not files:
                print("No se encontraron archivos MP4.")
            for f in files:
                convert_video(str(f))
        else:
            # Assume arg is file path
            convert_video(sys.argv[1])
        return

    choice = input("Seleccione una opción: ").strip()
    
    if choice == '1':
        f = input("Archivo MP4: ").strip('"\'')
        if os.path.exists(f):
            convert_video(f)
        else:
            print("Archivo no encontrado.")
            
    elif choice == '2':
        files = list(Path('.').glob('*.mp4'))
        if not files:
            print("No se encontraron archivos MP4.")
        for f in files:
            convert_video(str(f))

if __name__ == "__main__":
    main()
