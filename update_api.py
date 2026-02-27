import re
import os

# CONFIGURACIÓN
archivo_config = "config.js"  # Asegúrate de que la ruta sea correcta

def actualizar_api_url():
    # 1. Pedir la nueva URL al usuario
    print("--- ACTUALIZADOR DE API BACKEND ---")
    nueva_url = input("Pega la nueva URL del túnel (ej. https://random.trycloudflare.com): ").strip()
    
    # Limpieza básica: quitar slash final si existe y asegurar https
    nueva_url = nueva_url.rstrip('/')
    if not nueva_url.startswith("http"):
        print("Error: La URL debe empezar con http o https")
        return

    # 2. Verificar existencia del archivo
    if not os.path.exists(archivo_config):
        print(f"Error: No encuentro el archivo '{archivo_config}'")
        return

    # 3. Leer el contenido
    with open(archivo_config, 'r', encoding='utf-8') as f:
        contenido = f.read()

    # 4. Usar Regex para encontrar la línea const API_URL = "..."
    # Busca: const API_URL = "CUALQUIER_COSA";
    patron = r'(const\s+API_URL\s*=\s*")([^"]*)(")'
    
    # Reemplazamos el grupo 2 (la url vieja) por la nueva
    nuevo_contenido = re.sub(patron, fr'\1{nueva_url}\3', contenido)

    # 5. Guardar cambios
    if contenido == nuevo_contenido:
        print("No se hicieron cambios (quizás la URL era la misma o no se encontró el patrón).")
    else:
        with open(archivo_config, 'w', encoding='utf-8') as f:
            f.write(nuevo_contenido)
        print(f"✅ ¡Listo! API_URL actualizada a: {nueva_url}")
        print("Recuerda subir 'config.js' a GitHub para que los usuarios vean el cambio.")

if __name__ == "__main__":
    actualizar_api_url()