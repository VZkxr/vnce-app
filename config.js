/**
 * CONFIGURACIÓN DE URL DE API - VANACUE
 * Adaptativo para Desarrollo Local (Tailscale) y Producción (Cloudflare)
 */

const getApiUrl = () => {
    const host = window.location.hostname;
    
    // 1. Si estamos en el dominio oficial o GitHub con HTTPS
    if (host === 'vnc-e.com') return 'https://vnc-e.com';
    
    // 2. Si estamos en PC de desarrollo (Windows) vía Live Server (127.0.0.1:5500)
    // Pero el servidor vive en la laptop vieja con Tailscale:
    if (host === '127.0.0.1' || host === 'localhost') {
        // Probamos primero con el dominio público para que pase por el túnel/Nginx
        // Si tienes problemas de internet local, podrías cambiar esto por la IP de Tailscale: 'http://100.94.135.13:3000'
        return 'https://vnc-e.com'; 
    }

    // 3. Si accedemos por IP de Tailscale directamente
    if (host === '100.94.135.13') return 'http://100.94.135.13:3000';

    return 'https://vnc-e.com';
};

const API_URL = getApiUrl();

console.log("%c[Vanacue Net]", "color: #e50914; font-weight: bold;", "Origen:", window.location.origin, "-> API:", API_URL);