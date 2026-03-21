// ==========================================
//  FUNCION DE SEGURIDAD (EL LATIDO / HEARTBEAT)
// ==========================================

async function verificarSesionActiva() {
    const token = localStorage.getItem('vanacue_token');

    // 1. Recuperamos el nombre del usuario de la memoria local
    const userStr = localStorage.getItem('vanacue_user');
    const username = userStr ? JSON.parse(userStr).username : 'anonimo';

    if (!token) return;

    try {
        // Obtenemos el título de la película/serie en curso
        const media = window.currentMediaWatching || 'Ninguna';

        // 2. TRUCO: Agregamos &u=NombreUsuario y &media= a la URL
        const urlPing = `${API_URL}/api/ping?t=${Date.now()}&u=${encodeURIComponent(username)}&media=${encodeURIComponent(media)}`;

        const response = await fetch(urlPing, {
            headers: { 'Authorization': `Bearer ${token}` }
        });

        const data = await response.json();

        // --- ACTUALIZAR FOTO DE PERFIL DESDE PING ---
        if (data.success && data.user && data.user.profile_pic) {
            const profileUrl = `Multimedia/Profiles/${data.user.profile_pic}`;
            const dropdownImg = document.getElementById('dropdown-profile-img');
            const modalImg = document.getElementById('modal-profile-img');
            if (dropdownImg) dropdownImg.src = profileUrl;
            if (modalImg) modalImg.src = profileUrl;

            // Actualizar en localStorage para persistencia local
            const user = JSON.parse(localStorage.getItem('vanacue_user') || '{}');
            user.profile_pic = data.user.profile_pic;
            user.username = data.user.username; // Asegurar que el nombre también esté al día
            localStorage.setItem('vanacue_user', JSON.stringify(user));

            // Actualizar nombre en el dropdown por si acaso cambió
            const configName = document.getElementById('config-user-name');
            if (configName) configName.innerText = data.user.username;
        }

        if (handleSessionError(data)) {
            console.warn("Sesión invalidada. Cerrando...");
        }
    } catch (error) {
        console.log("Error de red...", error);
    }
}

// ==========================================
//  FUNCIÓN  PARA INICIALIZAR FAVORITOS
// ==========================================
function inicializarSistemaFavoritos() {
    // Solo cargar si no existe ya la promesa
    if (!favoritosPromesa && typeof cargarFavoritos === 'function') {
        console.log("Iniciando carga de favoritos...");
        favoritosPromesa = cargarFavoritos();
    }
}

// ==========================================
//  INICIO DE LA APLICACION
// ==========================================
document.addEventListener('DOMContentLoaded', async () => {
    // 1. Detección inmediata de sección para evitar flicker de Hero
    const params = new URLSearchParams(window.location.search);
    const accion = params.get('accion');
    const esIndex = document.getElementById('mainContent') !== null;

    if (accion && accion !== 'home') {
        // --- FIX DATA SYNC: Esperamos a que globalData esté listo antes de renderizar ---
        if (typeof dataPromise !== 'undefined') {
            await dataPromise;
        }

        if (accion === 'reseñas' || accion === 'reviews') {
            const userStr = localStorage.getItem('vanacue_user');
            const user = userStr ? JSON.parse(userStr) : {};
            if (user.reviews_block) {
                window.location.href = "index.html";
                return;
            }
            window.renderView('reviews');
        }
        else if (accion === 'series') window.renderView('series');
        else if (accion === 'peliculas') window.renderView('movies');
        else if (accion === 'favoritos') window.renderView('favorites');
        else if (accion === 'planes') window.renderView('plans');
        else if (accion === 'scanner') window.renderView('scanner');
        else if (params.has('genero')) window.renderView('genre', params.get('genero'));

        // Autorizar y mostrar contenido de inmediato
        const mainContent = document.getElementById('mainContent');
        if (esIndex && mainContent) mainContent.style.display = 'block';
    }

    const token = localStorage.getItem('vanacue_token');
    const userStr = localStorage.getItem('vanacue_user');
    const mainContent = document.getElementById('mainContent');

    // --- 0. INICIALIZACIÓN INMEDIATA DEL PERFIL ---
    if (userStr) {
        try {
            const u = JSON.parse(userStr);
            const pUrl = `Multimedia/Profiles/${u.profile_pic || 'alucard.jpg'}`;
            const ddImg = document.getElementById('dropdown-profile-img');
            const configName = document.getElementById('config-user-name');
            if (ddImg) ddImg.src = pUrl;
            if (configName) configName.innerText = u.username || 'Usuario';
        } catch (e) { console.error("Error parsing stored user", e); }
    }

    if (!token || !userStr) {
        console.warn("Acceso denegado (Credenciales locales faltantes).");
        window.location.href = 'login.html' + window.location.search;
        return;
    }

    console.log("INIT: Inicializando sistema de favoritos...");
    inicializarSistemaFavoritos();

    if (favoritosPromesa) {
        try {
            await favoritosPromesa;
        } catch (error) {
            console.error("INIT: Error cargando favoritos:", error);
        }
    }

    // 2. Lógica de Home (solo si no se cargó otra sección arriba)
    if (!accion || accion === 'home') {
        if (esIndex && typeof cargarHero === 'function') cargarHero();
        if (esIndex && mainContent) mainContent.style.display = 'block';
    }

    await verificarSesionActiva();
    setInterval(verificarSesionActiva, 15000);

    const user = JSON.parse(userStr);
    const displayElement = document.getElementById('user-display');
    if (displayElement) displayElement.innerText = user.username;

    const btnLogout = document.getElementById('btn-logout');
    if (btnLogout) {
        btnLogout.addEventListener('click', () => {
            localStorage.removeItem('vanacue_token');
            localStorage.removeItem('vanacue_user');
            window.location.href = 'login.html';
        });
    }

    if (user && user.role === 'admin') {
        const linkScanner = document.getElementById('link-scanner');
        if (linkScanner) linkScanner.style.display = 'inline-block';
    }

    const linkScannerLocal = document.getElementById('link-scanner');
    if (linkScannerLocal) {
        linkScannerLocal.addEventListener('click', (e) => {
            e.preventDefault();
            window.navigateTo('scanner');
        });
    }
});


// ==========================================
// SISTEMA DE FAVORITOS (FRONTEND)
// ==========================================

let misFavoritos = new Set(); // Aquí guardaremos los IDs de las pelis favoritas
let favoritosPromesa = null;

// Función para descargar la lista de favoritos al iniciar
// Función para descargar la lista de favoritos al iniciar
function cargarFavoritos() {
    const token = localStorage.getItem('vanacue_token');

    // Si no hay token, retornamos una promesa vacía inmediata para evitar errores
    if (!token) return Promise.resolve();

    // === OPTIMIZACIÓN: Si ya hay una promesa en curso o resuelta, la reutilizamos ===
    if (favoritosPromesa) {
        return favoritosPromesa;
    }

    // Asignamos todo el proceso a la variable global 'favoritosPromesa'
    favoritosPromesa = fetch(`${API_URL}/api/favorites`, {
        headers: { 'Authorization': `Bearer ${token}` }
    })
        .then(response => response.json())
        .then(data => {
            // === INTERCEPTOR DE SESIÓN ===
            if (handleSessionError(data)) return;
            // ============================

            if (data.success) {
                misFavoritos.clear();
                window.misFavoritosOrdenados = []; // Reiniciamos la lista ordenada

                // Guardamos TANTO strings comos números para asegurar match
                // API devuelve ordenado (más reciente al final o principio según backend, asumimos orden de llegada)
                // Si el backend devuelve [oldest, ..., newest], para mostrar "más reciente" primero, hacemos reverse().
                // Si devuelve [newest, ..., oldest], lo dejamos así.
                // Asumiremos que el backend devuelve en orden de inserción (oldest -> newest), 
                // así que invertiremos para mostrar el más reciente primero.
                const favoritosReversos = [...data.favorites].reverse();

                favoritosReversos.forEach(fav => {
                    if (fav.movie_tmdb_id) {
                        misFavoritos.add(String(fav.movie_tmdb_id));
                        misFavoritos.add(Number(fav.movie_tmdb_id));
                        window.misFavoritosOrdenados.push(fav.movie_tmdb_id); // Guardamos para orden

                        // Soporte para IDs generados (strings largos)
                        if (isNaN(fav.movie_tmdb_id)) {
                            misFavoritos.add(fav.movie_tmdb_id);
                        }
                    }
                });

                console.log("Favoritos sincronizados. Total:", misFavoritos.size / 2); // Dividimos entre 2 por la duplicidad deliberada
                actualizarEstrellasVisibles();
            }
        })
        .catch(error => {
            console.error("Error cargando favoritos:", error);
            // Si falla, anulamos la promesa para permitir reintentos futuros
            favoritosPromesa = null;
        });

    // Retornamos la promesa para que la lógica de redirección pueda usar .then()
    return favoritosPromesa;
}

// Helper para refrescar todas las estrellas en pantalla
function actualizarEstrellasVisibles() {
    console.log("---- Actualizando estrellas visuales ----");
    console.log("Favoritos en memoria (Set):", [...misFavoritos]);

    document.querySelectorAll('.icono-favorito').forEach(icon => {
        const id = icon.dataset.id;
        // Verificamos si existe como string o como número
        const existe = misFavoritos.has(id) || misFavoritos.has(Number(id));

        if (existe) {
            icon.src = "Multimedia/star_r.svg";
            icon.classList.add("favorito-activo");
        } else {
            icon.src = "Multimedia/star.svg";
            icon.classList.remove("favorito-activo");
        }
    });
}

// Función para dar/quitar like
async function toggleFavorito(pelicula, btnIcono) {
    const token = localStorage.getItem('vanacue_token');

    // Identificación Unificada (aseguramos compatibilidad)
    const id = pelicula.tmdbId || (typeof generateId === 'function' ? generateId(pelicula) : null);

    if (!id) { console.error("No se pudo identificar la película"); return; }

    const esFavorito = misFavoritos.has(id) || misFavoritos.has(Number(id));

    // A) CAMBIO VISUAL INMEDIATO (Optimista)
    if (esFavorito) {
        btnIcono.classList.remove('favorito-activo');
        btnIcono.src = "Multimedia/star.svg";

        // BORRAR AMBAS VERSIONES (String y Number) para evitar "fantasmas"
        misFavoritos.delete(String(id));
        misFavoritos.delete(Number(id));

        // Sincronizar lista ordenada
        if (window.misFavoritosOrdenados) {
            console.log("Eliminando de lista ordenada:", id);
            window.misFavoritosOrdenados = window.misFavoritosOrdenados.filter(favId => String(favId) !== String(id));
        }
    } else {
        btnIcono.classList.add('favorito-activo');
        btnIcono.src = "Multimedia/star_r.svg";
        misFavoritos.add(id);

        // Sincronizar lista ordenada
        if (!window.misFavoritosOrdenados) window.misFavoritosOrdenados = [];

        // Evitar duplicados al agregar
        if (!window.misFavoritosOrdenados.some(favId => String(favId) === String(id))) {
            console.log("Agregando a lista ordenada (Inicio):", id);
            window.misFavoritosOrdenados.unshift(id);
        }
    }

    // B) SINCRONIZAR VISUALMENTE
    actualizarEstrellasVisibles();

    // C) PETICIÓN AL SERVIDOR
    const endpoint = esFavorito ? '/api/favorites/remove' : '/api/favorites/add';

    try {
        const response = await fetch(`${API_URL}${endpoint}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({
                movie_tmdb_id: id,
                movie_title: pelicula.titulo,
                poster_path: pelicula.portada
            })
        });

        const data = await response.json();

        // === INTERCEPTOR DE SESIÓN ===
        if (handleSessionError(data)) return;
        // ============================

        if (!data.success) {
            // SI FALLA EL SERVER, REVERTIMOS CAMBIOS
            alert("Error al sincronizar: " + data.message);
            if (esFavorito) misFavoritos.add(id); else misFavoritos.delete(id);
            actualizarEstrellasVisibles();
        } else {
            // LÓGICA DE ACTUALIZACIÓN VISUAL (Si estamos en la pantalla de favoritos)
            if (esFavorito) {
                const seccionFav = document.querySelector(".seccion-favoritos");
                // Si estamos viendo la lista de favoritos y quitamos uno, lo animamos para que desaparezca
                if (seccionFav) {
                    const tarjeta = btnIcono.closest(".tarjeta");
                    if (tarjeta) {
                        tarjeta.style.transition = "transform 0.3s, opacity 0.3s";
                        tarjeta.style.transform = "scale(0)";
                        tarjeta.style.opacity = "0";
                        setTimeout(() => tarjeta.remove(), 300);

                        // Mostrar mensaje de "Vacío" si era el último
                        setTimeout(() => {
                            const grid = seccionFav.querySelector(".grid-genero");
                            if (grid && grid.children.length === 0) {
                                grid.innerHTML = `
                                    <div class="mensaje-vacio-container">
                                        <div class="mensaje-vacio-icono">🍿</div>
                                        <h3 class="mensaje-vacio-titulo">Tu lista está vacía</h3>
                                        <p class="mensaje-vacio-texto">
                                            Aún no has guardado películas o series.<br>
                                            ¡Explora el catálogo y marca tus favoritas!
                                        </p>
                                    </div>
                                 `;
                            }
                        }, 350);
                    }
                }
            }
        }
    } catch (error) {
        console.error("Error de conexión:", error);
        // Revertir en caso de error de red
        if (esFavorito) misFavoritos.add(id); else misFavoritos.delete(id);
        actualizarEstrellasVisibles();
    }
}

// Variable global para guardar todas las películas
let globalData = [];

// --- FUNCIONALIDADES DE FAVORITOS (LOCALSTORAGE Y ID ÚNICO) ---
const FAVORITOS_KEY = "vanacue_favoritos";

// --- FUNCIONALIDADES DE PROGRESO DE VIDEO (RESUME) ---
const PROGRESS_KEY = "vanacue_video_progress";

/** Obtiene el objeto completo de progresos */
function getAllProgress() {
    try {
        const data = localStorage.getItem(PROGRESS_KEY);
        // Migración simple: si es null, retorna objeto vacío
        if (!data) return {};

        const parsed = JSON.parse(data);

        // Si detectamos que los valores son números (versión vieja), los convertimos a objetos
        // Esto es un "lazy migration"
        for (const key in parsed) {
            if (typeof parsed[key] === 'number') {
                parsed[key] = {
                    time: parsed[key],
                    duration: 0, // Desconocido en migración
                    timestamp: Date.now()
                };
            }
        }
        return parsed;
    } catch (e) {
        return {};
    }
}

/** Guarda el tiempo actual de una película específica */
function saveVideoProgress(id, time, duration = 0, metadata = {}, forceFinish = false) {
    const progress = getAllProgress();

    // Guardamos objeto completo
    progress[id] = {
        time: time,
        duration: duration,
        timestamp: Date.now(),
        ...metadata
    };

    // Limpieza automática: Si terminó (95%) O si se forzó la finalización (Post-Play logic)
    // Nota: El usuario pidió usar la lógica de Post-Play, así que forceFinish tendrá prioridad.
    // Mantenemos el 95% como fallback por si acaso.
    if (forceFinish || (duration > 0 && (time / duration) > 0.95)) {
        delete progress[id];
    }

    localStorage.setItem(PROGRESS_KEY, JSON.stringify(progress));
}

/** Obtiene el tiempo guardado de una película */
function getVideoProgress(id) {
    const progress = getAllProgress();
    const item = progress[id];

    if (!item) return 0;

    // Compatibilidad con versión vieja (número) o nueva (objeto)
    return typeof item === 'number' ? item : item.time;
}

/** Borra el progreso (cuando la película termina) */
function removeVideoProgress(id) {
    const progress = getAllProgress();
    if (progress[id]) {
        delete progress[id];
        localStorage.setItem(PROGRESS_KEY, JSON.stringify(progress));
    }
}

/** Genera un ID único basado en el título y la fecha (ya que no tienen ID nativo). */
function generateId(pelicula) {
    // Usamos el título sin espacios y la fecha para una alta probabilidad de unicidad
    return pelicula.titulo.replace(/\s/g, '_').toLowerCase() + '_' + pelicula.fecha;
}
// ----------------------------------------------------------------------

// --- HISTORIAL DE EPISODIOS DE SERIES ---
const SERIES_HISTORY_KEY = "vanacue_series_history";

/**
 * Guarda cuál fue el último episodio tocado de una serie.
 * @param {string} seriesTitulo - Título de la serie (usado como ID).
 * @param {Object} dataEpisodio - Datos necesarios para reanudar (url, nombre, indices).
 */
function saveLastEpisode(seriesTitulo, dataEpisodio) {
    try {
        const history = JSON.parse(localStorage.getItem(SERIES_HISTORY_KEY) || '{}');
        history[seriesTitulo] = dataEpisodio;
        localStorage.setItem(SERIES_HISTORY_KEY, JSON.stringify(history));
    } catch (e) {
        console.error("Error guardando historial de serie", e);
    }
}

/**
 * Obtiene el último episodio visto de una serie.
 * @param {string} seriesTitulo 
 */
function getLastEpisode(seriesTitulo) {
    try {
        const history = JSON.parse(localStorage.getItem(SERIES_HISTORY_KEY) || '{}');
        return history[seriesTitulo];
    } catch (e) {
        return null;
    }
}

//  Contenedor principal de la aplicación 
const mainContainer = document.querySelector("main");

/**
 * Crea un elemento de tarjeta DOM para una película/serie.
 * Esta función ya incluye la lógica de Favoritos (estrella y estado).
 * @param {Object} pelicula - Objeto de la película/serie.
 * @returns {HTMLElement} El elemento div de la tarjeta.
 */
function createCardElement(pelicula) {
    // 1. Lógica de Favoritos (Existente)
    const id = pelicula.tmdbId || generateId(pelicula);
    const esFavorito = misFavoritos.has(id);

    // 2. Lógica de Streaming (Misma lógica de detección)
    let isStreamAvailable = false;

    if (pelicula.tipo === "Serie") {
        // Serie disponible si tiene temporadas o un link general
        if ((pelicula.temporadas && pelicula.temporadas.length > 0) || (pelicula.streamUrl && pelicula.streamUrl.length > 5)) {
            isStreamAvailable = true;
        }
    } else {
        // Película disponible si streamUrl es válido
        if (pelicula.streamUrl && pelicula.streamUrl.trim() !== "" && pelicula.streamUrl !== "null") {
            isStreamAvailable = true;
        }
    }

    // 3. Definir la clase de estado para el CSS (online / offline)
    const statusClass = isStreamAvailable ? 'online' : 'offline';

    // 4. Crear el HTML
    const card = document.createElement("div");
    card.classList.add("tarjeta");
    card.dataset.id = id;

    card.innerHTML = `
      <img src="${pelicula.portada}" alt="${pelicula.titulo}">
      
      <div class="indicator-stream ${statusClass}"></div>

      <img src="Multimedia/${esFavorito ? 'star_r.svg' : 'star.svg'}" 
           alt="Favorito" 
           class="icono-favorito ${esFavorito ? 'favorito' : ''}" 
           data-id="${id}">

      <div class="contenido">
        <h3>${pelicula.titulo}</h3>
        <p>${pelicula.genero.join(", ")}</p>
      </div>
    `;

    card.dataset.info = JSON.stringify(pelicula);

    // (Listener eliminado para usar delegación global)

    return card;
}

// --- VARIABLES GLOBALES PARA CONTROLAR EL SCROLL ---
let updateMenubarBackground = null;
let scrollListenerActive = false;

// === CARGADOR DE DATOS ===
// Agregamos '?v=' + new Date().getTime() para obligar a cargar el archivo nuevo siempre
const dataPromise = fetch('datos.json?v=' + new Date().getTime())
    .then(response => {
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        return response.json();
    })
    .then(data => {        // <--- NUEVO BLOQUE
        globalData = data; // Guardamos los datos para usarlos en el Modal
        return data;       // Pasamos los datos intactos para que el resto de tu código siga funcionando
    })
    .catch(e => {
        console.error('No se pudo cargar el archivo datos.json:', e);
        return [];
    });

// ==========================================
// === SPA / ROUTING SYSTEM (NUEVO) ===
// ==========================================

window.navigateTo = function (viewName, param = null) {
    // 1. Update URL without Reload
    let newUrl = "index.html";
    if (viewName === 'home') {
        newUrl = "index.html";
    } else if (viewName === 'series') {
        newUrl = "?accion=series";
    } else if (viewName === 'movies') {
        newUrl = "?accion=peliculas";
    } else if (viewName === 'favorites') {
        newUrl = "?accion=favoritos";
    } else if (viewName === 'plans') {
        newUrl = "?accion=planes";
    } else if (viewName === 'reviews') {
        const userStr = localStorage.getItem('vanacue_user');
        const user = userStr ? JSON.parse(userStr) : {};
        if (user.reviews_block) {
            mostrarToast("Función no disponible.");
            window.location.href = "index.html";
            return;
        }
        newUrl = "?accion=reseñas";
    } else if (viewName === 'scanner') {
        newUrl = "?accion=scanner";
    } else if (viewName === 'genre') {
        newUrl = `?genero=${encodeURIComponent(param)}`;
    }

    if (window.location.search !== newUrl.replace("index.html", "")) {
        window.history.pushState({ view: viewName, param: param }, "", newUrl);
    }

    // 2. Render View
    window.renderView(viewName, param);
};

window.renderView = function (viewName, param) {
    const main = document.querySelector("main");
    const hero = document.querySelector(".hero");
    const heroContainer = document.getElementById("hero-carrusel-container");
    const menubar = document.querySelector(".menubar");

    // Update Active Link (SPA aware)
    const navLinks = document.querySelectorAll(".nav-links a");
    navLinks.forEach(link => link.classList.remove("active"));

    if (viewName === 'home') document.getElementById('link-inicio')?.classList.add('active');
    else if (viewName === 'series') document.getElementById('link-series')?.classList.add('active');
    else if (viewName === 'movies') document.getElementById('link-peliculas')?.classList.add('active');
    else if (viewName === 'favorites') document.getElementById('link-favoritos')?.classList.add('active');
    else if (viewName === 'plans') document.getElementById('link-planes')?.classList.add('active');
    else if (viewName === 'reviews') document.getElementById('link-reviews')?.classList.add('active');
    else if (viewName === 'scanner') document.getElementById('link-scanner')?.classList.add('active');

    // Scroll to top
    window.scrollTo({ top: 0, behavior: 'smooth' });

    // Handle Menubar State (Default: transparent/smart)
    // If NOT home, force scrolled (solid)
    if (viewName !== 'home') {
        if (menubar) menubar.classList.add("scrolled");
        // Disable scroll listener temporarily
        if (typeof scrollListenerActive !== 'undefined' && scrollListenerActive && typeof updateMenubarBackground === 'function') {
            window.removeEventListener("scroll", updateMenubarBackground);
            scrollListenerActive = false;
        }
    } else {
        // Re-enable scroll listener for Home
        if (typeof updateMenubarBackground === 'function') {
            updateMenubarBackground(); // Check immediately
            window.addEventListener("scroll", updateMenubarBackground);
            scrollListenerActive = true;
        }
    }

    if (viewName === 'home') {
        if (hero) hero.style.display = "block";
        window.renderHome();
    } else {
        if (hero) hero.style.display = "none";

        if (viewName === 'series') window.mostrarGrid("Series", "Serie");
        else if (viewName === 'movies') window.mostrarGrid("Películas", "Película");
        else if (viewName === 'favorites') window.mostrarFavoritos();
        else if (viewName === 'plans') window.mostrarPlanes();
        else if (viewName === 'reviews') window.mostrarReseñas();
        else if (viewName === 'scanner') window.mostrarScanner();
        else if (viewName === 'genre') window.mostrarGenero(param);
    }
};

window.renderHome = function () {
    console.log("Rendering Home SPA...");
    const main = document.querySelector("main");
    if (!main) return;

    // Clear Main (Remove old grids)
    main.innerHTML = "";

    // === 1. SECCIÓN CONTINUAR VIENDO (NUEVO) ===
    renderContinueWatching(main);

    // Re-build Sections
    const secciones = ["Recién agregadas", "Terror", "Acción", "Romance", "Comedia", "Drama", "Animación", "Suspenso"];

    secciones.forEach(seccion => {
        const seccionDiv = document.createElement("div");
        seccionDiv.classList.add("seccion-catalogo");

        // Header
        const headerSeccion = document.createElement("div");
        headerSeccion.classList.add("header-seccion");

        const tituloSeccion = document.createElement("h2");
        tituloSeccion.textContent = seccion;
        headerSeccion.appendChild(tituloSeccion);

        if (seccion !== "Recién agregadas") {
            const explorarBtn = document.createElement("div");
            explorarBtn.classList.add("explorar-btn");
            explorarBtn.innerHTML = `<span class="simbolo">&#10148;</span><span class="texto">Explorar todo &#10148;</span>`;
            explorarBtn.addEventListener("click", () => {
                // SPA Navigation for Genres
                window.navigateTo('genre', seccion.toLowerCase().replace(" ", "_"));
            });
            headerSeccion.appendChild(explorarBtn);
        }
        seccionDiv.appendChild(headerSeccion);

        // Carousel Container
        const contenedorCarrusel = document.createElement("div");
        contenedorCarrusel.classList.add("carrusel-container");

        const btnLeft = document.createElement("button");
        btnLeft.classList.add("scroll-btn", "left");
        btnLeft.innerHTML = "&#10094;";

        const btnRight = document.createElement("button");
        btnRight.classList.add("scroll-btn", "right");
        btnRight.innerHTML = "&#10095;";

        const carrusel = document.createElement("div");
        carrusel.classList.add("carrusel");

        // Filter Logic (Same as before)
        const generoAliases = { "suspenso": ["suspenso", "suspense"] };
        let peliculasSeccion = [];

        if (seccion === "Recién agregadas") {
            peliculasSeccion = [...globalData].reverse().slice(0, 8);
        } else {
            const key = seccion.toLowerCase();
            if (key === "suspenso") {
                const aliases = generoAliases["suspenso"];
                peliculasSeccion = globalData.filter(p => p.genero.some(g => aliases.includes(g.toLowerCase()))).reverse().slice(0, 8);
            } else {
                peliculasSeccion = globalData.filter(p => p.genero.some(g => g.toLowerCase() === key)).reverse().slice(0, 8);
            }
        }

        // Create Cards
        peliculasSeccion.forEach(pelicula => {
            const card = createCardElement(pelicula);
            carrusel.appendChild(card);
        });

        contenedorCarrusel.appendChild(btnLeft);
        contenedorCarrusel.appendChild(carrusel);
        contenedorCarrusel.appendChild(btnRight);

        // Scroll Events
        btnLeft.addEventListener("click", () => carrusel.scrollBy({ left: -300, behavior: "smooth" }));
        btnRight.addEventListener("click", () => carrusel.scrollBy({ left: 300, behavior: "smooth" }));

        seccionDiv.appendChild(contenedorCarrusel);
        main.appendChild(seccionDiv);
    });
};

/**
 * Renderiza la sección "Continuar viendo" si hay items en progreso.
 */
function renderContinueWatching(container) {
    const progressData = getAllProgress();
    const keys = Object.keys(progressData);

    if (keys.length === 0) return; // No hay nada viendo

    // Filtrar items válidos y ordenarlos por timestamp (más reciente primero)
    // También validamos que el item sigan existiendo en globalData (por si se borró del catálogo)
    // Nota: El key del progreso es `titulo_fecha`, pero puede ser `titulo_fecha` de un episodio.
    // Necesitamos mapearlo al objeto del catálogo real para tener datos frescos (imagen, etc)

    const continueItems = [];

    keys.forEach(key => {
        const itemProgreso = progressData[key];

        // Si no tiene timestamp, es data vieja o inválida (aunque la migración debió arreglarlo)
        if (!itemProgreso || typeof itemProgreso !== 'object') return;

        // Buscamos coincidencia en globalData
        // Caso 1: Película. El ID key coincide con generateId(p)
        // Caso 2: Serie. El ID key es del episodio, pero necesitamos la SERIE padre.
        //   Pero espera, saveVideoProgress usa `videoId`.
        //   Para peliculas: titulo_fecha
        //   Para series: tituloEpisodio_fechaSerie (WAIT! let's check initPlayer)

        // En `iniciarReproduccion`: videoId = tituloObra.replace... + fechaObra
        // Si es Serie, tituloObra viene como "T1:E1 - TituloEp".
        // Esto hace difícil encontrar la serie original solo con el ID del video si no guardamos metadata extra.
        // Afortunadamente, agregamos `metadata` en el paso anterior.

        // Si tenemos metadata, USAMOS ESO. Es lo más seguro.
        if (itemProgreso.titulo) {
            // Es un objeto rico creado por nuestro nuevo código
            continueItems.push({
                id: key,
                ...itemProgreso
            });
        } else {
            // Fallback para items viejos (si los hubiera) - Intento "best effort"
            // Por simplicidad, si es muy viejo y no tiene metadata, tal vez no lo mostramos o mostramos sin foto.
            // Omitimos legacy sin metadata para evitar UI rota.
        }
    });

    // Ordenar: Más reciente al inicio
    continueItems.sort((a, b) => b.timestamp - a.timestamp);

    // LIMITAR A 5 ITEMS (Requerimiento de usuario)
    const itemsToRender = continueItems.slice(0, 5);

    if (itemsToRender.length === 0) return;

    // --- RENDERIZADO UI ---

    const seccionDiv = document.createElement("div");
    seccionDiv.classList.add("seccion-catalogo", "seccion-continue-watching");

    // Header
    const headerSeccion = document.createElement("div");
    headerSeccion.classList.add("header-seccion");

    const tituloSeccion = document.createElement("h2");
    tituloSeccion.textContent = "Continuar viendo";
    headerSeccion.appendChild(tituloSeccion);
    seccionDiv.appendChild(headerSeccion);

    // Carousel Container
    const contenedorCarrusel = document.createElement("div");
    contenedorCarrusel.classList.add("carrusel-container");

    const carrusel = document.createElement("div");
    carrusel.classList.add("carrusel");
    // Nota: Usamos las mismas clases para heredar estilos de scroll, pero las tarjetas serán diferentes

    itemsToRender.forEach(item => {
        // Buscar el objeto real en globalData para asegurar acciones al click (como abrir modal de serie)
        // El titulo en metadata para series es "Stranger Things" (subtitulo) o el del episodio?
        // En `configurarEventosPlyr` pasamos: 
        // metadata.titulo = tituloObra (que es "T1:E1 - TituloEp")
        // metadata.subtitulo = contexto.serie.titulo ("Stranger Things")

        // Para buscar en catálogo:
        const tituloBusqueda = item.esSerie ? item.subtitulo : item.titulo;

        // Intentamos encontrar el objeto maestro
        const dataMaestra = globalData.find(d => d.titulo === tituloBusqueda) ||
            globalData.find(d => d.titulo === item.titulo); // Fallback peli

        if (dataMaestra) {
            // Usamos la imagen `continue_watching` del JSON si existe, si no backdrop, si no portada
            // OJO: dataMaestra tiene la URL `continue_watching` actualizada.

            const card = createBackdropCard(dataMaestra, item);
            carrusel.appendChild(card);
        }
    });

    // === BOTONES DE SCROLL (Añadido por solicitud responsive) ===
    const btnLeft = document.createElement("button");
    btnLeft.classList.add("scroll-btn", "left");
    btnLeft.innerHTML = "&#10094;";

    const btnRight = document.createElement("button");
    btnRight.classList.add("scroll-btn", "right");
    btnRight.innerHTML = "&#10095;";

    // Eventos de Scroll
    btnLeft.addEventListener("click", () => carrusel.scrollBy({ left: -300, behavior: "smooth" }));
    btnRight.addEventListener("click", () => carrusel.scrollBy({ left: 300, behavior: "smooth" }));

    contenedorCarrusel.appendChild(btnLeft);
    contenedorCarrusel.appendChild(carrusel);
    contenedorCarrusel.appendChild(btnRight);

    seccionDiv.appendChild(contenedorCarrusel);

    container.appendChild(seccionDiv);
}

/**
 * Crea tarjeta formato Backdrop con barra de progreso
 */
function createBackdropCard(dataCatalogo, progressItem) {
    const card = document.createElement("div");
    card.classList.add("tarjeta", "tarjeta-backdrop"); // Clase adicional para CSS específico

    // Imagen: Prioridad -> continue_watching > backdrop > portada
    const imageSrc = dataCatalogo.continue_watching || dataCatalogo.backdrop || dataCatalogo.portada;

    // Texto: Si es serie, mostramos "T1:E1". Si es peli, el año.
    let infoTexto = "";
    if (progressItem.esSerie && progressItem.temporadaStr) {
        infoTexto = progressItem.temporadaStr;
    } else if (!progressItem.esSerie && dataCatalogo.fecha) {
        // Extraemos solo el año si la fecha es completa (YYYY-MM-DD o similar)
        // Asumimos que dataCatalogo.fecha puede ser "2024" o "2024-05-20"
        infoTexto = dataCatalogo.fecha.split("-")[0];
    }

    // Porcentaje (Si duration es 0, asumimos 0%)
    const percent = progressItem.duration > 0 ? Math.min(100, Math.max(0, (progressItem.time / progressItem.duration) * 100)) : 0;

    // --- BTN ELIMINAR (NUEVO) ---
    // Se inserta dentro de img-container para que quede sobre la imagen
    card.innerHTML = `
      <div class="img-container">
          <img src="${imageSrc}" alt="${dataCatalogo.titulo}">
          <div class="card-play-overlay"><span class="play-icon">▶</span></div>
          
          <div class="progress-bar-container">
            <div class="progress-bar-fill" style="width: ${percent}%;"></div>
          </div>

          <div class="card-delete-btn" title="Eliminar de Continuar viendo">
             <img src="Multimedia/clear.svg" alt="Eliminar">
          </div>
      </div>
      
      <div class="contenido-backdrop">
        <h3>${dataCatalogo.titulo}</h3>
        ${infoTexto ? `<p class="episodio-info">${infoTexto}</p>` : ''}
      </div>
    `;

    // --- FUNCIONALIDAD ELIMINAR ---
    const btnDelete = card.querySelector(".card-delete-btn");
    if (btnDelete) {
        btnDelete.addEventListener("click", (e) => {
            e.preventDefault();
            e.stopPropagation(); // Evitar abrir el modal

            // 1. Borrar progreso
            removeVideoProgress(progressItem.id); // Usamos el ID original del progreso

            // 2. Identificar el contenedor ANTES de borrar la tarjeta
            // Esto es crucial porque card.parentNode se pierde al hacer remove()
            const container = card.parentElement;

            // 3. Eliminar UI
            card.remove();

            // 4. Verificar si quedó vacía la sección USANDO EL CONTENEDOR CAPTURADO
            if (container && container.children.length === 0) {
                // Buscamos la sección completa (padre del carrusel container, padre del carrusel)
                const seccion = container.closest(".seccion-continue-watching");
                if (seccion) seccion.remove();
            }

            // 5. Feedback
            mostrarToast("Obra eliminada de la sección");
        });
    }


    // --- EVENTOS DE TARJETA ---

    // 1. Click Normal (Mobile y Desktop)
    card.addEventListener("click", () => {
        // En móvil, si estamos en modo "edición" (mostrando delete), el click debería cancelar ese modo o abrir?
        // La solicitud dice: "mantener presionada... para que aparezca el tache."
        // Usualmente un tap fuera o un tap simple limpia el estado.
        // Vamos a hacer que si tiene la clase show-delete, el clic solo la quita.
        if (card.classList.contains("show-delete")) {
            card.classList.remove("show-delete");
            return;
        }

        abrirModal(dataCatalogo);
    });

    // 2. Long Press para Móvil (touchstart / touchend)
    let pressTimer;

    card.addEventListener("touchstart", (e) => {
        // Iniciar timer
        pressTimer = setTimeout(() => {
            // Acción al mantener presionado
            card.classList.add("show-delete");
            // Vibración si es soportada (feedback háptico)
            if (navigator.vibrate) navigator.vibrate(50);
        }, 600); // 600ms para considerar long press
    }, { passive: true });

    card.addEventListener("touchend", (e) => {
        clearTimeout(pressTimer);
    });

    card.addEventListener("touchmove", (e) => {
        // Si mueve el dedo, cancelamos el long press
        clearTimeout(pressTimer);
    });

    // Cancelar menú contextual por defecto en móvil para evitar que salga el del navegador
    card.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        // También podemos activar aquí el modo delete por si usan click derecho en híbridos
        // card.classList.add("show-delete");
        return false;
    });

    return card;
}

window.mostrarGrid = function (titulo, tipo) {
    const main = document.querySelector("main");

    // Filter Items
    const elementos = globalData.filter(item => item.tipo === tipo).reverse();
    const totalItems = elementos.length;

    main.innerHTML = `
        <section class="genero-main">
          <h1 id="titulo-genero">${titulo}</h1>
          <p class="contador-titulo" id="contador-animado">(0)</p>
          <div id="grid-genero" class="grid-genero"></div>
        </section>
    `;

    // Animate Counter
    const objContador = document.getElementById("contador-animado");
    const animateValue = (obj, start, end, duration) => {
        let startTimestamp = null;
        const step = (timestamp) => {
            if (!startTimestamp) startTimestamp = timestamp;
            const progress = Math.min((timestamp - startTimestamp) / duration, 1);
            obj.innerHTML = `(${Math.floor(progress * (end - start) + start)})`;
            if (progress < 1) window.requestAnimationFrame(step);
        };
        window.requestAnimationFrame(step);
    };
    if (totalItems > 0) animateValue(objContador, 0, totalItems, 800);
    else objContador.style.display = 'none';

    // Render Grid
    const grid = main.querySelector("#grid-genero");
    if (totalItems === 0) {
        grid.innerHTML = `<p style="text-align:center;">No se encontraron ${tipo.toLowerCase()}s.</p>`;
        return;
    }
    elementos.forEach(item => grid.appendChild(createCardElement(item)));
};

window.mostrarGenero = function (generoParam) {
    const main = document.querySelector("main");
    const generoNombre = decodeURIComponent(generoParam).replace("_", " ");
    const generoKey = generoNombre.toLowerCase();

    // Filter
    const generoAliases = { "suspenso": ["suspenso", "suspense"] };
    const peliculasFiltradas = globalData.filter(p =>
        p.genero.some(g => {
            const gLower = g.toLowerCase();
            return (generoAliases[generoKey] && generoAliases[generoKey].includes(gLower)) || gLower === generoKey;
        })
    ).reverse();

    // Render
    main.innerHTML = `
        <section class="genero-main">
          <h1 id="titulo-genero">${generoNombre.charAt(0).toUpperCase() + generoNombre.slice(1)}</h1>
          <div id="grid-genero" class="grid-genero"></div>
        </section>
    `;

    const grid = main.querySelector("#grid-genero");
    peliculasFiltradas.forEach(pelicula => grid.appendChild(createCardElement(pelicula)));

    // Update Stars if needed
    if (typeof actualizarEstrellasVisibles === 'function') actualizarEstrellasVisibles();
};


window.mostrarPlanes = function () {
    const main = document.querySelector("main");
    const menubar = document.querySelector(".menubar");
    if (menubar) menubar.classList.add("scrolled");

    // Hide Hero
    const hero = document.querySelector(".hero");
    if (hero) hero.style.display = "none";

    let username = "Invitado";
    let userRole = "free";
    try {
        const userStr = localStorage.getItem('vanacue_user');
        if (userStr) {
            const user = JSON.parse(userStr);
            if (user.username) username = user.username;
            if (user.role) userRole = user.role;
        }
    } catch (e) {
        console.error("Error retrieving user", e);
    }

    const isPremium = userRole === 'premium' || userRole === 'admin';
    const premiumBtnHtml = isPremium
        ? `<button class="plan-btn disabled">Ya lo tienes</button>`
        : `<button id="btn-request-premium" class="plan-btn primary">Lo quiero</button>`;

    main.innerHTML = `
    <section class="planes-container">
        <!-- PLAN FREE -->
        <div class="plan-card">
            <h3 class="plan-title">Free</h3>
            <div class="plan-price">$0 <span>/mes</span></div>
            <ul class="plan-features">
                <li>Acceso a 5 películas en streaming</li>
                <li>Acceso a 2 series en streaming</li>
            </ul>
            <button class="plan-btn disabled">Ya lo tienes</button>
        </div>

        <!-- PLAN PREMIUM -->
        <div class="plan-card premium">
            <h3 class="plan-title" style="color: #e50914;">Premium</h3>
            <div class="plan-price">$49 <span>MXN/mes</span></div>
            <ul class="plan-features">
                <li>Acceso a contenido nuevo en FHD</li>
                <li>Acceso ILIMITADO al contenido</li>
                <li>Prioridad en pedidos y subidas</li>
            </ul>
            ${premiumBtnHtml}
        </div>
    </section>
    `;

    // Logic for Premium Button
    const btnPremium = document.getElementById("btn-request-premium");
    if (btnPremium) {
        btnPremium.addEventListener("click", () => {
            // Generate Message
            const message = `¡Hola! soy el usuario ${username}, quisiera mejorar mi plan de Vanacue, espero más información.`;

            // Open Telegram with pre-filled message
            const telegramUrl = `https://t.me/llzkxrll?text=${encodeURIComponent(message)}`;
            window.open(telegramUrl, "_blank");
        });
    }
};

window.mostrarFavoritos = function () {
    const main = document.querySelector("main");
    const menubar = document.querySelector(".menubar");
    const hero = document.querySelector(".hero");

    // Desactivar listener de scroll para que no parpadee el menú
    // (Ya lo hace renderView, pero por seguridad)
    if (menubar) menubar.classList.add("scrolled");
    if (hero) hero.style.display = "none";

    // Renderizar Estructura
    main.innerHTML = `
                <section class="seccion-favoritos" style="padding-top: 120px;"> 
      <h2>Mi Lista</h2>
      <div id="grid-favoritos-spa" class="grid-genero"></div>
    </section>
                `;

    const grid = document.getElementById("grid-favoritos-spa");
    window.renderizarFavoritosInto(grid);
};

window.renderizarFavoritosInto = function (grid) {
    if (!grid) return;

    grid.innerHTML = '<div class="spinner"></div>'; // Loading state

    // Promise.all to ensure we have Data AND Favorites loaded
    Promise.all([dataPromise, cargarFavoritos()])
        .then(([catalogo]) => {
            console.log("SPA: Renderizando favoritos...");
            grid.innerHTML = ""; // Limpiar loader

            if (misFavoritos.size === 0) {
                grid.innerHTML = `
                <div class="mensaje-vacio-container">
                    <div class="mensaje-vacio-icono">🍿</div>
                        <h3 class="mensaje-vacio-titulo">Tu lista está vacía</h3>
                        <p class="mensaje-vacio-texto">
                            Aún no has guardado películas o series.<br>
                            ¡Explora el catálogo y marca tus favoritas!
                        </p>
                </div>
                `;
                return;
            }

            // === RESPETAR ORDEN DE AGREGADO (API) ===
            let contenidoFavorito = [];

            if (window.misFavoritosOrdenados && window.misFavoritosOrdenados.length > 0) {
                contenidoFavorito = window.misFavoritosOrdenados.map(favId => {
                    return catalogo.find(item => {
                        const itemId = item.tmdbId || generateId(item);
                        return String(itemId) === String(favId);
                    });
                }).filter(item => item !== undefined);
            } else {
                contenidoFavorito = catalogo.filter(item => {
                    const id = item.tmdbId || generateId(item);
                    return misFavoritos.has(id) || misFavoritos.has(Number(id)) || misFavoritos.has(String(id));
                });
            }

            if (contenidoFavorito.length === 0) {
                grid.innerHTML = `<p style='text-align:center; color:#777;'>Tienes favoritos guardados, pero no coinciden con el catálogo actual.</p>`;
                return;
            }

            contenidoFavorito.forEach(item => {
                const card = createCardElement(item);
                grid.appendChild(card);
            });
        })
        .catch(err => {
            console.error("Error SPA Favoritos:", err);
            grid.innerHTML = "<p style='text-align:center; color:#777;'>Error al cargar datos.</p>";
        });
};

// ==========================================
// SECCIÓN DE RESEÑAS
// ==========================================

// ==========================================
// SECCIÓN DE RESEÑAS CON PAGINACIÓN
// ==========================================

let reviewsCurrentPage = 1;
const REVIEWS_PER_PAGE = 3;

window.mostrarReseñas = function () {
    const main = document.querySelector("main");
    const menubar = document.querySelector(".menubar");
    if (menubar) menubar.classList.add("scrolled");

    // Hide Hero
    const hero = document.querySelector(".hero");
    if (hero) hero.style.display = "none";

    // User Role Info
    const userStr = localStorage.getItem('vanacue_user');
    const user = userStr ? JSON.parse(userStr) : { username: 'Invitado', role: 'free' };
    const isPremium = user.role === 'premium' || user.role === 'admin';

    // 1. BANNER DINÁMICO
    let bannerHtml = "";
    if (!isPremium) {
        bannerHtml = `
            <div class="review-banner">
                <div class="banner-content">
                    <img src="Multimedia/info.svg" alt="Plus" class="banner-icon">
                    <div class="banner-text">
                        <h3>¿Quieres compartir tu opinión?</h3>
                        <p>Solo los miembros con suscripción <span class="plus-highlight">Premium</span> pueden escribir, puntuar y comentar contenido. ¡Únete a Vanacue Premium hoy!</p>
                    </div>
                </div>
                <button class="btn-banner-plans" onclick="window.navigateTo('plans')">VER PLAN PREMIUM</button>
            </div>
        `;
    } else {
        bannerHtml = `
            <div class="review-banner banner-plus">
                <div class="banner-content">
                    <img src="Multimedia/info.svg" alt="Plus" class="banner-icon">
                    <div class="banner-text">
                        <h3>Funcionamiento de reseñas</h3>
                    </div>
                </div>
                <div class="plus-instructions-grid">
                    <div class="plus-col">
                        <div class="inst-item"><span class="inst-num">1</span> Selecciona la obra que quieras puntuar y da click en el "lápiz".</div>
                        <div class="inst-item"><span class="inst-num">2</span> Puntúa de 1 a 5 estrellas.</div>
                        <div class="inst-item"><span class="inst-num">3</span> Redacta, no uses palabras antisonantes ni spoilers.</div>
                    </div>
                    <div class="plus-col">
                        <div class="inst-item"><span class="inst-num">4</span> Publica tu reseña.</div>
                        <div class="inst-item"><span class="inst-num">5</span> Espera aprobación por parte de la administración.</div>
                        <div class="inst-item"><span class="inst-num">6</span> Una vez aprobada, puedes compartirla en tus redes sociales.</div>
                    </div>
                </div>
            </div>
        `;
    }

    // 2. POPULARES AHORA (Artículos con popular: true) - Orden más reciente agregado
    const populares = (typeof globalData !== 'undefined' ? globalData : [])
        .filter(p => p.popular === true)
        .reverse()
        .slice(0, 4);
    let popularesHtml = populares.map(p => {
        const pJson = JSON.stringify(p).replace(/'/g, "&apos;");
        return `
            <div class="sidebar-movie-card" onclick='abrirModal(${pJson})'>
                <div class="img-container">
                    <img src="${p.portada}" alt="${p.titulo}">
                </div>
                <div class="movie-mini-info">
                    <h4>${p.titulo}</h4>
                    <p>${p.calificacion} ★</p>
                </div>
            </div>
        `;
    }).join("");

    const adminSection = user.role === 'admin' ? `
        <div class="admin-moderation-section">
            <div class="admin-header">
                <h2>Panel de Moderación <span class="admin-badge">ADMIN</span></h2>
                <p>Reseñas pendientes de aprobación.</p>
            </div>
            <div id="admin-moderation-panel" class="moderation-grid">
                <div class="loading-spinner">Cargando pendientes...</div>
            </div>
        </div>
    ` : "";

    main.innerHTML = `
        <div class="seccion-reviews">
            <div class="reviews-header-info">
                <h1>Reseñas de la Comunidad</h1>
                <p>Descubre las opiniones sobre los estrenos más recientes y los clásicos de siempre.</p>
            </div>

            ${adminSection}
            ${bannerHtml}

            <div class="reviews-main-grid">
                <aside class="reviews-sidebar">
                    <h2>Populares ahora <span class="ver-todo" onclick="window.navigateTo('home')">Ver todo</span></h2>
                    <div class="sidebar-cards">
                        ${popularesHtml}
                    </div>
                </aside>

                <section class="reviews-content-area">
                    <h2>Últimas reseñas <span class="recientes-filter">Recientes ▾</span></h2>
                    <div class="reviews-search-wrapper">
                        <input type="text" id="reviews-search-input" class="reviews-search-input" placeholder="Buscar por película o usuario...">
                    </div>
                    <div id="paginated-reviews-container">
                        <!-- Aquí se inyectan las reseñas paginadas -->
                    </div>
                </section>
            </div>
        </div>
    `;

    // Renderizar primera página de reseñas públicas
    window.renderPaginatedReviews(1);

    // Botón de ordenamiento Recientes
    setTimeout(() => {
        const filtroBtn = document.querySelector('.recientes-filter');
        if (filtroBtn) {
            filtroBtn.onclick = () => {
                reviewsSortOrder = reviewsSortOrder === 'DESC' ? 'ASC' : 'DESC';
                filtroBtn.textContent = reviewsSortOrder === 'DESC' ? 'Recientes ▾' : 'Antiguas ▴';
                filtroBtn.style.color = reviewsSortOrder === 'ASC' ? '#e50914' : '';
                window.renderPaginatedReviews(1);
            };
        }

        // Buscador de reseñas (filtra tarjetas visibles por título y username)
        const searchInput = document.getElementById('reviews-search-input');
        if (searchInput) {
            searchInput.addEventListener('input', () => {
                const query = searchInput.value.trim().toLowerCase();
                const cards = document.querySelectorAll('.review-card');
                cards.forEach(card => {
                    const title = (card.querySelector('.review-movie-title')?.textContent || '').toLowerCase();
                    const user = (card.querySelector('.user-meta h4')?.textContent || '').toLowerCase();
                    card.style.display = (!query || title.includes(query) || user.includes(query)) ? '' : 'none';
                });
                // Mostrar mensaje si no hay resultados
                const container = document.getElementById('paginated-reviews-container');
                if (container) {
                    let noResults = container.querySelector('.no-search-results');
                    const visibles = [...cards].filter(c => c.style.display !== 'none');
                    if (query && visibles.length === 0) {
                        if (!noResults) {
                            noResults = document.createElement('div');
                            noResults.className = 'no-search-results';
                            noResults.style.cssText = 'padding:2rem; text-align:center; color:#555; font-size:0.95rem;';
                            noResults.textContent = `No hay reseñas que coincidan con "${searchInput.value}"`;
                            container.appendChild(noResults);
                        }
                    } else if (noResults) {
                        noResults.remove();
                    }
                }
            });
        }
    }, 100);

    // Si es admin, renderizar panel de moderación
    if (user.role === 'admin') {
        window.renderAdminModerationPanel();
    }
};

let openDiscussionIndex = null; // Trackea qué discusión está abierta
let reviewsSortOrder = 'DESC'; // 'DESC' = más reciente, 'ASC' = más antiguo

window.renderPaginatedReviews = async function (page) {
    const container = document.getElementById('paginated-reviews-container');
    if (!container) return;

    reviewsCurrentPage = page;

    try {
        const REVIEWS_PER_PAGE = 10;
        const limit = REVIEWS_PER_PAGE;
        const token = localStorage.getItem('vanacue_token');
        const response = await fetch(`${API_URL}/api/reviews?page=${page}&limit=${limit}&order=${reviewsSortOrder}`, {
            headers: token ? { 'Authorization': `Bearer ${token}` } : {}
        });
        const data = await response.json();

        if (!data.success || !data.reviews) {
            container.innerHTML = '<div style="padding:20px; text-align:center; color:#888;">No hay reseñas disponibles aún.</div>';
            return;
        }

        const reviews = data.reviews;

        if (reviews.length === 0 && page === 1) {
            container.innerHTML = '<div style="padding:20px; text-align:center; color:#888;">No hay reseñas disponibles aún.</div>';
            return;
        }

        // Generar HTML de paginación
        let paginationHtml = `<div class="reviews-pagination">`;
        if (page > 1) {
            paginationHtml += `<button onclick="window.renderPaginatedReviews(${page - 1})">Anterior</button>`;
        }
        if (reviews.length === limit) {
            paginationHtml += `<button onclick="window.renderPaginatedReviews(${page + 1})">Siguiente</button>`;
        }
        paginationHtml += `</div>`;

        const currentUserRole = (() => { try { return JSON.parse(localStorage.getItem('vanacue_user') || '{}').role; } catch (e) { return null; } })();
        const isAdmin = currentUserRole === 'admin';

        let reviewsHtml = reviews.map((r, idx) => {
            const isLiked = r.user_has_liked === 1;
            const isDisliked = r.user_has_disliked === 1;
            const isCommented = false;
            const isExpanded = openDiscussionIndex === r.id;

            return `
            <div class="review-card ${isExpanded ? 'is-expanded' : ''}" data-id="${r.id}">
                <div class="review-card-header">
                    <div class="user-info-row">
                        <img src="Multimedia/Profiles/${r.profile_pic || 'alucard.jpg'}" alt="Avatar" class="user-avatar" onerror="this.src='Multimedia/logo.png'">
                        <div class="user-meta">
                            <h4>${r.username}</h4>
                            <p>Reseñado el ${new Date(r.created_at).toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' })}</p>
                        </div>
                    </div>
                    <div class="review-stars">
                        ${Array(5).fill(0).map((_, i) => `<img src="Multimedia/star_r.svg" class="star-icon ${i >= r.rating ? 'empty' : ''}">`).join("")}
                    </div>
                </div>
                <div class="review-movie-title">${r.movie_title} (${r.movie_year})</div>
                <p class="review-comment">"${r.comment}"</p>
                <div class="review-card-footer">
                    <div class="footer-action" onclick="window.toggleReviewLike(${r.id})">
                        <img src="Multimedia/${isLiked ? 'like_2.svg' : 'like_1.svg'}" class="footer-icon-svg ${isLiked ? 'active' : ''}">
                        <span class="like-count">${r.likes}</span>
                    </div>
                    <div class="footer-action" onclick="window.toggleReviewDislike(${r.id})">
                        <img src="Multimedia/${isDisliked ? 'dislike_2.svg' : 'dislike_1.svg'}" class="footer-icon-svg ${isDisliked ? 'active' : ''}">
                        <span class="dislike-count">${r.dislikes}</span>
                    </div>
                    <div class="footer-action" onclick="window.toggleReviewComment(${r.id})">
                        <img src="Multimedia/${isCommented ? 'comment_2.svg' : 'comment_1.svg'}" class="footer-icon-svg ${isCommented ? 'active' : ''}">
                        <span>${r.comments_count}</span>
                    </div>
                    <div class="footer-action" onclick="window.openShareModalBackend(${r.id})">
                        <img src="Multimedia/share_r.svg" class="footer-icon-svg">
                        <span>Compartir</span>
                    </div>
                    ${isAdmin ? `<div class="footer-action footer-action-delete" onclick="window.deleteReview(${r.id})">
                        <img src="Multimedia/delete.svg" class="footer-icon-svg" onerror="this.style.display='none'">
                        <span>Eliminar</span>
                    </div>` : ''}
                </div>

                <div class="discussion-container" id="discussion-${r.id}" style="${isExpanded ? 'display:block' : 'display:none'}">
                    <!-- Área de Comentarios -->
                </div>
            </div>
            `;
        }).join("");

        // 1. Inyectar el HTML de las reseñas
        container.innerHTML = reviewsHtml + paginationHtml;

        // 2. Si hay una discusión abierta, cargar sus comentarios
        if (openDiscussionIndex !== null) {
            const discussionContainer = document.getElementById(`discussion-${openDiscussionIndex}`);
            if (discussionContainer) {
                renderDiscussionArea(openDiscussionIndex, discussionContainer);
            }
        }

        // 3. Sobrescribir los onclick de compartir para pasar el objeto completo
        reviews.forEach(r => {
            const card = container.querySelector(`.review-card[data-id="${r.id}"]`);
            if (card) {
                const shareBtn = card.querySelector('[onclick*="openShareModalBackend"]');
                if (shareBtn) shareBtn.onclick = (e) => { e.stopPropagation(); window.openShareModal(r); };
            }
        });

    } catch (e) {
        console.error("Error al cargar reseñas:", e);
        container.innerHTML = `<div style="padding:15px; text-align:center; color:#f00;">Error: ${e.message}</div>`;
    }
};

window.toggleReviewLike = async function (reviewId) {
    await handleReviewReaction(reviewId, 'like');
};

window.toggleReviewDislike = async function (reviewId) {
    await handleReviewReaction(reviewId, 'dislike');
};

async function handleReviewReaction(reviewId, type) {
    const token = localStorage.getItem('vanacue_token');
    if (!token) return mostrarToast("Inicia sesión para reaccionar.");

    const userStr = localStorage.getItem('vanacue_user');
    const userRole = userStr ? JSON.parse(userStr).role : 'free';
    if (userRole === 'free') {
        return mostrarToast("Necesitas suscripción premium para realizar esta acción.");
    }

    try {
        const response = await fetch(`${API_URL}/api/reviews/like`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ review_id: reviewId, type })
        });
        const data = await response.json();
        console.log('[Like] Server response:', data);
        if (data.success) {
            // Actualización quirúrgica del DOM
            const card = document.querySelector(`.review-card[data-id="${reviewId}"]`);
            if (card) {
                const footer = card.querySelector('.review-card-footer');
                const likeBtn = footer ? footer.querySelector('[onclick*="toggleReviewLike"]') : null;
                const dislikeBtn = footer ? footer.querySelector('[onclick*="toggleReviewDislike"]') : null;

                const likeCount = likeBtn ? likeBtn.querySelector('.like-count') : card.querySelector('.like-count');
                const dislikeCount = dislikeBtn ? dislikeBtn.querySelector('.dislike-count') : card.querySelector('.dislike-count');
                const likeIcon = likeBtn ? likeBtn.querySelector('.footer-icon-svg') : null;
                const dislikeIcon = dislikeBtn ? dislikeBtn.querySelector('.footer-icon-svg') : null;

                const newLikes = typeof data.likes === 'number' ? data.likes : parseInt(data.likes) || 0;
                const newDislikes = typeof data.dislikes === 'number' ? data.dislikes : parseInt(data.dislikes) || 0;

                if (likeCount) likeCount.innerText = newLikes;
                if (dislikeCount) dislikeCount.innerText = newDislikes;

                if (likeIcon) {
                    likeIcon.src = data.user_has_liked ? 'Multimedia/like_2.svg' : 'Multimedia/like_1.svg';
                    likeIcon.classList.toggle('active', !!data.user_has_liked);
                }
                if (dislikeIcon) {
                    dislikeIcon.src = data.user_has_disliked ? 'Multimedia/dislike_2.svg' : 'Multimedia/dislike_1.svg';
                    dislikeIcon.classList.toggle('active', !!data.user_has_disliked);
                }
            }
        } else {
            mostrarToast(data.message || 'Error al reaccionar.');
        }
    } catch (e) {
        console.error('[Like] Error:', e);
    }
}

window.deleteReview = async function (reviewId) {
    if (!confirm('¿Eliminar esta reseña? Esta acción no se puede deshacer.')) return;
    const token = localStorage.getItem('vanacue_token');
    if (!token) return;
    try {
        const response = await fetch(`${API_URL}/api/reviews/${reviewId}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();
        if (data.success) {
            const card = document.querySelector(`.review-card[data-id="${reviewId}"]`);
            if (card) {
                card.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
                card.style.opacity = '0';
                card.style.transform = 'scale(0.95)';
                setTimeout(() => card.remove(), 300);
            }
            mostrarToast('Reseña eliminada correctamente.');
        } else {
            mostrarToast(data.message || 'Error al eliminar.');
        }
    } catch (e) {
        console.error('[DeleteReview]', e);
        mostrarToast('Error de conexión.');
    }
};

window.formatRelativeDate = function (dateString) {
    const now = new Date();
    const date = new Date(dateString);
    const diffInSeconds = Math.floor((now - date) / 1000);

    if (diffInSeconds < 60) return 'hace unos segundos';

    const diffInMinutes = Math.floor(diffInSeconds / 60);
    if (diffInMinutes < 60) return `hace ${diffInMinutes} ${diffInMinutes === 1 ? 'minuto' : 'minutos'}`;

    const diffInHours = Math.floor(diffInMinutes / 60);
    if (diffInHours < 24) return `hace ${diffInHours} ${diffInHours === 1 ? 'hora' : 'horas'}`;

    const diffInDays = Math.floor(diffInHours / 24);
    if (diffInDays < 7) return `hace ${diffInDays} ${diffInDays === 1 ? 'día' : 'días'}`;

    return date.toLocaleDateString();
};

window.toggleReviewComment = function (reviewId) {
    const container = document.getElementById(`discussion-${reviewId}`);
    if (!container) return;

    if (openDiscussionIndex === reviewId) {
        // Cerrar
        openDiscussionIndex = null;
        container.style.display = 'none';
        document.querySelector(`.review-card[data-id="${reviewId}"]`).classList.remove('is-expanded');
    } else {
        // Abrir (y cerrar previa si hubiera)
        if (openDiscussionIndex !== null) {
            const prev = document.getElementById(`discussion-${openDiscussionIndex}`);
            if (prev) prev.style.display = 'none';
            const prevCard = document.querySelector(`.review-card[data-id="${openDiscussionIndex}"]`);
            if (prevCard) prevCard.classList.remove('is-expanded');
        }

        openDiscussionIndex = reviewId;
        container.style.display = 'block';
        document.querySelector(`.review-card[data-id="${reviewId}"]`).classList.add('is-expanded');
        renderDiscussionArea(reviewId, container);
    }
};

async function renderDiscussionArea(reviewId, container, shouldScroll = false) {
    try {
        const response = await fetch(`${API_URL}/api/reviews/${reviewId}/comments`);
        const data = await response.json();

        const comments = data.success ? data.comments : [];
        const userStr = localStorage.getItem('vanacue_user');
        let currentUserPic = 'alucard.jpg';
        if (userStr) {
            try {
                const u = JSON.parse(userStr);
                currentUserPic = u.profile_pic || 'alucard.jpg';
            } catch (e) { }
        }

        container.innerHTML = `
            <div class="comments-list-wrapper custom-scrollbar" id="comments-wrapper-${reviewId}">
                <div class="comments-list" id="comments-list-${reviewId}">
                    ${(() => {
                const userStr = localStorage.getItem('vanacue_user');
                const userData = userStr ? JSON.parse(userStr) : null;
                const currentUserName = userData ? userData.username : null;
                const currentUserRole = userData ? userData.role : null;

                return comments.map(c => {
                    const isAdmin = c.role === 'admin';
                    const isMe = currentUserName && c.username === currentUserName;
                    const canDelete = currentUserRole === 'admin';

                    // Forzar interpretación como UTC si viene de SQLite sin indicador
                    const dateStr = c.created_at.includes('T') ? c.created_at : c.created_at.replace(' ', 'T') + 'Z';
                    const d = new Date(dateStr);
                    const months = ["Ene.", "Feb.", "Mar.", "Abr.", "May.", "Jun.", "Jul.", "Ago.", "Sep.", "Oct.", "Nov.", "Dic."];
                    const day = d.getDate();
                    const month = months[d.getMonth()];
                    const year = d.getFullYear();

                    let hours = d.getHours();
                    const ampm = hours >= 12 ? 'pm' : 'am';
                    hours = hours % 12 || 12;
                    const minutes = d.getMinutes().toString().padStart(2, '0');
                    const formattedDate = `${day} ${month} a las ${hours}:${minutes} ${ampm} ${year}`;
                    return `
                        <div class="comment-item ${isAdmin ? 'is-admin' : ''} ${isMe ? 'is-me' : ''}">
                            <div class="comment-user-info">
                                <img src="Multimedia/Profiles/${c.profile_pic || 'alucard.jpg'}" alt="Avatar" class="comment-avatar" onerror="this.src='Multimedia/logo.png'">
                                <div class="comment-user-text">
                                    <div class="comment-user-row">
                                        <span class="comment-user">${c.username}</span>
                                        ${isAdmin ? '<span class="comment-admin-badge">ADMIN</span>' : ''}
                                    </div>
                                </div>
                            </div>
                            <div class="comment-content-row">
                                <div class="comment-bubble">
                                    <span class="comment-text">${c.comment}</span>
                                </div>
                                ${canDelete ? `<button class="btn-comment-delete" title="Eliminar Comentario" onclick="window.deleteComment(${c.id}, ${reviewId})">Eliminar</button>` : ''}
                            </div>
                            <span class="comment-date">${formattedDate}</span>
                        </div>
                    `;
                }).join("");
            })()}
                </div>
            </div>
            <div class="reply-area">
                <div class="reply-main">
                    <img src="Multimedia/Profiles/${currentUserPic}" alt="Tu Avatar" class="reply-avatar" onerror="this.src='Multimedia/logo.png'">
                    <div class="reply-input-wrapper">
                        <textarea placeholder="Añadir un comentario..." id="reply-input-${reviewId}" oninput="this.style.height = ''; this.style.height = this.scrollHeight + 'px'"></textarea>
                    </div>
                </div>
                <div class="reply-actions" id="reply-actions-${reviewId}">
                    <button class="btn-reply-cancel" onclick="window.toggleReviewComment(${reviewId})">Cancelar</button>
                    <button class="btn-reply-send" id="btn-reply-send-${reviewId}" onclick="window.postComment(${reviewId})">Responder</button>
                </div>
            </div>
        `;
        container.style.display = 'block';

        if (shouldScroll) {
            setTimeout(() => {
                const wrapper = document.getElementById(`comments-wrapper-${reviewId}`);
                if (wrapper) wrapper.scrollTop = wrapper.scrollHeight;
            }, 100);
        }
    } catch (e) {
        console.error(e);
    }
}

window.postComment = async function (reviewId) {
    const input = document.getElementById(`reply-input-${reviewId}`);
    const btnSend = document.getElementById(`btn-reply-send-${reviewId}`);
    const comment = input.value.trim();
    if (!comment) return;

    const token = localStorage.getItem('vanacue_token');
    if (!token) return mostrarToast("Inicia sesión para comentar.");

    const userStr = localStorage.getItem('vanacue_user');
    const userRole = userStr ? JSON.parse(userStr).role : 'free';
    if (userRole === 'free') {
        return mostrarToast("Necesitas suscripción premium para realizar esta acción.");
    }

    try {
        if (btnSend) {
            btnSend.disabled = true;
            btnSend.innerText = "...";
        }

        const response = await fetch(`${API_URL}/api/reviews/comment`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ review_id: reviewId, comment })
        });
        const data = await response.json();
        if (data.success) {
            input.value = '';
            const list = document.getElementById(`comments-list-${reviewId}`);
            if (list) {
                const isAdmin = data.comment_data.role === 'admin';
                const userStr = localStorage.getItem('vanacue_user');
                const userData = userStr ? JSON.parse(userStr) : null;
                const canDelete = userData && userData.role === 'admin';

                const d = new Date();
                const months = ["Ene.", "Feb.", "Mar.", "Abr.", "May.", "Jun.", "Jul.", "Ago.", "Sep.", "Oct.", "Nov.", "Dic."];
                const day = d.getDate();
                const month = months[d.getMonth()];
                const year = d.getFullYear();

                let hours = d.getHours();
                const ampm = hours >= 12 ? 'pm' : 'am';
                hours = hours % 12 || 12;
                const minutes = d.getMinutes().toString().padStart(2, '0');
                const formattedDate = `${day} ${month} a las ${hours}:${minutes} ${ampm} ${year}`;

                const newCommentHtml = `
                    <div class="comment-item ${isAdmin ? 'is-admin' : ''} is-me" style="opacity:0; transform:translateY(10px); transition:all 0.3s ease;">
                        <div class="comment-user-info">
                            <img src="Multimedia/Profiles/${data.comment_data.profile_pic || 'alucard.jpg'}" alt="Avatar" class="comment-avatar" onerror="this.src='Multimedia/logo.png'">
                            <div class="comment-user-text">
                                <div class="comment-user-row">
                                    <span class="comment-user">${data.comment_data.username}</span>
                                    ${isAdmin ? '<span class="comment-admin-badge">ADMIN</span>' : ''}
                                </div>
                            </div>
                        </div>
                        <div class="comment-content-row">
                            <div class="comment-bubble">
                                <span class="comment-text">${data.comment_data.comment}</span>
                            </div>
                            ${canDelete ? `<button class="btn-comment-delete" title="Eliminar Comentario" onclick="window.deleteComment(${data.comment_data.id}, ${reviewId})">Eliminar</button>` : ''}
                        </div>
                        <span class="comment-date">${formattedDate}</span>
                    </div>
                `;
                list.insertAdjacentHTML('beforeend', newCommentHtml);

                if (btnSend) {
                    btnSend.disabled = false;
                    btnSend.innerText = "Responder";
                }

                // Animación de entrada
                const newEl = list.lastElementChild;
                setTimeout(() => {
                    newEl.style.opacity = '1';
                    newEl.style.transform = 'translateY(0)';
                }, 10);

                // Scroll suave al nuevo comentario
                const wrapper = document.getElementById(`comments-wrapper-${reviewId}`);
                if (wrapper) {
                    wrapper.scrollTo({
                        top: wrapper.scrollHeight,
                        behavior: 'smooth'
                    });
                }

                // Actualizar contador en el footer
                const card = document.querySelector(`.review-card[data-id="${reviewId}"]`);
                if (card) {
                    const commentCountSpan = card.querySelector('.footer-action:nth-child(3) span');
                    if (commentCountSpan) {
                        const currentCount = parseInt(commentCountSpan.innerText) || 0;
                        commentCountSpan.innerText = currentCount + 1;
                    }
                }
            }
        } else {
            mostrarToast(data.message);
            if (btnSend) {
                btnSend.disabled = false;
                btnSend.innerText = "Responder";
            }
        }
    } catch (e) {
        console.error(e);
        if (btnSend) {
            btnSend.disabled = false;
            btnSend.innerText = "Responder";
        }
    }
};

window.renderAdminModerationPanel = async function () {
    const container = document.getElementById('admin-moderation-panel');
    if (!container) return;

    const token = localStorage.getItem('vanacue_token');
    if (!token) return;

    try {
        const response = await fetch(`${API_URL}/api/admin/reviews/pending`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();

        if (!data.success || data.reviews.length === 0) {
            container.innerHTML = '<div class="no-pending">No hay reseñas pendientes.</div>';
            return;
        }

        container.innerHTML = data.reviews.map(r => `
            <div class="moderation-card" id="mod-card-${r.id}">
                <div class="mod-card-header">
                    <img src="Multimedia/Profiles/${r.profile_pic || 'alucard.jpg'}" alt="Avatar" class="user-avatar" onerror="this.src='Multimedia/logo.png'">
                    <div class="user-meta">
                        <h4>${r.username}</h4>
                        <p>${r.movie_title} (${r.movie_year})</p>
                    </div>
                    <div class="mod-stars">
                        ${r.rating} ★
                    </div>
                </div>
                <p class="mod-comment">"${r.comment}"</p>
                <div class="mod-actions">
                    <button class="btn-mod-reject" onclick="window.moderateReview(${r.id}, false)">Rechazar</button>
                    <button class="btn-mod-approve" onclick="window.moderateReview(${r.id}, true)">Aprobar</button>
                </div>
            </div>
        `).join("");

    } catch (e) {
        console.error("Error cargando panel de moderación:", e);
        container.innerHTML = '<div class="error">Error al conectar con el servidor.</div>';
    }
};

window.moderateReview = async function (reviewId, approve) {
    const token = localStorage.getItem('vanacue_token');
    if (!token) return;

    const btnText = approve ? 'Aprobando...' : 'Rechazando...';
    const card = document.getElementById(`mod-card-${reviewId}`);
    if (card) card.style.opacity = '0.5';

    try {
        const response = await fetch(`${API_URL}/api/admin/reviews/moderate`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ review_id: reviewId, approve })
        });
        const data = await response.json();

        if (data.success) {
            mostrarToast(approve ? "Reseña aprobada" : "Reseña rechazada");
            window.renderAdminModerationPanel(); // Recargar lista de pendientes
            window.renderPaginatedReviews(1);    // Recargar lista pública si se aprobó
        } else {
            mostrarToast(data.message);
            if (card) card.style.opacity = '1';
        }
    } catch (e) {
        console.error(e);
        mostrarToast("Error de conexión");
        if (card) card.style.opacity = '1';
    }
};
// Bloque de código eliminado por redundancia con la integración del backend

// PopState Handler (Browser Back Button)
window.addEventListener("popstate", (event) => {
    // If event.state is null, it might be the initial page load or a basic hash change. 
    // We should check URL params.
    const params = new URLSearchParams(window.location.search);

    if (params.has("accion")) {
        const accion = params.get("accion");
        if (accion === 'series') window.renderView('series');
        else if (accion === 'peliculas') window.renderView('movies');
        else if (accion === 'favoritos') window.renderView('favorites');
    } else if (params.has("genero")) {
        window.renderView('genre', params.get("genero"));
    } else {
        // Default to Home
        // But check if we are in a modal... 
        if (event.state && event.state.modalAbierto) {
            // Do nothing, handled by modal logic
        } else {
            window.renderView('home');
        }
    }
});

// ==========================================
// === LÓGICA DEL HERO DINÁMICO (JSON) ===
// ==========================================

document.addEventListener("DOMContentLoaded", () => {
    const heroContainer = document.getElementById("hero-carrusel-container");
    const dotsContainer = document.getElementById("hero-dots-container");

    // Solo ejecutamos si existe el contenedor del Hero
    if (!heroContainer) return;

    // 1. CARGA SIMULTÁNEA: Pedimos hero.json Y datos.json al mismo tiempo
    Promise.all([
        fetch('hero.json?v=' + new Date().getTime()).then(r => r.json()),
        fetch('datos.json?v=' + new Date().getTime()).then(r => r.json())
    ]).then(([heroData, biblioteca]) => {

        if (heroData.length === 0) return;

        // 2. GENERAR HTML DE SLIDES (CON LÓGICA DE SERIES)
        heroData.forEach((item, index) => {

            // Busamos la info completa en datos.json para saber si es serie
            const dataCompleta = biblioteca.find(d => d.titulo === item.titulo);
            let textoBoton = "▶ Reproducir"; // Texto por defecto

            // Si es serie, revisamos el historial para cambiar el texto del botón
            if (dataCompleta && dataCompleta.tipo === "Serie") {
                // Usamos la función que creamos antes
                const last = typeof getLastEpisode === 'function' ? getLastEpisode(item.titulo) : null;
                if (last) {
                    textoBoton = `▶ Continuar T${last.seasonNumber}:E${last.episodeNumber} `;
                }
            }

            // Crear Slide
            const slide = document.createElement("div");
            slide.classList.add("hero-slide");
            const telegramUrl = item.enlaceTelegram || ""; // Usamos el del hero o datos

            slide.innerHTML = `
                <img src="${item.imagen}" alt="${item.titulo}" class="hero-img">
                    <div class="hero-content">
                        <img src="${item.logo}" alt="Título ${item.titulo}" class="hero-logo">
                            <p class="hero-subtitle">${item.subtitulo}</p>

                            <div class="hero-botones-wrapper">
                                <button class="hero-btn play-trigger" data-titulo="${item.titulo}">
                                    ${textoBoton}
                                </button>

                                ${telegramUrl ? `
                      <a href="${telegramUrl}" target="_blank" class="btn-hero-telegram">
                          <img src="Multimedia/telegram.svg" alt="Ver en Telegram">
                      </a>` : ''}
                            </div>
                    </div>
            `;
            heroContainer.appendChild(slide);

            // Crear Dot
            const dot = document.createElement("img");
            dot.src = index === 0 ? "Multimedia/circle_w.svg" : "Multimedia/circle.svg";
            dot.classList.add("dot");
            if (index === 0) dot.classList.add("active");
            dotsContainer.appendChild(dot);
        });

        // 3. LISTENERS DEL BOTÓN REPRODUCIR (HERO)
        // 4. INICIAR LA ANIMACIÓN DEL CARRUSEL
        iniciarLogicaHero(biblioteca);
    })
        .catch(e => console.error("Error en Hero:", e));

    // --- FUNCIÓN INTERNA PARA ANIMAR EL CARRUSEL ---
    function iniciarLogicaHero(biblioteca) {
        const heroCarrusel = document.querySelector(".hero-carrusel");
        const slides = document.querySelectorAll(".hero-slide");
        const dots = document.querySelectorAll(".hero-dots .dot");
        const btnLeftHero = document.querySelector(".hero-btn-left");
        const btnRightHero = document.querySelector(".hero-btn-right");

        // === NUEVA LÓGICA DE DELEGACIÓN GLOBAL (CEREBRO ÚNICO) ===
        // En lugar de escuchar botones individuales, escuchamos al contenedor.
        // Cuando se hace click en "Reproducir", usamos el ÍNDICE ACTUAL (index)
        // para determinar qué título reproducir. Esto ignora clics fantasma.
        if (heroCarrusel) {
            heroCarrusel.addEventListener('click', (e) => {
                const btn = e.target.closest('.hero-btn.play-trigger');
                if (!btn) return; // Si no dio click en un botón de play, ignorar

                // AQUÍ ESTÁ LA MAGIA: IGNORAMOS EL BOTÓN CLICKEADO
                // Y USAMOS EL SLIDE ACTIVO (index)
                const activeSlide = slides[index];
                if (!activeSlide) return;

                const activeBtn = activeSlide.querySelector('.play-trigger');
                if (!activeBtn) return;

                if (!activeBtn) return;

                // REPRODUCIR (Lógica Centralizada)
                reproducirSlideActivo(biblioteca, slides, index);
            });
        }

        // --- HELPER: REPRODUCIR SLIDE ACTIVO ---
        function reproducirSlideActivo(biblioteca, slides, index) {
            const activeSlide = slides[index];
            if (!activeSlide) return;

            const activeBtn = activeSlide.querySelector('.play-trigger');
            if (!activeBtn) return;

            const titulo = activeBtn.getAttribute("data-titulo");
            const dataCompleta = biblioteca.find(d => d.titulo === titulo);

            if (!dataCompleta) {
                mostrarToast("No disponible en Streaming");
                return;
            }

            // Seguridad Premium
            const userStr = localStorage.getItem('vanacue_user');
            const usuario = userStr ? JSON.parse(userStr) : { role: 'free' };

            if (dataCompleta.premium === true && usuario.role !== 'premium' && usuario.role !== 'admin') {
                abrirModal(dataCompleta);
                mostrarToast("Contenido Premium\nContacta a soporte en Telegram");
                return;
            }

            abrirModal(dataCompleta);

            if (dataCompleta.tipo === "Serie") {
                const lastWatched = typeof getLastEpisode === 'function' ? getLastEpisode(dataCompleta.titulo) : null;
                if (lastWatched) {
                    const tituloRep = `T${lastWatched.seasonNumber}:E${lastWatched.episodeNumber} - ${lastWatched.titulo}`;
                    iniciarReproduccion(lastWatched.streamUrl, tituloRep, dataCompleta.fecha);
                } else {
                    if (dataCompleta.temporadas && dataCompleta.temporadas.length > 0) {
                        const primerEp = dataCompleta.temporadas[0].episodios[0];
                        if (typeof saveLastEpisode === 'function') {
                            saveLastEpisode(dataCompleta.titulo, {
                                seasonIndex: 0, episodeIndex: 0, seasonNumber: 1, episodeNumber: 1,
                                titulo: primerEp.titulo, streamUrl: primerEp.streamUrl, fechaSerie: dataCompleta.fecha
                            });
                        }
                        const tituloRep = `T1:E1 - ${primerEp.titulo}`;
                        iniciarReproduccion(primerEp.streamUrl, tituloRep, dataCompleta.fecha, primerEp.subtitulos);
                    } else {
                        mostrarToast("No disponible en Streaming");
                    }
                }
            } else {
                if (dataCompleta.streamUrl) {
                    iniciarReproduccion(dataCompleta.streamUrl, dataCompleta.titulo, dataCompleta.fecha);
                } else {
                    mostrarToast("No disponible en Streaming");
                }
            }
        }

        if (slides.length === 0) return;

        let index = 0;
        const totalSlides = slides.length;

        // Inicializar: Asegurar que el primero sea visible
        slides.forEach((slide, i) => {
            if (i === 0) {
                slide.classList.add("active");
                slide.classList.remove("exiting");
            } else {
                slide.classList.remove("active", "exiting");
            }
        });

        // Actualizar visuales (Reveal Effect: Outgoing fades out, Incoming stays behind)
        // EVENTO: Limpieza asíncrona tras la transición
        // Esto evita el parpadeo del reflow síncrono
        slides.forEach(slide => {
            slide.addEventListener('transitionend', (e) => {
                // Solo nos importa si terminó la transición de opacidad
                if (e.propertyName !== 'opacity') return;

                // Si el slide está oculto (ni activo ni saliendo)
                if (!slide.classList.contains('active') && !slide.classList.contains('exiting')) {
                    const img = slide.querySelector(".hero-img");
                    if (img) {
                        img.style.animation = 'none';
                        void img.offsetWidth; // Reflow seguro (nadie lo ve)
                        img.style.animation = '';
                        img.style.animationPlayState = 'paused';
                    }
                }
            });
        });

        function updateVisuals(prevIndex) {
            slides.forEach((slide, i) => {
                // 1. El nuevo slide (index) entra DETRÁS (z-index 1)
                if (i === index) {
                    slide.classList.add("active");
                    slide.classList.remove("exiting");

                    // FIX: Asegurar que NO esté pausado manualmente
                    const img = slide.querySelector(".hero-img");
                    if (img) img.style.animationPlayState = "";
                }
                // 2. El slide anterior (prevIndex) se queda ARRIBA (z-index 2) y se desvanece
                else if (i === prevIndex) {
                    slide.classList.add("exiting");
                    slide.classList.remove("active");
                }
                // 3. Los demás se limpian (y se REBOBINAN en silencio)
                else {
                    slide.classList.remove("active", "exiting");

                    // REBOBINADO MOVIDO A TRANSITIONEND
                    // Para evitar parpadeo por reflow síncrono
                }
            });

            // Actualizar dots
            dots.forEach((dot, i) => {
                dot.src = i === index ? "Multimedia/circle_w.svg" : "Multimedia/circle.svg";
                dot.classList.toggle("active", i === index);
            });
        }

        function goToSlide(i) {
            const prev = index;
            index = i;
            updateVisuals(prev); // Pasamos el anterior para que sea el "exiting"
            resetAutoplay();
        }

        // --- SWIPE TÁCTIL CON FISICA 1:1 ---
        let touchStartX = 0;
        let touchStartY = 0;
        let touchEndX = 0;
        let isDragging = false;
        let isScrolling = false;
        const heroWidth = heroCarrusel ? heroCarrusel.offsetWidth : 0;

        if (heroCarrusel) {
            heroCarrusel.addEventListener("touchstart", (e) => {
                touchStartX = e.touches[0].clientX;
                touchStartY = e.touches[0].clientY;
                isDragging = true;
                isScrolling = false;
                // Pausar autoplay durante la interacción
                clearTimeout(autoplayTimeout);

                // Desactivar transiciones para respuesta instantánea
                slides.forEach(s => s.classList.add("no-transition"));
            }, { passive: true });

            heroCarrusel.addEventListener("touchmove", (e) => {
                if (!isDragging) return;
                if (isScrolling) return;

                const currentX = e.touches[0].clientX;
                const currentY = e.touches[0].clientY;

                const deltaX = touchStartX - currentX;
                const deltaY = touchStartY - currentY;

                // DETECCIÓN DE DIRECCIÓN
                if (Math.abs(deltaY) > Math.abs(deltaX)) {
                    isScrolling = true;
                    slides.forEach(s => s.classList.remove("no-transition"));
                    return;
                }

                touchEndX = currentX;
                const deltaXReal = touchStartX - touchEndX;

                // Normalizar delta entre 0 y 1 (o más)
                const percent = Math.abs(deltaXReal) / heroWidth;

                // LOGICA DE VISUALIZACIÓN EN TIEMPO REAL
                if (deltaX > 0) {
                    // DESLIZANDO A LA IZQUIERDA (Siguiente)
                    // El slide actual (index) se desvanece (opacity baja)
                    // El slide siguiente (index + 1) está detrás (opacity 1 por defecto o controlado)

                    // Aseguramos que el SIGUIENTE esté listo detrás
                    const nextIndex = (index + 1) % totalSlides;

                    slides[index].style.opacity = Math.max(0, 1 - percent); // Desvanece el actual
                    slides[index].style.zIndex = 2;

                    slides[nextIndex].style.opacity = 1; // El fondo se ve completo
                    slides[nextIndex].style.zIndex = 1;

                    // FIX: Mantener estático hasta cambiar
                    const nextImg = slides[nextIndex].querySelector(".hero-img");
                    if (nextImg) nextImg.style.animationPlayState = "";

                } else {
                    // DESLIZANDO A LA DERECHA (Anterior)
                    // CAMBIO DE LÓGICA: Igual que al ir adelante, desvanecemos el ACTUAL
                    // para revelar el ANTERIOR que está detrás.
                    const prevIndex = (index - 1 + totalSlides) % totalSlides;

                    // El actual (Top) se desvanece
                    slides[index].style.opacity = Math.max(0, 1 - percent);
                    slides[index].style.zIndex = 2; // Se mantiene arriba mientras sale

                    // El anterior (Bottom) está listo detrás
                    slides[prevIndex].style.opacity = 1;
                    slides[prevIndex].style.zIndex = 1;

                    // FIX: Mantener estático hasta cambiar
                    const prevImg = slides[prevIndex].querySelector(".hero-img");
                    if (prevImg) prevImg.style.animationPlayState = "";
                }
            }, { passive: true });

            heroCarrusel.addEventListener("touchend", (e) => {
                if (!isDragging) return;
                isDragging = false;

                // Detectar posición final real (por si touchmove no disparó)
                const realEndX = e.changedTouches[0].clientX;
                const realEndY = e.changedTouches[0].clientY;

                const diffX = Math.abs(touchStartX - realEndX);
                const diffY = Math.abs(touchStartY - realEndY);

                // === DETECCIÓN DE TAP (Toque simple sin arrastre) ===
                if (diffX < 10 && diffY < 10) {
                    // Limpiar clases de transición por seguridad
                    slides.forEach(s => s.classList.remove("no-transition"));

                    // Si el toque fue en el botón de play, disparar manualmente
                    if (e.target.closest('.play-trigger')) {
                        e.preventDefault();
                        reproducirSlideActivo(biblioteca, slides, index);
                    }
                    // IMPORTANTE: Salir para NO ejecutar la lógica de swipe (updateVisuals)
                    // que "refresca" el DOM y mata el evento click nativo
                    return;
                }

                if (isScrolling) {
                    startAutoplay();
                    return;
                }

                // Reactivar transiciones CSS y limpiar estilos inline
                slides.forEach(s => {
                    s.classList.remove("no-transition");
                    s.style.opacity = "";
                    s.style.zIndex = "";

                    // LIMPIAR FORZADO DE ANIMACIÓN
                    const img = s.querySelector(".hero-img");
                    if (img) {
                        img.style.animation = "";
                        img.style.animationPlayState = "";
                    }
                });

                const deltaX = touchStartX - realEndX;
                const threshold = heroWidth * 0.2; // 20% de la pantalla para cambiar

                if (deltaX > threshold) {
                    // Confirmar avence al Siguiente
                    goToSlide((index + 1) % totalSlides);
                } else if (deltaX < -threshold) {
                    // Confirmar retroceso al Anterior
                    goToSlide((index - 1 + totalSlides) % totalSlides);
                } else {
                    // Cancelar / Revertir (volver al estado actual)
                    // Simplemente re-llamamos a updateVisuals para resetear clases
                    // Como no cambiamos 'index', se queda donde mismo
                    updateVisuals((index - 1 + totalSlides) % totalSlides);
                    startAutoplay();
                }
            });
        }

        // Autoplay Corrected
        let autoplayTimeout;
        function startAutoplay() {
            clearTimeout(autoplayTimeout); // Matar cualquier timer previo
            autoplayTimeout = setTimeout(() => {
                // FIX: Verify visibility to avoid background transitions
                // If offsetParent is null, it's hidden (display: none)
                if (!heroCarrusel.offsetParent) {
                    startAutoplay(); // Re-schedule check but don't advance
                    return;
                }
                goToSlide((index + 1) % totalSlides);
            }, 6000);
        }
        function stopAutoplay() {
            clearTimeout(autoplayTimeout);
        }
        function resetAutoplay() {
            stopAutoplay();
            startAutoplay();
        }
        startAutoplay();

        // Flechas
        if (btnLeftHero) btnLeftHero.addEventListener("click", () => {
            goToSlide((index - 1 + totalSlides) % totalSlides);
        });
        if (btnRightHero) btnRightHero.addEventListener("click", () => {
            goToSlide((index + 1) % totalSlides);
        });

        // Clic en Dots
        dots.forEach((dot, i) => {
            dot.addEventListener("click", () => goToSlide(i));
        });
    }
});

document.addEventListener("DOMContentLoaded", () => {
    // Esperamos a que los datos del JSON estén listos
    dataPromise.then(catalogoPeliculas => {

        // === [INICIO BLOQUE NUEVO] DETECTOR DE DEEP LINKS ===
        const params = new URLSearchParams(window.location.search);
        const idParaVer = params.get("watch");

        if (idParaVer) {
            console.log("🔗 Link directo detectado para ID:", idParaVer);

            // Buscamos la película en el catálogo recién cargado
            const peliculaEncontrada = catalogoPeliculas.find(p => {
                // Usamos la misma lógica de ID que en favoritos/abrirModal
                const pId = p.tmdbId || (typeof generateId === 'function' ? generateId(p) : null);
                // Comparamos como String para evitar errores de tipo (numero vs texto)
                return String(pId) === String(idParaVer);
            });

            if (peliculaEncontrada) {
                // Pequeño retraso para dar tiempo a que el DOM base se pinte
                setTimeout(() => {
                    abrirModal(peliculaEncontrada);
                }, 500);
            } else {
                console.warn("⚠️ El ID del link no existe en el catálogo.");
                // Opcional: Limpiamos la URL si el ID es inválido
                if (typeof limpiarUrlAlCerrar === 'function') limpiarUrlAlCerrar();
            }
        }
        // === [FIN BLOQUE NUEVO] ===

        // 4. Inicializar UI principal (SPA Logic)
        const main = document.querySelector("main");

        // Si estamos en favoritos.html, evitamos renderizar carruseles
        if (document.getElementById("contenedor-favoritos")) return;
        if (!main || main.classList.contains("genero-main")) return;

        // Check if we need to redirect due to deep link or show Home
        const navParams = new URLSearchParams(window.location.search);

        // If there is a 'watch' param, the modal logic already handles it (above).
        // Here we just decide what background view to show. 
        // If we are watching something, we usually want Home behind it, unless we came from a specific view...
        // For simplicity, default to Home if no specific view param.

        if (navParams.has("accion")) {
            const accion = navParams.get("accion");
            if (accion === 'series') window.renderView('series');
            else if (accion === 'peliculas') window.renderView('movies');
            else if (accion === 'favoritos') window.renderView('favorites');
            else if (accion === 'planes') window.renderView('plans');
        } else if (navParams.has("genero")) {
            window.renderView('genre', navParams.get("genero"));
        } else {
            // Default: Render Home
            window.renderHome();
        }

    }); // Cerramos el .then de dataPromise
});

// === PÁGINA DE GÉNERO ===
document.addEventListener("DOMContentLoaded", () => {
    // Esperamos a que los datos del JSON estén listos
    dataPromise.then(catalogoPeliculas => {

        const params = new URLSearchParams(window.location.search);
        const generoParam = params.get("genero");
        if (!generoParam) return; // si no estamos en la página de género, salimos

        const generoNombre = decodeURIComponent(generoParam).replace("_", " ");
        const generoKey = generoNombre.toLowerCase();

        const titulo = document.getElementById("titulo-genero");
        const contenedor = document.getElementById("grid-genero");

        if (titulo && contenedor) {
            // Poner el título con mayúscula inicial
            titulo.textContent = generoNombre.charAt(0).toUpperCase() + generoNombre.slice(1);

            // === Mapeo de sinónimos (Suspenso <-> Suspense) ===
            const generoAliases = {
                "suspenso": ["suspenso", "suspense"],
                "suspense": ["suspenso", "suspense"]
            };

            // === Filtrar películas coincidentes ===
            const peliculasFiltradas = catalogoPeliculas
                .filter(p =>
                    p.genero.some(g => {
                        const gLower = g.toLowerCase();
                        // si existe alias, busca en ambas variantes
                        if (generoAliases[generoKey]) {
                            return generoAliases[generoKey].includes(gLower);
                        }
                        // de lo contrario, coincidencia exacta (case-insensitive)
                        return gLower === generoKey;
                    })
                )
                .reverse();

            console.log(`Género: ${generoNombre} → Encontradas: `, peliculasFiltradas.map(p => p.titulo));

            // === Renderizar tarjetas ===
            peliculasFiltradas.forEach(pelicula => {
                const card = createCardElement(pelicula);
                contenedor.appendChild(card);
            });

            // === FORZAR ACTUALIZACIÓN DE ESTRELLAS ===
            // Si la promesa de favoritos existe, esperamos a que termine y actualizamos iconos
            if (favoritosPromesa) {
                favoritosPromesa.then(() => {
                    actualizarEstrellasVisibles();
                });
            }
        }

    }); // Cerramos el .then de dataPromise
});

// === FUNCIONALIDAD DE BOTONES DE MENÚ (SPA Logic) ===
document.addEventListener("DOMContentLoaded", () => {
    // 1. SELECCIÓN POR ID
    const btnInicio = document.getElementById("link-inicio");
    const btnSeries = document.getElementById("link-series");
    const btnPeliculas = document.getElementById("link-peliculas");
    const btnFavoritos = document.getElementById("link-favoritos");

    // Prevent default and navigate logic
    if (btnInicio) btnInicio.addEventListener("click", (e) => {
        e.preventDefault();
        window.navigateTo('home');
    });

    if (btnSeries) btnSeries.addEventListener("click", (e) => {
        e.preventDefault();
        window.navigateTo('series');
    });

    if (btnPeliculas) btnPeliculas.addEventListener("click", (e) => {
        e.preventDefault();
        window.navigateTo('movies');
    });

    if (btnFavoritos) {
        btnFavoritos.addEventListener("click", (e) => {
            e.preventDefault();
            // Check if we are in index (SPA capable) or need to redirect
            if (document.getElementById("mainContent")) {
                window.navigateTo('favorites');
            } else {
                window.location.href = 'index.html?accion=favoritos';
            }
        });
    }

    const btnPlanes = document.getElementById("link-planes");
    if (btnPlanes) {
        btnPlanes.addEventListener("click", (e) => {
            e.preventDefault();
            if (document.getElementById("mainContent")) {
                window.navigateTo('plans');
            } else {
                window.location.href = 'index.html?accion=planes';
            }
        });
    }

    const btnReviews = document.getElementById("link-reviews");
    if (btnReviews) {
        const userStr = localStorage.getItem('vanacue_user');
        const user = userStr ? JSON.parse(userStr) : {};
        if (user.reviews_block) {
            btnReviews.style.display = 'none';
        }

        btnReviews.addEventListener("click", (e) => {
            e.preventDefault();
            if (user.reviews_block) {
                mostrarToast("Función no disponible.");
                return;
            }
            if (document.getElementById("mainContent")) {
                window.navigateTo('reviews');
            } else {
                window.location.href = 'index.html?accion=reseñas';
            }
        });
    }
});

// === BUSCADOR EMERGENTE (ELIMINADO - USAR LÓGICA DE MENUBAR) ===
// La lógica de búsqueda ahora se maneja en setupMenubarInteractions()


// === MANEJO DE CLIC EN EL ÍCONO DE FAVORITOS (ACTUALIZADO) ===
document.addEventListener("click", e => {
    // 1. Detectar si el clic fue en una estrella
    const favoritoIcono = e.target.closest(".icono-favorito");
    if (!favoritoIcono) return;

    e.preventDefault();
    e.stopPropagation(); // Evitar que se abra el modal de la película

    // 2. Buscar la tarjeta padre para obtener los datos
    const tarjeta = favoritoIcono.closest(".tarjeta");

    if (tarjeta && tarjeta.dataset.info) {
        try {
            // Convertimos el texto JSON a un objeto real
            const pelicula = JSON.parse(tarjeta.dataset.info);

            console.log("Toggle favorito click detectado:", pelicula.titulo);

            // 3. Llamamos a la función MAESTRA
            toggleFavorito(pelicula, favoritoIcono);
        } catch (err) {
            console.error("Error al procesar datos de tarjeta para favoritos:", err);
        }
    } else {
        console.warn("Tarjeta o datos no encontrados para el ícono de favorito");
    }
});


// === CLICK GLOBAL EN TARJETAS (Asegurando NO abrir Telegram si se hizo clic en Favorito) ===
document.addEventListener("click", e => {

    // Si el clic vino del ícono de favoritos, IGNORAR la acción de la tarjeta
    if (e.target.closest(".icono-favorito")) {
        return;
    }

    dataPromise.then(catalogoPeliculas => {

        // Detectamos el elemento padre .tarjeta que contiene la información
        const card = e.target.closest(".tarjeta");
        if (!card) return; // Si no se hizo clic sobre una tarjeta, salir

        const menubar = document.querySelector(".menubar");

        // 1. OBTENER DATOS DE LA PELÍCULA 
        let pelicula;
        if (card.dataset.info) {
            pelicula = JSON.parse(card.dataset.info);
        } else {
            const titulo = card.querySelector("h3")?.textContent?.trim();
            if (titulo) {
                pelicula = catalogoPeliculas.find(p => p.titulo === titulo);
            }
        }


        // 2. APLICAR CAMBIO DE CLASE Y FORZAR RENDERIZADO
        if (pelicula) { // Quitamos la dependencia estricta de enlaceTelegram para que abra el modal

            // Aseguramos que el menú se oscurezca
            if (menubar) menubar.classList.add("scrolled");

            // 3. ABRIR EL MODAL (En vez de ir a Telegram directo)
            abrirModal(pelicula);
        }

    }); // Cerramos el .then de dataPromise
});

// === BLOQUEAR CLIC DERECHO ===
function blockRightClick(e) {
    e.preventDefault();
    e.stopPropagation();
}

// === CAMBIO DE COLOR DEL MENUBAR INTELIGENTE ===
document.addEventListener("DOMContentLoaded", () => {
    const menubar = document.querySelector(".menubar");
    const hero = document.querySelector(".hero"); // Referencia al hero

    if (!menubar) return;

    // Si estamos en genero.html, forzamos oscuro y salimos
    if (document.querySelector(".genero-main")) {
        menubar.classList.add("scrolled");
        return;
    }

    // FUNCIÓN MAESTRA DE COLOR
    updateMenubarBackground = function () {
        if (!hero || getComputedStyle(hero).display === 'none') {
            menubar.classList.add("scrolled");
            return;
        }

        // 2. LÓGICA PARA EL HOME (Solo si el hero está visible):
        // Calculamos el umbral (70% de la pantalla)
        const scrollThreshold = window.innerHeight * 0.70;

        if (window.scrollY > scrollThreshold) {
            menubar.classList.add("scrolled");
        } else {
            menubar.classList.remove("scrolled");
        }
    }

    // Inicializar
    updateMenubarBackground();

    // Listeners
    window.addEventListener("scroll", updateMenubarBackground);
    window.addEventListener("resize", updateMenubarBackground);

    const observer = new MutationObserver(updateMenubarBackground);
    if (hero) {
        observer.observe(hero, { attributes: true, attributeFilter: ['style'] });
    }
});


// ==========================================
// === LÓGICA DEL MODAL CON STREAMING HLS ===
// ==========================================

const modalOverlay = document.getElementById('modal-info');
const btnCerrar = document.getElementById('btn-cerrar-modal');
const modalVideo = document.getElementById('modal-video');
const modalImg = document.getElementById('modal-img-fondo');
const modalContentOverlay = document.getElementById('modal-hero-content-wrapper');

let hls = null;
let player = null;


/**
 * Renderiza la lista de episodios en el modal para una temporada específica.
 * @param {Object} serie - El objeto completo de la serie.
 * @param {number} indiceTemporada - El índice del array de temporadas (0 para temp 1, etc).
 */
function renderizarEpisodios(serie, indiceTemporada) {
    const listaContainer = document.getElementById('lista-episodios');
    if (!listaContainer) return;

    // Limpiar lista anterior
    listaContainer.innerHTML = '';

    // Obtener la temporada actual
    const temporadaActual = serie.temporadas[indiceTemporada];
    if (!temporadaActual || !temporadaActual.episodios) return;

    // Recorrer los episodios y crear el HTML
    temporadaActual.episodios.forEach((ep, indexEp) => {
        const row = document.createElement('div');
        row.classList.add('episodio-item');

        // Obtener el último episodio visto de esta serie
        const lastEp = getLastEpisode(serie.titulo);
        const isActive = lastEp && lastEp.seasonNumber === temporadaActual.numero && lastEp.episodeNumber === ep.episodio;

        if (isActive) {
            row.classList.add('active-episode');
        }

        row.addEventListener('click', () => {

            // === 1. VALIDACIÓN PREMIUM (NUEVO BLOQUE) ===
            const userStr = localStorage.getItem('vanacue_user');
            const usuario = userStr ? JSON.parse(userStr) : { role: 'free' };

            // Usamos el objeto 'serie' que ya recibimos como parámetro en la función
            if (serie.premium === true && usuario.role !== 'premium' && usuario.role !== 'admin') {
                mostrarToast("Contenido Premium\nContacta a soporte en Telegram.");
                return;
            }
            // ============================================

            // === 2. VALIDACIÓN DE STREAMING ===
            if (!ep.streamUrl) {
                mostrarToast("No disponible en streaming");
                return;
            }

            const tituloRep = `T${temporadaActual.numero}:E${ep.episodio} - ${ep.titulo}`;

            // GUARDAR ESTADO (Solo si hay streamUrl)
            saveLastEpisode(serie.titulo, {
                seasonIndex: indiceTemporada,
                episodeIndex: indexEp,
                seasonNumber: temporadaActual.numero,
                episodeNumber: ep.episodio,
                titulo: ep.titulo,
                streamUrl: ep.streamUrl,
                fechaSerie: serie.fecha
            });

            // Actualizar UI: Remover clase activa de otros y añadir a este
            const allRows = listaContainer.querySelectorAll('.episodio-item');
            allRows.forEach(r => r.classList.remove('active-episode'));
            row.classList.add('active-episode');

            // INICIAR REPRODUCCIÓN
            // CONTEXTO PARA EPISODIO SIGUIENTE
            const contexto = {
                tipo: 'serie',
                serie: serie, // objeto completo recibido por parametro
                temporadaIndex: indiceTemporada,
                episodioIndex: indexEp,
                temporadaNumero: temporadaActual.numero,
                episodioNumero: ep.episodio
            };

            iniciarReproduccion(ep.streamUrl, tituloRep, serie.fecha, ep.subtitulos, contexto);

        });

        // HTML interno del episodio (SVG INLINE para el icono de play)
        row.innerHTML = `
            <div class="episodio-numero">${ep.episodio}</div>
            <div class="episodio-img-wrapper">
                <img src="${ep.imagen}" alt="${ep.titulo}" class="episodio-img">
                <div class="episodio-play-icon">
                    <svg viewBox="0 0 24 24" fill="white" width="100%" height="100%"><path d="M8 5v14l11-7z"/></svg>
                </div>
            </div>
            <div class="episodio-info">
                <div class="episodio-cabecera">
                    <span class="episodio-titulo">${ep.titulo}</span>
                    <span class="episodio-duracion">${ep.duracion}</span>
                </div>
                <p class="episodio-sinopsis">${ep.sinopsis}</p>
            </div>
            `;

        listaContainer.appendChild(row);
    });
}

// ==========================================
// GESTIÓN DE URL (DEEP LINKING) - PARTE 1
// ==========================================
function actualizarUrlAlAbrir(pelicula) {
    // Usamos tmdbId si existe, si no, generamos el ID como lo haces en favoritos
    const id = pelicula.tmdbId || (typeof generateId === 'function' ? generateId(pelicula) : null);

    if (id) {
        // Esto cambia la URL visualmente sin recargar la página
        // Guardamos un "estado" para saber que hay un modal abierto
        const nuevaUrl = `? watch = ${id} `;
        window.history.pushState({ modalAbierto: true, id: id }, '', nuevaUrl);
    }
}

function limpiarUrlAlCerrar() {
    // Regresamos a la URL limpia (sin parámetros)
    // OJO: Usamos replaceState para no llenar el historial de "atrás" infinitos
    const urlLimpia = window.location.pathname;
    window.history.pushState({ modalAbierto: false }, '', urlLimpia);
}

// === FUNCIÓN ABRIR MODAL (CON LIMPIEZA AUTOMÁTICA) ===
function abrirModal(pelicula) {
    // 1. CONFIRMA QUE ESTA LÍNEA EXISTE AQUÍ ARRIBA:
    if (typeof actualizarUrlAlAbrir === 'function') {
        actualizarUrlAlAbrir(pelicula);
    } else {
        console.error("No encuentro la función actualizarUrlAlAbrir");
    }
    // 1. Limpieza de reproductores anteriores
    if (player) { try { player.destroy(); } catch (e) { } player = null; }
    if (hls) { try { hls.destroy(); } catch (e) { } hls = null; }

    const heroContainer = document.querySelector('.modal-hero');
    if (heroContainer) {
        const videos = heroContainer.querySelectorAll('video, .plyr');
        videos.forEach(v => v.remove());
        heroContainer.classList.remove('video-activo');
    }

    // 2. Mostrar elementos visuales base
    if (modalImg) {
        // Usamos backdrop si existe (horizontal), si no, la portada normal
        modalImg.src = pelicula.backdrop ? pelicula.backdrop : pelicula.portada;
        modalImg.classList.remove('hidden');
        modalImg.style.display = "block";
    }
    if (modalContentOverlay) modalContentOverlay.classList.remove('hidden');
    if (modalOverlay) modalOverlay.scrollTo(0, 0);

    // 3. Llenar textos básicos
    const tituloElem = document.getElementById('modal-titulo');
    if (tituloElem) tituloElem.innerText = pelicula.titulo;

    document.getElementById('modal-calificacion').innerText = `Match ${Math.round(pelicula.calificacion * 10)}% `;
    document.getElementById('modal-fecha').innerText = pelicula.fecha.substring(0, 4);

    // Ajuste visual para duración: si es serie, mostramos "X temporadas" o lo que venga en JSON
    document.getElementById('modal-duracion').innerText = pelicula.duracion;
    document.getElementById('modal-tipo').innerText = pelicula.tipo;
    document.getElementById('modal-sinopsis').innerText = pelicula.sinopsis;

    // Arrays a strings
    const elencoStr = Array.isArray(pelicula.elenco) ? pelicula.elenco.join(', ') : pelicula.elenco;
    const generoStr = Array.isArray(pelicula.genero) ? pelicula.genero.join(', ') : pelicula.genero;
    document.getElementById('modal-director').innerText = pelicula.director || 'Desconocido';
    document.getElementById('modal-elenco').innerText = elencoStr;
    document.getElementById('modal-genero').innerText = generoStr;

    // Botón "Ver reseñas"
    const btnVerResenas = document.getElementById('modal-btn-ver-resenas');
    if (btnVerResenas) {
        const userStr = localStorage.getItem('vanacue_user');
        const user = userStr ? JSON.parse(userStr) : {};
        
        btnVerResenas.style.display = 'inline-flex';
        const tituloPelicula = pelicula.titulo || '';
        btnVerResenas.onclick = () => {
            if (user.reviews_block) {
                mostrarToast("Función no disponible.");
                return;
            }
            // Cerrar modal y resetear overflow (fix del bug de scroll)
            const modalInfo = document.getElementById('modal-info');
            if (modalInfo) modalInfo.classList.add('hidden');
            document.documentElement.style.overflow = '';
            document.body.style.overflow = '';

            window.navigateTo('reviews');

            // Tras renderizar, volcar el título en el buscador y hacer scroll
            setTimeout(() => {
                const searchInput = document.getElementById('reviews-search-input');
                if (searchInput && tituloPelicula) {
                    searchInput.value = tituloPelicula;
                    searchInput.dispatchEvent(new Event('input'));
                }
                const container = document.getElementById('paginated-reviews-container');
                if (container) container.scrollIntoView({ behavior: 'smooth' });
            }, 600);
        };
    }

    // 4. LÓGICA DE SERIES VS PELÍCULAS
    const seccionEpisodios = document.getElementById('seccion-episodios');
    const selectTemporada = document.getElementById('select-temporada');
    const btnPlay = document.getElementById('modal-btn-reproducir');

    // Clonamos el botón Play para eliminar listeners viejos
    if (btnPlay) {
        const newBtnPlay = btnPlay.cloneNode(true);
        if (btnPlay.parentNode) btnPlay.parentNode.replaceChild(newBtnPlay, btnPlay);

        // 1. CONFIGURAR BOTÓN PLAY PRINCIPAL (Lógica de Click)
        newBtnPlay.addEventListener('click', (e) => {
            e.preventDefault();

            // === VALIDACIÓN PREMIUM ===
            const userStr = localStorage.getItem('vanacue_user');
            const usuario = userStr ? JSON.parse(userStr) : { role: 'free' };

            if (pelicula.premium === true && usuario.role !== 'premium' && usuario.role !== 'admin') {
                mostrarToast("Contenido Premium.\nContacta a soporte en Telegram.");
                return;
            }

            // LÓGICA DE REPRODUCCIÓN
            if (pelicula.tipo === "Serie") {
                // Verificar que existan temporadas
                if (!pelicula.temporadas || pelicula.temporadas.length === 0) {
                    mostrarToast("No disponible en Streaming");
                    return;
                }

                // --- LÓGICA DE SERIES ---
                const lastWatched = getLastEpisode(pelicula.titulo);

                if (lastWatched && lastWatched.streamUrl) {
                    // CASO 1: TIENE HISTORIAL
                    const tituloRep = `T${lastWatched.seasonNumber}:E${lastWatched.episodeNumber} - ${lastWatched.titulo}`;
                    // Reconstruir contexto desde historial (aproximado)
                    const contexto = {
                        tipo: 'serie',
                        serie: pelicula,
                        temporadaIndex: lastWatched.seasonIndex,
                        episodioIndex: lastWatched.episodeIndex,
                        temporadaNumero: lastWatched.seasonNumber,
                        episodioNumero: lastWatched.episodeNumber
                    };

                    let episodioData = null;
                    if (pelicula.temporadas && pelicula.temporadas[lastWatched.seasonIndex]) {
                        episodioData = pelicula.temporadas[lastWatched.seasonIndex].episodios[lastWatched.episodeIndex];
                    }
                    const subs = episodioData && episodioData.subtitulos ? episodioData.subtitulos : [];

                    iniciarReproduccion(lastWatched.streamUrl, tituloRep, pelicula.fecha, subs, contexto);

                } else {
                    // CASO 2: EMPEZAR DESDE CERO
                    const primerEp = pelicula.temporadas[0].episodios[0];
                    if (!primerEp || !primerEp.streamUrl) {
                        mostrarToast("No disponible en Streaming");
                        return;
                    }

                    const tituloRep = `T1:E1 - ${primerEp.titulo}`;

                    const contexto = {
                        tipo: 'serie',
                        serie: pelicula,
                        temporadaIndex: 0,
                        episodioIndex: 0,
                        temporadaNumero: 1,
                        episodioNumero: 1
                    };

                    // Guardar estado inicial
                    saveLastEpisode(pelicula.titulo, {
                        seasonIndex: 0,
                        episodeIndex: 0,
                        seasonNumber: 1,
                        episodeNumber: 1,
                        titulo: primerEp.titulo,
                        streamUrl: primerEp.streamUrl,
                        fechaSerie: pelicula.fecha
                    });

                    const subs = primerEp.subtitulos || [];
                    iniciarReproduccion(primerEp.streamUrl, tituloRep, pelicula.fecha, subs, contexto);
                }

            } else {
                // --- LÓGICA DE PELÍCULAS ---
                if (pelicula.streamUrl && pelicula.streamUrl.trim() !== "") {
                    // AQUÍ AGREGAMOS pelicula.subtitulos AL FINAL
                    // FIX: Agregamos contexto para leer post-play_experience
                    const contexto = {
                        tipo: 'pelicula',
                        pelicula: pelicula
                    };
                    iniciarReproduccion(pelicula.streamUrl, pelicula.titulo, pelicula.fecha, pelicula.subtitulos, contexto);
                } else {
                    mostrarToast("No disponible en Streaming");
                }
            }
        });

        // 2. CONFIGURACIÓN VISUAL (Texto y Candado)
        const spanTexto = newBtnPlay.querySelector('span');

        // A) Definir el texto base (Reproducir / Continuar)
        if (pelicula.tipo === "Serie") {
            const lastWatched = getLastEpisode(pelicula.titulo);
            if (lastWatched) {
                spanTexto.innerText = `Continuar T${lastWatched.seasonNumber}:E${lastWatched.episodeNumber} `;
            } else {
                spanTexto.innerText = "Reproducir T1:E1";
            }
        } else {
            spanTexto.innerText = "Reproducir";
        }

        // B) APLICAR ESTILO PREMIUM (Aquí es donde te atoraste)
        // Lo ponemos al final para que agregue el candado al texto que ya definimos arriba
        if (pelicula.premium) {
            spanTexto.innerText; // Agrega candado al inicio
            newBtnPlay.style.backgroundColor = "#dba506";      // Color dorado
            newBtnPlay.style.color = "#000";                   // Texto negro para contraste (opcional)
        } else {
            // Restablecer estilos por si se recicla el botón (importante en modales)
            newBtnPlay.style.backgroundColor = "";
            newBtnPlay.style.color = "";
        }
    }

    // MANEJO DE LA SECCIÓN DE EPISODIOS
    if (pelicula.tipo === "Serie" && pelicula.temporadas) {
        // A) Mostrar sección
        seccionEpisodios.classList.remove('hidden');

        // B) Llenar Select de Temporadas
        selectTemporada.innerHTML = '';
        // Lógica de historial para preseleccionar temporada
        const lastWatched = getLastEpisode(pelicula.titulo);
        let seasonIndexToRender = 0;

        if (lastWatched && typeof lastWatched.seasonIndex === 'number') {
            seasonIndexToRender = lastWatched.seasonIndex;
        }

        pelicula.temporadas.forEach((temp, index) => {
            const option = document.createElement('option');
            option.value = index; // Usamos el índice del array (0, 1, 2...)
            option.text = temp.nombre || `Temporada ${temp.numero} `;

            if (index === seasonIndexToRender) {
                option.selected = true;
            }
            selectTemporada.appendChild(option);
        });

        // Aseguramos que el select tenga el valor correcto
        selectTemporada.value = seasonIndexToRender;

        renderizarEpisodios(pelicula, seasonIndexToRender);

        const newSelect = selectTemporada.cloneNode(true);
        selectTemporada.parentNode.replaceChild(newSelect, selectTemporada);

        // FIX: Re-asignar valor después de clonar para asegurar visualización correcta
        newSelect.value = seasonIndexToRender;

        newSelect.addEventListener('change', (e) => {
            const indexSeleccionado = parseInt(e.target.value);
            renderizarEpisodios(pelicula, indexSeleccionado);
        });

    } else {
        // Si NO es serie, ocultamos la sección
        seccionEpisodios.classList.add('hidden');
    }

    // Configuración Botón Telegram (MODIFICADO: Toast si es null)
    const btnTelegram = document.getElementById('modal-btn-telegram');
    if (btnTelegram) {
        // Clonamos para limpiar listeners previos
        const newBtnTelegram = btnTelegram.cloneNode(true);
        if (btnTelegram.parentNode) btnTelegram.parentNode.replaceChild(newBtnTelegram, btnTelegram);

        newBtnTelegram.style.display = "flex"; // Siempre visible

        if (pelicula.enlaceTelegram) {
            newBtnTelegram.href = pelicula.enlaceTelegram;
            newBtnTelegram.target = "_blank";
        } else {
            newBtnTelegram.href = "#";
            newBtnTelegram.removeAttribute("target"); // Evitar abrir tab vacía
            newBtnTelegram.addEventListener("click", (e) => {
                e.preventDefault();
                mostrarToast("No disponible en telegram");
            });
        }
    }

    // ARREGLO PARA BOTÓN COMPARTIR
    const btnShare = document.getElementById('modal-btn-share');
    if (btnShare) {
        // Clonamos para limpiar listeners previos
        const newBtnShare = btnShare.cloneNode(true);
        if (btnShare.parentNode) btnShare.parentNode.replaceChild(newBtnShare, btnShare);

        newBtnShare.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();

            // 1. Obtener ID
            const id = pelicula.tmdbId || (typeof generateId === 'function' ? generateId(pelicula) : 'home');

            // 2. Construir URL
            const shareUrl = `https://vnc-e.com/share/${id}`;

            // 3. Copiar al portapapeles
            navigator.clipboard.writeText(shareUrl).then(() => {
                mostrarToast("Enlace copiado al portapapeles");
            }).catch(err => {
                console.error('Error al copiar: ', err);
                mostrarToast("No se pudo copiar el enlace");
            });
        });
    }

    // ARREGLO PARA BOTÓN RESEÑA (PENCIL)
    const btnReview = document.getElementById('modal-btn-review');
    if (btnReview) {
        // Hacemos el botón visible siempre
        btnReview.classList.remove('hidden');
        btnReview.style.display = 'flex';

        // Clonamos para limpiar listeners previos
        const newBtnReview = btnReview.cloneNode(true);
        if (btnReview.parentNode) btnReview.parentNode.replaceChild(newBtnReview, btnReview);

        newBtnReview.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();

            // Verificación unificada de "Premium/Admin"
            const userStr = localStorage.getItem('vanacue_user');
            const user = userStr ? JSON.parse(userStr) : { role: 'free' };
            const isPremium = user.role === 'premium' || user.role === 'admin';

            if (!isPremium) {
                mostrarToast("Necesitas suscripción premium para realizar esta acción.");
                return;
            }

            if (user.reviews_block) {
                mostrarToast("Función no disponible.");
                return;
            }

            window.openWriteReviewModal(pelicula);
        });
    }

    // 5. CONFIGURACIÓN BOTÓN FAVORITOS (CORREGIDO)
    const btnFav = document.getElementById('modal-btn-favorito');

    if (btnFav) {
        // A) Calcular el ID Unificado
        const id = pelicula.tmdbId || generateId(pelicula);

        // B) Verificar estado
        if (misFavoritos.has(id)) {
            btnFav.classList.add('favorito-activo');
            btnFav.src = "Multimedia/star_r.svg"; // <--- Importante: Cambiar la imagen visualmente
        } else {
            btnFav.classList.remove('favorito-activo');
            btnFav.src = "Multimedia/star.svg";
        }

        // C) Asignar click
        btnFav.onclick = (e) => {
            e.preventDefault();
            e.stopPropagation();
            toggleFavorito(pelicula, btnFav);
        };
    }

    // Similares
    if (typeof generarSimilares === "function") generarSimilares(pelicula);

    // Mostrar Modal Final
    if (modalOverlay) modalOverlay.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
}

// === FUNCIÓN PARA MOSTRAR MENSAJE ESTÉTICO (TOAST) ===
function mostrarToast(mensaje) {
    // 1. Evitar acumulación: Si ya hay uno, lo quitamos
    const existente = document.querySelector('.toast-msg');
    if (existente) existente.remove();

    const toast = document.createElement('div');
    toast.className = 'toast-msg';

    // 2. CAMBIO IMPORTANTE: Usamos innerText
    // Esto asegura que el navegador respete el salto de línea (\n)
    toast.innerText = mensaje;

    document.body.appendChild(toast);

    // 3. CAMBIO DE TIEMPO: Sincronizado con la animación CSS (4s)
    setTimeout(() => {
        if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, 4100); // 4.1 segundos para dejar que termine el fade out
}

// === FUNCIÓN AUXILIAR PARA DESARROLLO LOCAL ===
function resolverUrlVideo(url) {
    if (!url) return "";
    if (url.startsWith('http')) {
        return url;
    }
    return `https://vnc-e.com${url}`;
}

// === FUNCIÓN INICIAR REPRODUCCIÓN (ACTUALIZADA CON CONTEXTO) ===
function iniciarReproduccion(url, tituloObra, fechaObra, subtitulos = [], contexto = null) {
    let displayYear = "";
    if (fechaObra) {
        const yearMatch = String(fechaObra).match(/^(\d{4})/);
        if (yearMatch) {
            displayYear = ` (${yearMatch[1]})`;
        } else {
            displayYear = ` (${fechaObra})`;
        }
    }
    window.currentMediaWatching = tituloObra + displayYear;

    url = resolverUrlVideo(url);

    if (!url || url === "null" || url.trim() === "") {
        mostrarToast("No disponible en streaming");
        return;
    }

    // 1. INYECCIÓN CSS (CORREGIDA: Restauramos Z-Index para que se vean)
    const estiloPlayer = document.createElement('style');
    estiloPlayer.innerHTML = `
        /* === CAPAS (Z-INDEX) === */
        .plyr__controls { z-index: 100 !important; position: relative; }
        
        .custom-video-overlay { z-index: 50 !important; }
        
        .plyr__captions { 
            z-index: 150 !important; 
            pointer-events: none; 
            display: block !important; 
        }

        .plyr__control--overlaid { display: none !important; opacity: 0 !important; visibility: hidden !important; }

        /* === MENÚ === */
        .netflix-menu-overlay {
            position: absolute; top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.9); z-index: 200;
            display: flex; flex-direction: column; align-items: center; justify-content: center;
            opacity: 0; pointer-events: none; transition: opacity 0.2s ease;
        }
        .netflix-menu-overlay.active { opacity: 1; pointer-events: auto; }

        .netflix-menu-container { display: flex; gap: 4rem; max-width: 80%; }
        .netflix-col h3 { color: #fff; font-size: 1.2rem; margin-bottom: 1rem; border-bottom: 1px solid #e50914; padding-bottom: 5px; text-align: left; }
        
        .netflix-option {
            color: #aaa; padding: 8px 15px; cursor: pointer; font-size: 1rem;
            text-align: left; transition: color 0.2s; display: flex; align-items: center; gap: 10px;
        }
        .netflix-option:hover { color: #fff; background: rgba(255,255,255,0.1); border-radius: 4px; }
        .netflix-option.selected { color: #fff; font-weight: bold; }
        .netflix-option.selected::before { content: '✓'; color: #e50914; font-weight: bold; }

        @media (max-width: 768px) { .netflix-menu-container { flex-direction: column; gap: 2rem; width: 90%; } }
        
        .plyr-custom-btn svg { fill: currentColor; width: 18px; height: 18px; margin-top: 2px; }
        .plyr-custom-btn:hover { color: #e50914; }

        /* === RESPONSIVE: VOLUMEN VS PROGRESO === */
        
        /* 1. En móviles (vertical/pequeño), OCULTAMOS volumen para dar espacio a la barra */
        @media (max-width: 768px) {
            .plyr__volume {
                display: none !important;
            }
        }

        /* 2. EXCEPCIÓN: Si entra en Pantalla Completa, MOSTRAMOS volumen (incluso en móvil) */
        .plyr--fullscreen-active .plyr__volume {
            display: flex !important;
        }

        /* === SUBTÍTULOS MÁS GRANDES EN PANTALLA COMPLETA (VERSIÓN DEFINITIVA) === */
        
        /* 1. Plyr Custom UI (Standard) */
        .plyr--fullscreen-active .plyr__captions,
        .plyr--fullscreen-active .plyr__caption,
        .plyr--fullscreen-active .plyr__captions span {
            font-size: 5vh !important; /* 5% de la altura de la pantalla (~50px en 1080p) */
            line-height: normal !important;
        }

        /* 2. Selector Universal dentro de Captions (por si la anidación varía) */
        .plyr--fullscreen-active .plyr__captions * {
            font-size: 5vh !important;
        }

        /* 3. Shadow DOM / Webkit Nativo (Chrome/Edge/Safari) */
        video::-webkit-media-text-track-display {
            font-size: 5vh !important;
            transform: translate(0, -10%); /* Subirlos un poco si son nativos */
        }
        
        /* 4. Standard ::cue (Firefox / Fallback) */
        video::cue {
            font-size: 5vh !important;
            background-color: rgba(0,0,0,0.8) !important;
        }

        /* Asegurar que el contenedor de Plyr ocupe toda la pantalla para que las mediciones VH sean correctas */
        .plyr--fullscreen-active {
            width: 100vw !important;
            height: 100vh !important;
        }
    `;

    // AGREGAMOS ESTILOS PARA POST-PLAY (NETFLIX STYLE)
    estiloPlayer.innerHTML += `
        /* === POST-PLAY OVERLAY === */
        .post-play-overlay {
            position: absolute; top: 0; left: 0; width: 100%; height: 100%;
            z-index: 40; /* Debajo del video minimizado (50) pero encima del fondo 50 es video... espera. Video es 50. */
            /* CORRECCIÓN Z-INDEX: Video es 50. Overlay debe estar DEBAJO del video minimizado para que éste "flote" sobre él? 
               NO. El diseño original de Netflix es: El video se hace pequeño y queda EN UNA ESQUINA.
               El fondo (backdrop) ocupa TODO EL CONTENEDOR.
               Entonces:
               1. Contenedor Hero (padre).
               2. Imagen de fondo estática (z=0).
               3. Video minimizado (z=50).
               4. Overlay de recomendación (z=40). 
               
               Si el overlay tiene fondo negro/imagen, tapará la imagen de fondo estática original del modal.
            */
            background: #000;
            display: flex; flex-direction: row; align-items: center; justify-content: flex-end;
            opacity: 0; pointer-events: none; transition: opacity 0.5s ease;
        }
        .post-play-overlay.active { opacity: 1; pointer-events: auto; }
        .post-play-overlay.hidden { display: none; }

        .post-play-background {
            position: absolute; top: 0; left: 0; width: 100%; height: 100%;
            z-index: 1;
        }
        .post-play-background img {
            width: 100%; height: 100%; object-fit: cover; opacity: 0.6;
        }
        .post-play-gradient {
            position: absolute; top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(to right, #000 0%, rgba(0,0,0,0.8) 40%, rgba(0,0,0,0.4) 100%);
        }

        .post-play-content {
            position: relative; z-index: 2; width: 40%; margin-right: 5%;
            color: #fff; text-align: left;
            display: flex; flex-direction: column; gap: 1rem;
        }
        
        .pp-label { font-size: 1rem; color: #aaa; text-transform: uppercase; letter-spacing: 1px; margin: 0; }
        .pp-titulo { font-size: 2.5rem; font-weight: bold; margin: 0; line-height: 1.1; }
        .pp-sinopsis { font-size: 1rem; color: #ccc; display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; margin: 0; }
        
        .pp-actions { display: flex; gap: 1rem; margin-top: 1rem; }
        
        .pp-btn-play {
            background: #fff; color: #000; border: none; padding: 10px 25px;
            font-size: 1.1rem; font-weight: bold; border-radius: 4px; cursor: pointer;
            display: flex; align-items: center; gap: 8px; transition: transform 0.2s;
        }
        .pp-btn-play:hover { transform: scale(1.05); background: #e5e5e5; }
        
        .pp-btn-cancel {
            /* Estilo copiado de .btn-cerrar */
            background-color: rgba(24, 24, 24, 0.6);
            color: white;
            border: 2px solid rgba(255, 255, 255, 0.7);
            border-radius: 50%;
            width: 45px !important; height: 45px !important; /* Forzar dimensiones */
            min-width: 45px; /* Evitar aplastamiento */
            padding: 0 !important; /* Quitar padding por defecto */
            font-size: 28px;
            display: flex; align-items: center; justify-content: center;
            cursor: pointer;
            transition: transform 0.2s, background-color 0.2s;
            z-index: 100 !important; /* Asegurar clic */
            flex-shrink: 0; /* Evitar que flex lo aplaste */
        }
        .pp-btn-cancel:hover { 
            background-color: white; 
            color: black; 
            transform: scale(1.1); 
        }
        /* CAMBIO DE COLOR DEL ICONO SVG AL HOVER */
        .pp-btn-cancel:hover img {
            filter: brightness(0); /* Vuelve negro el icono (asumiendo que era blanco) */
        }

        /* OCULTAR CONTROLES (Barra de progreso, volumen, etc) CUANDO ESTÁ MINIMIZADO */
        /* Al activarse el post-play, Plyr a veces fuerza los controles. Esto los oculta a la fuerza. */
        .post-play-active .plyr__controls {
            display: none !important;
            opacity: 0 !important;
            pointer-events: none !important;
        }



        /* === VIDEO MINIMIZADO === */
        /* Aplicamos al wrapper de video de Plyr para que SOLO el video se encoja dentro del contenedor full */
        .plyr__video-wrapper.player-minimized {
            width: 35% !important; height: auto !important; aspect-ratio: 16/9;
            top: 40px !important; left: 40px !important;
            border: 2px solid rgba(255,255,255,0.2);
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
            transition: all 0.7s cubic-bezier(0.19, 1, 0.22, 1);
            position: absolute !important; 
            z-index: 70 !important; /* MÁS ALTO QUE TODO */
        }
        
        .post-play-overlay {
            /* ... estilos base ... */
            z-index: 60 !important; /* Encima de controles custom (50), debajo de video mini (70) */
        }

        /* En móvil, ajustamos el layout */
        @media (max-width: 768px) {
            .post-play-content { width: 90%; margin: 0 auto; text-align: center; align-items: center; padding-top: 40%; }
            .post-play-background img { opacity: 0.4; }
            .post-play-gradient { background: linear-gradient(to top, #000 0%, rgba(0,0,0,0.6) 50%, rgba(0,0,0,0.2) 100%); }
            
            .plyr__video-wrapper.player-minimized {
                width: 50% !important; top: 20px !important; left: 50% !important; transform: translateX(-50%);
            }
        }
    `;

    if (!document.getElementById('estilo-player-custom')) {
        estiloPlayer.id = 'estilo-player-custom';
        document.head.appendChild(estiloPlayer);
    }

    url = encodeURI(url);
    // === NUEVO: INYECCIÓN DE USUARIO PARA LOGS ===
    const userLogData = localStorage.getItem('vanacue_user');
    const usuarioLog = userLogData ? JSON.parse(userLogData).username : 'anonimo';
    // Creamos una nueva variable con la firma ?u=NombreUsuario
    const urlConUsuario = `${url}?u=${encodeURIComponent(usuarioLog)}`;
    // =============================================
    const videoId = tituloObra.trim().replace(/\s/g, '_').toLowerCase() + '_' + fechaObra;
    const heroContainer = document.querySelector('.modal-hero');
    if (!heroContainer) return;

    // Preparar Interfaz
    const modalImg = document.getElementById('modal-img-fondo');
    const modalContentOverlay = document.getElementById('modal-hero-content-wrapper');
    if (modalImg) modalImg.classList.add('hidden');
    if (modalContentOverlay) modalContentOverlay.classList.add('hidden');
    heroContainer.classList.add('video-activo');

    heroContainer.querySelectorAll('video, .plyr').forEach(v => v.remove());

    // Crear Video Element
    const videoElement = document.createElement('video');
    videoElement.id = 'dynamic-player';
    videoElement.controls = true;
    videoElement.playsInline = true;

    // IMPORTANTE: Permitir CORS para subtítulos
    videoElement.crossOrigin = "anonymous";

    Object.assign(videoElement.style, {
        width: "100%", height: "100%", position: "absolute",
        top: "0", left: "0", zIndex: "50", display: "block"
    });

    // Inyectar Subtítulos al DOM (<track>)
    if (subtitulos && Array.isArray(subtitulos)) {
        let hasDefault = subtitulos.some(s => s.default);

        subtitulos.forEach((sub, idx) => {
            const track = document.createElement('track');
            track.kind = 'captions';
            track.label = sub.label;
            track.srclang = sub.lang;
            track.src = resolverUrlVideo(sub.url);

            if (sub.default) {
                track.default = true;
            } else if (!hasDefault && idx === 0) {
                track.default = true; // Fix para algunos navegadores que ignoran la carga visual sin un default track
            }
            videoElement.appendChild(track);
        });
    }

    heroContainer.appendChild(videoElement);

    const defaultOptions = {
        seekTime: 10,
        controls: ['play', 'progress', 'current-time', 'mute', 'volume', 'fullscreen'],
        clickToPlay: false,
        // Active: true es vital para que Plyr renderice su propia UI de subtítulos
        // language: 'auto' puede causar problemas en Safari si no hay metadata clara
        captions: { active: true, update: true, language: 'auto' },
        fullscreen: { iosNative: true, container: null } // iosNative true es necesario para iPhone
    };

    // ===============================================
    // === LÓGICA DE CONTROLES (CORRECCIÓN VISUAL FINAL) ===
    // ===============================================

    // Helper para obtener el tiempo de trigger configurado (MOVIDO A SCOPE SUPERIOR)
    const getPostPlayThreshold = () => {
        let rawValue = 1.0; // Default: 1 minuto (60 seg)

        // Intentar leer configuración del JSON
        if (contexto) {
            if (contexto.tipo === 'pelicula' && contexto.pelicula && contexto.pelicula['post-play_experience'] !== undefined) {
                rawValue = contexto.pelicula['post-play_experience'];
            } else if (contexto.tipo === 'serie' && contexto.serie) {
                // Buscar en el episodio ESPECÍFICO
                try {
                    const epData = contexto.serie.temporadas[contexto.temporadaIndex].episodios[contexto.episodioIndex];
                    if (epData && epData['post-play_experience'] !== undefined) {
                        rawValue = epData['post-play_experience'];
                    }
                } catch (e) {
                    console.warn("No se pudo leer config de episodio:", e);
                }
            }
        }

        // Conversión formato "minutos.segundos" (Base 60 fake decimal)
        const minutes = Math.floor(rawValue);
        const secondsPart = (rawValue - minutes) * 100;
        const seconds = Math.round(secondsPart);

        // console.log(`[PostPlay] Raw: ${rawValue} -> ${minutes}m ${seconds}s -> Total: ${(minutes * 60) + seconds}s`);
        return (minutes * 60) + seconds;
    };

    const setupCustomControls = (playerInstance) => {
        const plyrContainer = playerInstance.elements.container;
        if (!plyrContainer) return;

        // --- FIX IPHONE: Sincronización manual de TextTracks ---
        const synchronizeNativeTracks = (activeIndex) => {
            const tracks = videoElement.textTracks;
            for (let i = 0; i < tracks.length; i++) {
                if (i === activeIndex) {
                    tracks[i].mode = 'showing';
                } else {
                    tracks[i].mode = 'hidden';
                }
            }
        };

        // 1. LIMPIEZA
        const oldUI = plyrContainer.querySelectorAll('.custom-video-overlay, .video-overlay-title, .seek-feedback, .btn-close-video, .netflix-menu-overlay, .btn-next-episode');
        oldUI.forEach(el => el.remove());

        // 2. CREAR EL OVERLAY PRINCIPAL (Botones Play/Pause)
        const overlay = document.createElement('div');
        overlay.className = 'custom-video-overlay';
        Object.assign(overlay.style, {
            position: 'absolute', top: '0', left: '0',
            width: '100%', height: '100%', margin: '0',
            transform: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center',
            gap: '2rem', zIndex: '50',
            pointerEvents: 'auto',
            background: 'rgba(0,0,0,0.01)', transition: 'opacity 0.2s ease',
            outline: 'none', webkitTapHighlightColor: 'transparent'
        });

        // 3. MENÚ DE OPCIONES (Audio/Subs)
        const menuOverlay = document.createElement('div');
        menuOverlay.className = 'netflix-menu-overlay';
        menuOverlay.innerHTML = `
            <div class="netflix-menu-container">
                <div class="netflix-col" id="col-audio"><h3>Audio</h3><div id="list-audio"></div></div>
                <div class="netflix-col" id="col-subs"><h3>Subtítulos</h3><div id="list-subs"></div></div>
            </div>
            <div style="margin-top: 2rem; color: #888; font-size: 0.8rem;">Toca fuera para cerrar</div>
        `;

        // 4. TÍTULO DEL VIDEO
        const anio = fechaObra ? fechaObra.substring(0, 4) : '';
        const titleDiv = document.createElement('div');
        titleDiv.className = 'video-overlay-title';
        titleDiv.innerText = anio ? `${tituloObra} (${anio})` : tituloObra;
        Object.assign(titleDiv.style, {
            position: 'absolute', top: '30px', left: '30px', pointerEvents: 'none',
            zIndex: '51', transition: 'opacity 0.2s ease'
        });
        plyrContainer.appendChild(titleDiv);

        // 5. BOTÓN CERRAR (Definido ANTES de updateVisibility)
        const closeVideoBtn = document.createElement('div');
        closeVideoBtn.className = 'btn-close-video';
        closeVideoBtn.innerHTML = '&times;';

        const handleClose = (e) => {
            e.stopPropagation();
            if (e.type === 'touchend') e.preventDefault();
            if (playerInstance.fullscreen.active) playerInstance.fullscreen.exit();
            playerInstance.destroy();
            if (hls) { hls.destroy(); hls = null; }
            player = null;
            const heroContainer = document.querySelector('.modal-hero');
            if (heroContainer) {
                heroContainer.querySelectorAll('video, .plyr').forEach(v => v.remove());
                heroContainer.classList.remove('video-activo');
            }
            if (modalImg) { modalImg.classList.remove('hidden'); modalImg.style.display = 'block'; }
            if (modalContentOverlay) modalContentOverlay.classList.remove('hidden');
        };

        closeVideoBtn.addEventListener('touchend', handleClose);
        closeVideoBtn.addEventListener('click', handleClose);
        plyrContainer.appendChild(closeVideoBtn);

        // ============================================================
        // === GESTIÓN CENTRALIZADA DE VISIBILIDAD ===
        // ============================================================
        const updateVisibility = () => {
            const isHidden = plyrContainer.classList.contains('plyr--hide-controls');
            const isMenuActive = menuOverlay.classList.contains('active');

            // Estado Global: ¿Debemos ocultar la interfaz?
            // Sí, si el autohide saltó (isHidden) O si el menú está abierto
            const shouldHideUI = isHidden || isMenuActive;

            // 1. Overlay Central (Play/Pause)
            overlay.style.opacity = shouldHideUI ? '0' : '1';

            // Lógica de interacción del overlay:
            if (isMenuActive) {
                overlay.style.pointerEvents = 'none'; // Si menú abierto, overlay transparente al click
            } else {
                overlay.style.pointerEvents = 'auto'; // Si menú cerrado, overlay captura toques para despertar
            }

            // 2. Botones internos (Play/Rewind) - Desactivar si no se ven
            const innerButtons = overlay.querySelectorAll('.custom-control-btn');
            innerButtons.forEach(btn => btn.style.pointerEvents = shouldHideUI ? 'none' : 'auto');

            // 3. Título y Botón Cerrar (AQUÍ ESTÁ LA SOLUCIÓN)
            // Ambos se ocultan si el menú está abierto o el autohide saltó
            const opacityValue = shouldHideUI ? '0' : '1';
            const pointerValue = shouldHideUI ? 'none' : 'auto';

            titleDiv.style.opacity = opacityValue;

            closeVideoBtn.style.opacity = opacityValue;
            closeVideoBtn.style.pointerEvents = pointerValue;
        };

        const observer = new MutationObserver(updateVisibility);
        observer.observe(plyrContainer, { attributes: true, attributeFilter: ['class'] });

        // ============================================================
        // === LOGICA DE TEMPORIZADOR (AUTOHIDE) ===
        // ============================================================
        let inactivityTimer;

        const hideControls = () => {
            if (playerInstance.playing && !menuOverlay.classList.contains('active')) {
                playerInstance.toggleControls(false);
            }
        };

        const resetInactivityTimer = () => {
            clearTimeout(inactivityTimer);
            if (playerInstance.paused || menuOverlay.classList.contains('active')) return;
            inactivityTimer = setTimeout(hideControls, 2500);
        };

        // Listeners Globales
        plyrContainer.addEventListener('mousemove', resetInactivityTimer);
        plyrContainer.addEventListener('touchstart', resetInactivityTimer, { passive: true });
        plyrContainer.addEventListener('touchmove', resetInactivityTimer, { passive: true });
        plyrContainer.addEventListener('click', resetInactivityTimer);

        playerInstance.on('play', resetInactivityTimer);
        playerInstance.on('pause', () => clearTimeout(inactivityTimer));
        playerInstance.on('controlshidden', () => clearTimeout(inactivityTimer));



        // ===============================================
        // === LÓGICA DE POST-PLAY (COLA / CRÉDITOS) ===
        // ===============================================
        let postPlayTriggered = false; // Flag para evitar múltiples ejecuciones
        let postPlayCancelled = false; // Si el usuario lo cerró manualmente


        playerInstance.on('timeupdate', () => {
            // 1. CONDICIÓN BÁSICA: Solo si NO se ha disparado y NO se ha cancelado
            if (postPlayTriggered || postPlayCancelled) return;

            // 2. CONDICIÓN DE TIEMPO: Dinámica
            const triggerSeconds = getPostPlayThreshold();
            const timeRemaining = playerInstance.duration - playerInstance.currentTime;

            // Usamos un buffer pequeño para asegurar que duración sea válida (>0)
            if (playerInstance.duration > 0 && timeRemaining <= triggerSeconds && timeRemaining > 0) {

                // 3. CONDICIÓN DE PANTALLA COMPLETA
                // Solo activamos si está en fullscreen
                if (!playerInstance.fullscreen.active) return;

                // 4. CONDICIÓN DE TIPO DE CONTENIDO
                let shouldTrigger = false;

                // Verificamos el contexto
                if (contexto && contexto.tipo === 'serie') {
                    // Es Serie: Solo si es el ULTIMO episodio de la ULTIMA temporada
                    // Necesitamos saber si es la última tempo y el último epi de esa tempo
                    const serie = contexto.serie;
                    const tempoActual = contexto.temporadaNumero; // Ojo: esto es número (1, 2...), indices son (0, 1...)
                    // Necesitamos comparar con el total de temporadas
                    const totalTemporadas = serie.temporadas.length;

                    // Si estamos en la última temporada
                    // (Nota: asumiendo que temporadas están en orden y el conteo coincide)
                    if (contexto.temporadaIndex === totalTemporadas - 1) {
                        // Ahora checamos si es el último episodio
                        const episodiosDeEstaTempo = serie.temporadas[contexto.temporadaIndex].episodios;
                        const totalEpisodios = episodiosDeEstaTempo.length;

                        if (contexto.episodioIndex === totalEpisodios - 1) {
                            shouldTrigger = true;
                            console.log("Post-Play Trigger: Es el final de la serie.");
                        }
                    }

                } else {
                    // Es Película (o no tiene contexto de serie): SIEMPRE activamos
                    shouldTrigger = true;
                }

                if (shouldTrigger) {
                    postPlayTriggered = true;
                    playerInstance.isVideoFinished = true; // Avisamos a timeupdate para que elimine progreso
                    // Pasamos 'tituloObra' para evitar recomendarnos a nosotros mismos
                    // Y pasamos callback para manejar el "Cancel" (resetear flags si fuera necesario, pero aquí solo ocultamos)
                    mostrarPostPlay(tituloObra, contexto, () => {
                        postPlayCancelled = true; // Callback de cancelación
                    });
                }
            }
        });

        // Reset flags si el usuario hace seek hacia atrás (antes de los 60s)
        // Reset flags si el usuario hace seek hacia atrás (antes del trigger)
        playerInstance.on('seeking', () => {
            const timeRemaining = playerInstance.duration - playerInstance.currentTime;
            const triggerSeconds = getPostPlayThreshold();

            if (timeRemaining > (triggerSeconds + 5)) { // Damos un margen de 5s
                postPlayTriggered = false;
                postPlayCancelled = false;
                playerInstance.isVideoFinished = false; // Reset flag
                ocultarPostPlay();
            }
        });

        // ============================================================
        // === INTERACCIÓN TOUCH (TOGGLE) ===
        // ============================================================
        const handleToggle = (e) => {
            if (e.target.closest('.plyr__controls') || menuOverlay.classList.contains('active')) return;

            const isHidden = plyrContainer.classList.contains('plyr--hide-controls');

            // Permitir clicks en botones si están visibles
            if (e.target.closest('.custom-control-btn') && !isHidden) return;

            e.stopPropagation();
            if (e.type === 'touchend' && e.cancelable) e.preventDefault();

            if (isHidden) {
                playerInstance.toggleControls(true);
                resetInactivityTimer();
            } else {
                playerInstance.toggleControls(false);
                clearTimeout(inactivityTimer);
            }
            setTimeout(updateVisibility, 10);
        };

        overlay.addEventListener('touchstart', (e) => {
            if (!e.target.closest('.custom-control-btn') || plyrContainer.classList.contains('plyr--hide-controls')) {
                e.stopPropagation();
            }
        }, { passive: false });

        overlay.addEventListener('touchend', handleToggle);
        overlay.addEventListener('click', handleToggle);

        menuOverlay.addEventListener('click', (e) => {
            if (e.target === menuOverlay) {
                menuOverlay.classList.remove('active');
                playerInstance.toggleControls(true);
                resetInactivityTimer();
                // Forzamos actualización visual al cerrar
                setTimeout(updateVisibility, 50);
            }
        });

        // RENDER DE CONTENIDO DEL OVERLAY
        overlay.innerHTML = `
            <div class="custom-control-btn" id="custom-rewind">⟲</div>
            <div class="custom-control-btn" id="custom-play-btn"><svg xmlns="http://www.w3.org/2000/svg" width="50" height="50" viewBox="0 0 20 20" style="pointer-events: none;"><path fill="#ffffff" d="m4 4l12 6l-12 6z"/></svg></div>
            <div class="custom-control-btn" id="custom-forward">⟳</div>
        `;

        // AGREGAR ELEMENTOS AL DOM
        plyrContainer.appendChild(menuOverlay);
        plyrContainer.appendChild(overlay);

        // FEEDBACK DE SEEK
        const fbLeft = document.createElement('div'); fbLeft.className = 'seek-feedback left'; fbLeft.innerText = '-10s';
        const fbRight = document.createElement('div'); fbRight.className = 'seek-feedback right'; fbRight.innerText = '+10s';
        plyrContainer.appendChild(fbLeft);
        plyrContainer.appendChild(fbRight);
        const triggerFeedbackLocal = (side) => {
            const el = plyrContainer.querySelector(`.seek-feedback.${side}`);
            if (el) { el.classList.remove('animate-feedback'); void el.offsetWidth; el.classList.add('animate-feedback'); }
        };

        // SETUP DE BOTONES
        const setupBtn = (id, action) => {
            const btn = overlay.querySelector(id);
            if (!btn) return;
            const handler = (e) => {
                e.stopPropagation();
                if (e.type === 'touchend') e.preventDefault();
                if (plyrContainer.classList.contains('plyr--hide-controls')) {
                    playerInstance.toggleControls(true);
                    resetInactivityTimer();
                    return;
                }
                action();
                resetInactivityTimer();
            };
            btn.addEventListener('touchstart', (e) => e.stopPropagation(), { passive: false });
            btn.addEventListener('touchend', handler);
            btn.addEventListener('click', handler);
        };

        setupBtn('#custom-play-btn', () => playerInstance.togglePlay());
        const btnPlay = overlay.querySelector('#custom-play-btn');
        // Usamos innerHTML para reemplazar el icono completo
        playerInstance.on('play', () => {
            if (btnPlay) btnPlay.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="50" viewBox="0 0 20 20" style="pointer-events: none;"><path fill="#ffffff" d="M5 4h3v12H5V4zm7 0h3v12h-3V4z"/></svg>';
            resetInactivityTimer();
        });
        playerInstance.on('pause', () => {
            if (btnPlay) btnPlay.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="50" viewBox="0 0 20 20" style="pointer-events: none;"><path fill="#ffffff" d="m4 4l12 6l-12 6z"/></svg>';
            clearTimeout(inactivityTimer);
        });

        setupBtn('#custom-rewind', () => { playerInstance.rewind(10); triggerFeedbackLocal('left'); });
        setupBtn('#custom-forward', () => { playerInstance.forward(10); triggerFeedbackLocal('right'); });

        // RENDER MENU OPTIONS (Necesario para el botón de settings)
        const renderMenuOptions = () => {
            const listAudio = menuOverlay.querySelector('#list-audio');
            const listSubs = menuOverlay.querySelector('#list-subs');
            listAudio.innerHTML = ''; listSubs.innerHTML = '';

            // AUDIOS
            if (hls && hls.audioTracks && hls.audioTracks.length > 0) {
                hls.audioTracks.forEach((track, index) => {
                    const div = document.createElement('div');
                    div.className = `netflix-option ${hls.audioTrack === index ? 'selected' : ''}`;
                    div.innerText = track.name;
                    div.onclick = (e) => { e.stopPropagation(); hls.audioTrack = index; mostrarToast(`Audio: ${track.name}`); renderMenuOptions(); };
                    listAudio.appendChild(div);
                });
            } else { listAudio.innerHTML = '<div class="netflix-option selected">Original</div>'; }

            // SUBTÍTULOS
            const isOff = !playerInstance.captions.active;
            const offDiv = document.createElement('div');
            offDiv.className = `netflix-option ${isOff ? 'selected' : ''}`;
            offDiv.innerText = "Desactivado";
            offDiv.onclick = (e) => {
                e.stopPropagation();
                playerInstance.toggleCaptions(false);
                playerInstance.currentTrack = -1;
                synchronizeNativeTracks(-1); // Desactivar nativos
                renderMenuOptions();
            };
            listSubs.appendChild(offDiv);

            if (subtitulos.length > 0) {
                subtitulos.forEach((sub, idx) => {
                    const isActive = playerInstance.captions.active && playerInstance.currentTrack === idx;
                    const div = document.createElement('div');
                    div.className = `netflix-option ${isActive ? 'selected' : ''}`;
                    div.innerText = sub.label;
                    div.onclick = (e) => {
                        e.stopPropagation();
                        playerInstance.currentTrack = idx;
                        playerInstance.toggleCaptions(true);
                        synchronizeNativeTracks(idx); // Sincronizar nativos para Safari
                        mostrarToast(`Subtítulos: ${sub.label}`);
                        renderMenuOptions();
                    };
                    listSubs.appendChild(div);
                });
            }
        };

        // BOTÓN SETTINGS (Integrado en barra)
        const controlsBar = plyrContainer.querySelector('.plyr__controls');
        const volumeControl = plyrContainer.querySelector('.plyr__volume');
        if (controlsBar && volumeControl) {
            const btnSettings = document.createElement('button');
            btnSettings.className = 'plyr__controls__item plyr__control plyr-custom-btn';
            btnSettings.type = 'button';
            btnSettings.innerHTML = `<svg viewBox="0 0 24 24"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/><path d="M7 9h2v2H7zm4 0h2v2h-2zm4 0h2v2h-2z"/></svg>`;
            volumeControl.parentNode.insertBefore(btnSettings, volumeControl.nextSibling);

            btnSettings.addEventListener('click', (e) => {
                e.stopPropagation();
                playerInstance.pause();
                renderMenuOptions();
                menuOverlay.classList.add('active');

                // Forzamos actualización visual inmediata
                updateVisibility();
                playerInstance.toggleControls(false);
            });
        }

        // Inicializar estado visual
        updateVisibility();
    };

    const configurarEventosPlyr = (plyrInstance) => {
        // CORRECCION: Definir plyrContainer para usarlo en los eventos
        const plyrContainer = plyrInstance.elements.container;

        // === FORZAR TAMAÑO DE SUBTÍTULOS (JS) ===
        const updateSubtitleStyles = () => {
            const isFullscreen = plyrInstance.fullscreen.active;
            const size = isFullscreen ? '5vh' : ''; // 5vh en full, default en normal

            // 1. Contenedor de Plyr
            const captionContainer = plyrContainer.querySelector('.plyr__captions');
            if (captionContainer) {
                captionContainer.style.fontSize = size;
                // Forzar a los hijos también
                Array.from(captionContainer.querySelectorAll('*')).forEach(el => {
                    el.style.fontSize = size;
                    el.style.lineHeight = 'normal';
                });
            }

            // 2. Webkit Text Tracks (Nativo) - Intentamos injectar estilo si es posible
            // (Esto es más difícil desde JS puro para shadow DOM, pero dejamos el intento)
        };

        plyrInstance.on('enterfullscreen', () => {
            setTimeout(updateSubtitleStyles, 100); // Pequeño delay para asegurar render
            setTimeout(updateSubtitleStyles, 500);
        });
        plyrInstance.on('exitfullscreen', () => {
            setTimeout(updateSubtitleStyles, 100);
        });
        plyrInstance.on('captionsenabled', updateSubtitleStyles);
        plyrInstance.on('languagechange', updateSubtitleStyles);
        // =========================================

        // VARIABLES PARA LÓGICA DE 10 SEGUNDOS
        let sessionWatchTime = 0;       // Tiempo visto en esta sesión (acumulado)
        let lastTimeUpdate = 0;         // Para calcular delta
        let hasReachedThreshold = false; // Flag para saber si ya cruzamos los 10s

        let hasResumed = false; // Flag para evitar múltiples saltos

        // LÓGICA DE REANUDACIÓN ROBUSTA (Para HLS y MP4)
        const attemptResume = () => {
            if (hasResumed) return; // Si ya reanudamos, no hacer nada

            const savedTime = getVideoProgress(videoId);
            const duration = plyrInstance.duration;

            // Reanudamos si:
            // 1. Hay un tiempo guardado (> 0)
            // 2. Y (No sabemos la duración aun [HLS start] O estamos en rango válido [antes del final])
            if (savedTime > 0 && (!duration || duration === 0 || savedTime < (duration - 10))) {
                console.log(`Intentando reanudar en: ${savedTime}s (Duración actual: ${duration})`);
                plyrInstance.currentTime = savedTime;
                hasResumed = true; // Marcar como realizado
            }
        };

        plyrInstance.on('ready', () => {
            setupCustomControls(plyrInstance);
            if (typeof injectControlBarNextButton === 'function') injectControlBarNextButton(plyrInstance, contexto);


            // --- ACTIVAR SUBTÍTULOS POR DEFECTO ---
            const defaultSubIndex = subtitulos.findIndex(s => s.default === true);
            if (defaultSubIndex !== -1) {
                setTimeout(() => {
                    plyrInstance.currentTrack = defaultSubIndex;
                    plyrInstance.toggleCaptions(true);
                    synchronizeNativeTracks(defaultSubIndex); // Inicializar nativos
                }, 200);
            } else {
                plyrInstance.toggleCaptions(false);
                synchronizeNativeTracks(-1);
            }

            // FIX: Red de seguridad - Si el resume nivel 1 (HLS) falló
            const savedTime = getVideoProgress(videoId);
            if (savedTime > 10 && plyrInstance.currentTime < 5) {
                console.log("Resume callback (safety check):", savedTime);
                plyrInstance.currentTime = savedTime;
            }
        });

        // Intentar reanudar cuando tengamos metadata (Más confiable para HLS)
        plyrInstance.on('loadedmetadata', attemptResume);

        // Último intento al empezar a reproducir
        plyrInstance.once('playing', attemptResume);

        plyrInstance.on('playing', () => {
            lastTimeUpdate = plyrInstance.currentTime;
        });

        plyrInstance.on('timeupdate', event => {
            if (!plyrInstance.playing) return;

            // 1. LÓGICA DE UMBRAL DE 10 SEGUNDOS
            const currentTime = plyrInstance.currentTime;

            // Calculamos cuánto avanzó desde el último update (normalmente 0.25s)
            // Filtramos saltos grandes (seek) para que no cuenten como "visto"
            const delta = Math.abs(currentTime - lastTimeUpdate);

            if (delta < 1.0) { // Solo sumamos si es reproducción continua normal
                sessionWatchTime += delta;
            }
            lastTimeUpdate = currentTime;

            // Si llegamos a 10s acumulados, activamos el guardado
            if (sessionWatchTime >= 10) {
                hasReachedThreshold = true;
            }

            // LÓGICA DE FINALIZACIÓN (PRIORIDAD ALTA)
            // (Eliminado: delegamos el borrado al momento exacto en el que aparecen los botones de Post-Play/Next Episode)

            // === LÓGICA DE SIGUIENTE EPISODIO (DURANTE CRÉDITOS) ===
            // console.log("TimeUpdate ctx:", contexto, "Duration:", plyrInstance.duration, "Current:", plyrInstance.currentTime);

            let esMomentoCreditos = false;

            if (contexto && contexto.tipo === 'serie') {
                const duration = plyrInstance.duration;
                const currentTime = plyrInstance.currentTime;

                // Si la duración no es válida (ej. stream infinito o error), abortar
                if (!duration || isNaN(duration) || duration <= 0) return;

                const timeLeft = duration - currentTime;
                let UMBRAL_CREDITOS = 60; // Default: 60 segundos
                let usarHeuristica = true;

                // Intentar obtener config específica del episodio
                if (contexto.serie &&
                    contexto.serie.temporadas &&
                    contexto.serie.temporadas[contexto.temporadaIndex] &&
                    contexto.serie.temporadas[contexto.temporadaIndex].episodios &&
                    contexto.serie.temporadas[contexto.temporadaIndex].episodios[contexto.episodioIndex]) {

                    const epData = contexto.serie.temporadas[contexto.temporadaIndex].episodios[contexto.episodioIndex];

                    // Si existe el parámetro time_next_episode (formato M.SS)
                    if (epData.time_next_episode && !isNaN(epData.time_next_episode)) {
                        let timeValue = epData.time_next_episode;
                        let minutos = Math.floor(timeValue);
                        let segundos = Math.round((timeValue - minutos) * 100);
                        UMBRAL_CREDITOS = (minutos * 60) + segundos;
                        usarHeuristica = false; // Ya tenemos dato preciso, ignorar %
                        console.log("Usando tiempo personalizado Next Episode:", UMBRAL_CREDITOS, "segundos");
                    }
                }

                // Calcular porcentaje visto (0 a 1)
                const porcentajeVisto = (currentTime / duration);

                // CRITERIO:
                // 1. Si hay dato preciso: Faltan X segundos (UMBRAL_CREDITOS)
                // 2. Si NO hay dato: Faltan 60s O se vio el 95%
                if (!usarHeuristica) {
                    esMomentoCreditos = (timeLeft <= UMBRAL_CREDITOS);
                } else {
                    esMomentoCreditos = (timeLeft <= UMBRAL_CREDITOS) || (porcentajeVisto >= 0.95);
                }

                // Buscar si ya existe el botón
                let btnNext = plyrContainer.querySelector('.btn-next-episode');

                // Mostrar botón
                if (esMomentoCreditos && timeLeft > 0) {
                    if (!btnNext) {
                        console.log("Intentando mostrar botón Next Episode...");
                        mostrarBotonSiguiente(plyrInstance, contexto);
                    } else if (!btnNext.classList.contains('visible')) {
                        console.log("Haciendo visible el botón Next Episode existente");
                        btnNext.classList.add('visible');
                    }
                }
                // Ocultar botón si no cumple condición (retrocedió)
                else {
                    if (btnNext && btnNext.classList.contains('visible')) {
                        console.log("Ocultando botón Next Episode (usuario retrocedió)");
                        btnNext.classList.remove('visible');

                        // Deshacer la precarga del siguiente episodio
                        if (plyrInstance.nextEpisodeQueuedId) {
                            removeVideoProgress(plyrInstance.nextEpisodeQueuedId);
                            plyrInstance.nextEpisodeQueued = false;
                            plyrInstance.nextEpisodeQueuedId = null;
                            console.log("Precarga del siguiente episodio cancelada.");
                        }
                    }
                }
            }

            // ForceFinish si el botón de Post Play (Movie) o Siguiente Episodio (Serie) está visible
            const forceFinish = (plyrInstance.isVideoFinished === true) || esMomentoCreditos;

            // LÓGICA DE GUARDADO (sessionWatchTime >= 10s O se forzó finalización)
            if (hasReachedThreshold || forceFinish) {
                // Preparamos metadata extra para la UI de "Continuar viendo"
                const metadata = {
                    titulo: tituloObra,
                    fecha: fechaObra,
                    portada: contexto?.serie?.portada || contexto?.pelicula?.portada,
                    backdrop: contexto?.serie?.backdrop || contexto?.pelicula?.backdrop,
                    // Logica Serie
                    esSerie: contexto && contexto.tipo === 'serie',
                    temporadaStr: contexto && contexto.tipo === 'serie' ? `T${contexto.temporadaNumero}:E${contexto.episodioNumero}` : null,
                    subtitulo: contexto && contexto.tipo === 'serie' ? contexto.serie.titulo : null
                };

                saveVideoProgress(videoId, currentTime, plyrInstance.duration, metadata, forceFinish);
            }
        });

        plyrInstance.on('ended', () => {
            console.log("Video finalizado");
            removeVideoProgress(videoId);
            // Backup por si acaso no le dio click
            if (contexto && contexto.tipo === 'serie') {
                console.log("Fin de episodio serie. Contexto:", contexto);
            }
        });
    };

    // --- BARRA DE CONTROLES ---
    const injectControlBarNextButton = (playerInst, ctx) => {
        if (!ctx || ctx.tipo !== 'serie') return;

        const plyrContainer = playerInst.elements.container;
        const controls = plyrContainer.querySelector('.plyr__controls');
        if (!controls) return;

        // Verificamos si ya existe
        if (controls.querySelector('.btn-control-next-ep')) return;

        // Calculamos índices del siguiente
        let nextSeasonIdx = parseInt(ctx.temporadaIndex);
        let nextEpisodeIdx = parseInt(ctx.episodioIndex) + 1;
        let nextEpData = null;

        if (ctx.serie && ctx.serie.temporadas && ctx.serie.temporadas[nextSeasonIdx]) {
            const currentSeasonEvents = ctx.serie.temporadas[nextSeasonIdx];
            if (currentSeasonEvents.episodios && currentSeasonEvents.episodios[nextEpisodeIdx]) {
                nextEpData = currentSeasonEvents.episodios[nextEpisodeIdx];
            } else {
                // Siguiente temporada
                nextSeasonIdx++;
                nextEpisodeIdx = 0;
                if (ctx.serie.temporadas[nextSeasonIdx] &&
                    ctx.serie.temporadas[nextSeasonIdx].episodios &&
                    ctx.serie.temporadas[nextSeasonIdx].episodios[0]) {
                    nextEpData = ctx.serie.temporadas[nextSeasonIdx].episodios[0];
                }
            }
        }

        if (nextEpData) {
            console.log("Inyectando botón Next Episode en barra de controles");

            // Crear Botón
            const btn = document.createElement('button');
            btn.className = 'plyr__controls__item plyr__control btn-control-next-ep';
            btn.type = 'button';
            btn.setAttribute('data-plyr-tooltip', 'Siguiente Episodio');
            // Icono SVG
            btn.innerHTML = `
                <svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg> 
            `;

            btn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();

                const nuevoContexto = {
                    ...ctx,
                    temporadaIndex: nextSeasonIdx,
                    episodioIndex: nextEpisodeIdx,
                    temporadaNumero: ctx.serie.temporadas[nextSeasonIdx].numero,
                    episodioNumero: nextEpData.episodio
                };
                const tituloRep = `T${nuevoContexto.temporadaNumero}:E${nuevoContexto.episodioNumero} - ${nextEpData.titulo}`;

                // Guardar Last Watched
                saveLastEpisode(ctx.serie.titulo, {
                    seasonIndex: nextSeasonIdx,
                    episodeIndex: nextEpisodeIdx,
                    seasonNumber: nuevoContexto.temporadaNumero,
                    episodeNumber: nuevoContexto.episodioNumero,
                    titulo: nextEpData.titulo,
                    streamUrl: nextEpData.streamUrl,
                    fechaSerie: ctx.serie.fecha
                });

                // Actualizar UI
                const listaContainer = document.getElementById('lista-episodios');
                if (listaContainer) {
                    const allRows = listaContainer.querySelectorAll('.episodio-item');
                    allRows.forEach(r => r.classList.remove('active-episode'));
                    // Nota: Si cambió de temporada, el índice visual puede no coincidir si no recargamos la lista.
                    // Pero inicarReproduccion no recarga el modal, así que "nextEpisodeIdx" es válido solo si es la misma temporada.
                    // Idealmente deberíamos actualizar el select de temporada si cambió.
                    // Como parche rápido visual:
                    if (nuevoContexto.temporadaIndex === ctx.temporadaIndex && allRows[nextEpisodeIdx]) {
                        allRows[nextEpisodeIdx].classList.add('active-episode');
                    }
                }

                iniciarReproduccion(nextEpData.streamUrl, tituloRep, ctx.serie.fecha, nextEpData.subtitulos || [], nuevoContexto);
            });

            // Insertar antes del volumen
            const vol = controls.querySelector('.plyr__volume');
            if (vol) {
                controls.insertBefore(btn, vol);
            } else {
                controls.appendChild(btn);
            }
        }
    };

    // Función auxiliar para calcular y mostrar el botón
    const mostrarBotonSiguiente = (playerInst, ctx) => {
        const plyrContainer = playerInst.elements.container;

        // Calcular índices del siguiente (asegurando enteros)
        let nextSeasonIdx = parseInt(ctx.temporadaIndex);
        let nextEpisodeIdx = parseInt(ctx.episodioIndex) + 1;

        // Verificar si existe episodio en esta temporada
        let nextEpData = null;
        if (ctx.serie && ctx.serie.temporadas && ctx.serie.temporadas[nextSeasonIdx]) {
            const currentSeasonEvents = ctx.serie.temporadas[nextSeasonIdx];
            if (currentSeasonEvents.episodios && currentSeasonEvents.episodios[nextEpisodeIdx]) {
                nextEpData = currentSeasonEvents.episodios[nextEpisodeIdx];
            } else {
                // Revisar siguiente temporada
                nextSeasonIdx++;
                nextEpisodeIdx = 0;
                if (ctx.serie.temporadas[nextSeasonIdx] &&
                    ctx.serie.temporadas[nextSeasonIdx].episodios &&
                    ctx.serie.temporadas[nextSeasonIdx].episodios[0]) {
                    nextEpData = ctx.serie.temporadas[nextSeasonIdx].episodios[0];
                }
            }
        }

        if (nextEpData) {
            console.log("Siguiente episodio encontrado:", nextEpData.titulo);

            // === NUEVO: PRECARGAMOS EL SIGUIENTE EPISODIO EN "CONTINUAR VIENDO" ===
            if (!playerInst.nextEpisodeQueued) {
                playerInst.nextEpisodeQueued = true;
                const nuevoTemporadaNumero = ctx.serie.temporadas[nextSeasonIdx].numero;
                const nuevoEpisodioNumero = nextEpData.episodio;
                const tituloRep = `T${nuevoTemporadaNumero}:E${nuevoEpisodioNumero} - ${nextEpData.titulo}`;
                const nextVideoId = tituloRep.trim().replace(/\s/g, '_').toLowerCase() + '_' + ctx.serie.fecha;

                playerInst.nextEpisodeQueuedId = nextVideoId;

                const nextMetadata = {
                    titulo: tituloRep,
                    fecha: ctx.serie.fecha,
                    portada: ctx.serie.portada,
                    backdrop: ctx.serie.backdrop,
                    esSerie: true,
                    temporadaStr: `T${nuevoTemporadaNumero}:E${nuevoEpisodioNumero}`,
                    subtitulo: ctx.serie.titulo
                };

                // Lo guardamos con progreso de 1 segundo para forzar su aparición en la lista
                saveVideoProgress(nextVideoId, 1, 0, nextMetadata, false);

                // IMPORTANTE: También actualizamos el historial de series para que al abrir el modal 
                // ya esté seleccionado este nuevo episodio
                saveLastEpisode(ctx.serie.titulo, {
                    seasonIndex: nextSeasonIdx,
                    episodeIndex: nextEpisodeIdx,
                    seasonNumber: nuevoTemporadaNumero,
                    episodeNumber: nuevoEpisodioNumero,
                    titulo: nextEpData.titulo,
                    streamUrl: nextEpData.streamUrl,
                    fechaSerie: ctx.serie.fecha
                });

                console.log("Siguiente episodio pre-encolado en Continuar Viendo:", tituloRep);
            }

            // CREAR BOTÓN
            const btn = document.createElement('div');
            btn.className = 'btn-next-episode';
            btn.innerHTML = `
                <span>Siguiente Episodio</span>
                <svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg>
            `;

            btn.addEventListener('click', (e) => {
                e.stopPropagation();

                // Preparar nuevo contexto
                const nuevoContexto = {
                    ...ctx,
                    temporadaIndex: nextSeasonIdx,
                    episodioIndex: nextEpisodeIdx,
                    temporadaNumero: ctx.serie.temporadas[nextSeasonIdx].numero,
                    episodioNumero: nextEpData.episodio
                };

                const tituloRep = `T${nuevoContexto.temporadaNumero}:E${nuevoContexto.episodioNumero} - ${nextEpData.titulo}`;

                // Guardar "Last Watched" del nuevo
                saveLastEpisode(ctx.serie.titulo, {
                    seasonIndex: nextSeasonIdx,
                    episodeIndex: nextEpisodeIdx,
                    seasonNumber: nuevoContexto.temporadaNumero,
                    episodeNumber: nuevoContexto.episodioNumero,
                    titulo: nextEpData.titulo,
                    streamUrl: nextEpData.streamUrl,
                    fechaSerie: ctx.serie.fecha
                });

                // ACTUALIZAR UI LISTA EPISODIOS (SINCRONIZACIÓN)
                const listaContainer = document.getElementById('lista-episodios');
                if (listaContainer) {
                    const allRows = listaContainer.querySelectorAll('.episodio-item');
                    allRows.forEach(r => r.classList.remove('active-episode'));

                    // Si estamos en la misma temporada visualmente, podemos activar el siguiente item
                    // Nota: Si cambia de temporada (ej: Temp 1 a Temp 2), el dropdown no cambia solo,
                    // pero al menos iluminamos el botón si la lista es continua o se recarga.
                    // Para simplificar, solo activamos si el índice existe en la lista actual.
                    if (allRows[nextEpisodeIdx]) {
                        allRows[nextEpisodeIdx].classList.add('active-episode');
                        // allRows[nextEpisodeIdx].scrollIntoView({ behavior: 'smooth', block: 'center' });
                    }
                }

                // Reproducir siguiente
                iniciarReproduccion(nextEpData.streamUrl, tituloRep, ctx.serie.fecha, nextEpData.subtitulos || [], nuevoContexto);
            });

            // Añadir al contenedor
            plyrContainer.appendChild(btn);

            // Forzar reflow y activar animación
            void btn.offsetWidth;
            btn.classList.add('visible');
        }
    };

    if (Hls.isSupported()) {
        if (hls) hls.destroy();
        hls = new Hls({
            enableWorker: true,
            lowLatencyMode: true,
            xhrSetup: function (xhr, url) { xhr.withCredentials = false; }
        });
        hls.loadSource(urlConUsuario);
        hls.attachMedia(videoElement);

        hls.on(Hls.Events.ERROR, function (event, data) {
            console.error("HLS Error details:", data);
            if (data.fatal) {
                switch (data.type) {
                    case Hls.ErrorTypes.NETWORK_ERROR:
                        console.log("Fatal network error encountered, trying to recover");
                        hls.startLoad();
                        break;
                    case Hls.ErrorTypes.MEDIA_ERROR:
                        console.log("Fatal media error encountered, trying to recover");
                        hls.recoverMediaError();
                        break;
                    default:
                        console.log("Fatal error, cannot recover");
                        hls.destroy();
                        break;
                }
            }
        });

        hls.on(Hls.Events.MANIFEST_PARSED, function (event, data) {
            // FIX: Intentamos setear el tiempo ANTES de iniciar Plyr para HLS
            const savedTime = getVideoProgress(videoId);
            if (savedTime > 0) {
                videoElement.currentTime = savedTime;
            }

            if (player) player.destroy();
            player = new Plyr(videoElement, defaultOptions);
            configurarEventosPlyr(player);
            videoElement.play().catch(() => console.log("Autoplay bloqueado"));
        });
    } else if (videoElement.canPlayType('application/vnd.apple.mpegurl')) {
        videoElement.src = urlConUsuario;
        if (player) player.destroy();
        player = new Plyr(videoElement, defaultOptions);
        configurarEventosPlyr(player);
        videoElement.play();
    }
}

function formatTime(seconds) {
    const date = new Date(0);
    date.setSeconds(seconds);
    const timeString = date.toISOString().substr(11, 8);
    return timeString.startsWith("00:") ? timeString.substr(3) : timeString;
}

// === LOGICA DE PELÍCULAS SIMILARES ===
function generarSimilares(peliculaActual) {
    const contenedor = document.getElementById('grid-similares');
    if (!contenedor) return;

    contenedor.innerHTML = '';

    if (typeof globalData === 'undefined' || globalData.length === 0) {
        console.warn("No hay datos globales para buscar similares");
        return;
    }

    // Filtración: 
    const similares = globalData.filter(item => {
        if (item.titulo === peliculaActual.titulo) return false;

        // Ver si hay intersección de géneros
        const tienenGeneroComun = item.genero.some(g => peliculaActual.genero.includes(g));
        return tienenGeneroComun;
    });

    // Tomar solo los últimos 6 agregados (orden inverso del JSON) para no saturar
    const seleccionadas = similares.reverse().slice(0, 6);

    if (seleccionadas.length === 0) {
        contenedor.innerHTML = '<p style="color: #777;">No hay títulos similares disponibles.</p>';
        return;
    }

    seleccionadas.forEach(sim => {
        const card = document.createElement('div');
        card.classList.add('card-similar');
        card.innerHTML = `
            <img src="${sim.portada}" alt="${sim.titulo}">
            <div class="card-similar-info">
                <div class="card-similar-title">${sim.titulo}</div>
            </div>
        `;

        card.addEventListener('click', () => {
            const modalOverlay = document.getElementById('modal-info');
            if (modalOverlay) modalOverlay.scrollTo(0, 0);

            abrirModal(sim);
        });

        contenedor.appendChild(card);
    });
}

// === FUNCIÓN CERRAR MODAL ===
function cerrarModal() {
    window.currentMediaWatching = 'Ninguna';
    limpiarUrlAlCerrar();

    if (modalOverlay) modalOverlay.classList.add('hidden');
    document.body.style.overflow = 'auto';

    if (player) {
        try { player.destroy(); } catch (e) { }
        player = null;
    }
    if (hls) {
        try { hls.destroy(); } catch (e) { }
        hls = null;
    }

    // Limpieza (Borrar cualquier rastro de video)
    const heroContainer = document.querySelector('.modal-hero');
    if (heroContainer) {
        const videos = heroContainer.querySelectorAll('video, .plyr');
        videos.forEach(v => v.remove());

        heroContainer.classList.remove('video-activo');
    }

    // Restaurar portada
    if (modalImg) {
        modalImg.classList.remove('hidden');
        modalImg.style.display = 'block';
    }
    if (modalContentOverlay) modalContentOverlay.classList.remove('hidden');

    if (modalVideo) {
        modalVideo.classList.add('hidden');
        modalVideo.removeAttribute('src');
    }
}

// Event Listeners para cerrar
if (btnCerrar) btnCerrar.addEventListener('click', cerrarModal);

if (modalOverlay) {
    modalOverlay.addEventListener('click', (e) => {
        if (e.target === modalOverlay) cerrarModal();
    });
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && modalOverlay && !modalOverlay.classList.contains('hidden')) {
        cerrarModal();
    }
});

// Listener del botón favorito del modal 
const btnFavModalGlobal = document.getElementById('modal-btn-favorito');
if (btnFavModalGlobal) {
    btnFavModalGlobal.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btnFavModalGlobal.dataset.id;
        if (typeof toggleFavorito === 'function') {
            const isNowFavorito = toggleFavorito(id);
            btnFavModalGlobal.src = isNowFavorito ? "Multimedia/star_r.svg" : "Multimedia/star.svg";

            document.querySelectorAll(`.icono-favorito[data-id="${id}"]`).forEach(icon => {
                icon.src = isNowFavorito ? "Multimedia/star_r.svg" : "Multimedia/star.svg";
                icon.classList.toggle("favorito", isNowFavorito);
            });

            const esVistaFavoritos = document.querySelector(".seccion-favoritos") !== null;
            if (esVistaFavoritos && !isNowFavorito) {
                const card = document.querySelector(`.tarjeta[data-id="${id}"]`);
                if (card) card.style.opacity = "0.5";
            }
        }
    });
}

// ==========================================
// === CONTROL DE TECLADO ===
// ==========================================

document.addEventListener('keydown', (event) => {

    if (!modalOverlay || modalOverlay.classList.contains('hidden')) return;
    if (!player || !player.elements || !player.elements.container) return;

    const container = player.elements.container;

    const animarFeedback = (side) => {
        const el = container.querySelector(`.seek-feedback.${side}`);
        if (el) {
            el.classList.remove('animate-feedback');
            void el.offsetWidth;
            el.classList.add('animate-feedback');
        }
    };

    switch (event.code) {
        case 'Space':
            event.preventDefault();
            event.stopPropagation();
            player.togglePlay();

            const btnPlay = container.querySelector('#custom-play-btn');
            if (btnPlay) {
                btnPlay.style.transform = "scale(1.2)";
                setTimeout(() => btnPlay.style.transform = "scale(1)", 200);
            }
            break;

        case 'ArrowRight':
            event.preventDefault();
            event.stopPropagation();
            player.forward(10);
            animarFeedback('right');
            break;

        case 'ArrowLeft':
            event.preventDefault();
            event.stopPropagation();
            player.rewind(10);
            animarFeedback('left');
            break;

        case 'ArrowUp':
            event.preventDefault(); // Evita scroll de la página
            event.stopPropagation();
            player.increaseVolume(0.1); // Sube un 10%
            break;

        case 'ArrowDown':
            event.preventDefault(); // Evita scroll de la página
            event.stopPropagation();
            player.decreaseVolume(0.1); // Baja un 10%
            break;

        case 'Escape':
            cerrarModal();
            break;
    }
}, true);

// ==========================================
// 🛠️ LÓGICA DE CONFIGURAR PERFIL (UNIFICADA)
// ==========================================

const modalEdit = document.getElementById('modal-edit-user');
const btnCancelEdit = document.getElementById('btn-cancel-edit');
const btnSaveAll = document.getElementById('btn-save-all');
const editProfileImg = document.getElementById('edit-modal-profile-img');
const btnChangePhotoEdit = document.getElementById('btn-change-photo-edit');
const currentUsernameDisplay = document.getElementById('current-username-display');
const btnTriggerNameChange = document.getElementById('btn-trigger-name-change');
const nameChangeFields = document.getElementById('name-change-fields');
const inputNewUser = document.getElementById('input-new-username');
const inputConfirmPass = document.getElementById('input-confirm-password');
const editFeedback = document.getElementById('edit-feedback');

const PROFILE_IMAGES = [
    "alucard.jpg", "chunchi.jpg", "daria.jpg", "elliot.jpg", "godz.jpg",
    "knight.jpg", "pennywise.jpg", "pirate.jpg", "princess.jpg", "superman.jpg"
];

let selectedProfilePic = "";
let gridSelectedPic = "";

function renderProfileOptions() {
    const grid = document.getElementById("profile-options-grid");
    const btnSaveProfile = document.getElementById("btn-save-profile");
    if (!grid) return;
    grid.innerHTML = "";

    // Al abrir, reseteamos la selección local al valor actual
    gridSelectedPic = tempSelectedPic;
    if (btnSaveProfile) btnSaveProfile.disabled = true;

    PROFILE_IMAGES.forEach(imgName => {
        const div = document.createElement("div");
        div.className = `profile-option ${imgName === gridSelectedPic ? "active" : ""}`;
        div.innerHTML = `<img src="Multimedia/Profiles/${imgName}" alt="${imgName}">`;

        div.onclick = () => {
            document.querySelectorAll(".profile-option").forEach(opt => opt.classList.remove("active"));
            div.classList.add("active");
            gridSelectedPic = imgName;
            if (btnSaveProfile) btnSaveProfile.disabled = false;
        };
        grid.appendChild(div);
    });
}

function openEditProfileModal() {
    const user = JSON.parse(localStorage.getItem('vanacue_user') || '{}');
    modalEdit.classList.remove('hidden');

    // Reset fields
    tempSelectedPic = user.profile_pic || "alucard.jpg";
    editProfileImg.src = `Multimedia/Profiles/${tempSelectedPic}`;
    currentUsernameDisplay.innerText = user.username;
    inputNewUser.value = user.username;
    inputConfirmPass.value = "";
    editFeedback.innerText = "";

    nameChangeFields.classList.remove('visible');
    // Si hay un modal de config desplegable, lo cerramos
    const configModal = document.getElementById('config-modal');
    if (configModal) configModal.classList.add('hidden');
}

if (btnCancelEdit) btnCancelEdit.onclick = () => modalEdit.classList.add('hidden');

// Toggle campos de nombre
if (btnTriggerNameChange) {
    btnTriggerNameChange.onclick = () => {
        nameChangeFields.classList.toggle('visible');
        if (nameChangeFields.classList.contains('visible')) {
            inputNewUser.focus();
        }
    };
}

// Abrir selector de foto (reutilizamos el modal que creamos antes)
if (btnChangePhotoEdit) {
    btnChangePhotoEdit.onclick = () => {
        const modalSelect = document.getElementById('modal-select-profile');
        if (typeof renderProfileOptions === 'function' && modalSelect) {
            renderProfileOptions();
            modalSelect.classList.remove('hidden');

            // Configurar botones del modal de selección UNA SOLA VEZ
            const btnCancelProfile = document.getElementById('btn-cancel-profile');
            const btnSaveProfile = document.getElementById('btn-save-profile');

            if (btnCancelProfile) {
                btnCancelProfile.onclick = () => modalSelect.classList.add('hidden');
            }
            if (btnSaveProfile) {
                btnSaveProfile.onclick = () => {
                    if (gridSelectedPic) {
                        tempSelectedPic = gridSelectedPic;
                        const editModalImg = document.getElementById('edit-modal-profile-img');
                        if (editModalImg) editModalImg.src = `Multimedia/Profiles/${tempSelectedPic}`;
                        modalSelect.classList.add('hidden');
                    }
                };
            }
        }
    };
}

// Sobrescribimos la lógica del selector de fotos para que actualice el modal de edición
window.handleProfileSelection = function (imgName) {
    tempSelectedPic = imgName;
    editProfileImg.src = `Multimedia/Profiles/${imgName}`;
    document.getElementById('modal-select-profile').classList.add('hidden');
    if (typeof mostrarToast === 'function') mostrarToast("Imagen seleccionada.");
};

if (btnSaveAll) {
    btnSaveAll.onclick = async () => {
        const user = JSON.parse(localStorage.getItem('vanacue_user') || '{}');
        const token = localStorage.getItem('vanacue_token');
        let photoChanged = (tempSelectedPic !== user.profile_pic);
        let nameChanged = (nameChangeFields.classList.contains('visible') && inputNewUser.value.trim() !== user.username);

        if (!photoChanged && !nameChanged) {
            modalEdit.classList.add('hidden');
            return;
        }

        editFeedback.innerText = "Guardando cambios...";
        editFeedback.style.color = "#fff";

        try {
            // 1. Foto (No requiere pass)
            if (photoChanged) {
                const resPhoto = await fetch(`${API_URL}/api/update-profile-pic`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
                    body: JSON.stringify({ profilePic: tempSelectedPic })
                });
                const dataPhoto = await resPhoto.json();
                if (!dataPhoto.success) throw new Error(dataPhoto.message);
            }

            // 2. Nombre (Requiere pass)
            if (nameChanged) {
                const newName = inputNewUser.value.trim();
                const pass = inputConfirmPass.value;
                if (newName.length < 4) throw new Error("Nombre muy corto.");
                if (!pass) throw new Error("Se requiere contraseña para cambiar nombre.");

                const resName = await fetch(`${API_URL}/api/update-username`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
                    body: JSON.stringify({ newUsername: newName, password: pass })
                });
                const dataName = await resName.json();
                if (!dataName.success) throw new Error(dataName.message);
                user.username = newName;
            }

            // Actualizar Todo
            user.profile_pic = tempSelectedPic;
            localStorage.setItem('vanacue_user', JSON.stringify(user));

            // Refrescar UI
            const pUrl = `Multimedia/Profiles/${tempSelectedPic}`;
            const ddImg = document.getElementById('dropdown-profile-img');
            if (ddImg) ddImg.src = pUrl;

            const configName = document.getElementById('config-user-name');
            if (configName) configName.innerText = user.username;

            const modalImg = document.getElementById('modal-profile-img');
            if (modalImg) modalImg.src = pUrl;

            modalEdit.classList.add('hidden');
            if (typeof mostrarToast === 'function') mostrarToast("¡Perfil actualizado!");

        } catch (err) {
            editFeedback.innerText = err.message;
            editFeedback.style.color = "#ff4444";
        }
    };
}


// =========================================
// === BOTÓN SCROLL TOP (VOLVER ARRIBA) ===
// =========================================

const btnScrollTop = document.getElementById('btn-scroll-top');

if (btnScrollTop) {
    window.addEventListener('scroll', () => {
        // A más de 300px, mostramos el botón
        if (window.scrollY > 300) {
            btnScrollTop.classList.add('visible');
        } else {
            btnScrollTop.classList.remove('visible');
        }
    });

    btnScrollTop.addEventListener('click', () => {
        window.scrollTo({
            top: 0,
            behavior: 'smooth'
        });
    });
}

// Función para manejar la expulsión
function handleSessionError(data) {
    if (!data) return false;

    // Detectar código específico O mensajes de texto que indiquen token inválido/expirado
    const esErrorSesion =
        data.code === 'SESSION_EXPIRED' ||
        (data.message && /token.*(invalid|expir|inválid)/i.test(data.message));

    if (esErrorSesion) {
        console.warn("Sesión expirada detectada:", data.message || data.code);
        alert("Tu sesión ha expirado. Por favor, inicia sesión nuevamente.");
        localStorage.removeItem('vanacue_token');
        localStorage.removeItem('vanacue_user');
        window.location.href = 'login.html';
        return true; // Hubo error y fue manejado
    }
    return false; // No hubo error de sesión
}
// ==========================================
// === LÓGICA del POST-PLAY ===
// ==========================================

/**
 * Selecciona una recomendación basada en el contexto actual.
 * @param {string} tituloActual - Título de la obra actual (para excluirla).
 * @param {Object} contexto - Datos extras (si es serie, etc).
 */
function seleccionarRecomendacion(tituloActual, contexto = null) {
    // Clonar data para no afectar original
    let pool = [...globalData];

    // Excluir la actual
    // Nota: El 'tituloActual' puede venir con "T1:E1 - Titulo", hay que ser laxos o usar IDs
    // Intentamos filtrar por coincidencia de título principal si tenemos contexto
    if (contexto && contexto.serie) {
        pool = pool.filter(p => p.titulo !== contexto.serie.titulo);
    } else {
        // Si es película, el tituloActual es el titulo de la película
        pool = pool.filter(p => !tituloActual.includes(p.titulo));
    }

    if (pool.length === 0) return null; // No hay nada más que ver :(

    // Simple Random Shuffle
    // (Podríamos mejorar para buscar mismo género?)
    const randomIndex = Math.floor(Math.random() * pool.length);
    return pool[randomIndex];
}

/**
 * Muestra el overlay de Post-Play y achica el video.
 */
function mostrarPostPlay(tituloActual, contexto, onCancel = null) {
    const overlay = document.getElementById('post-play-overlay');
    const videoElement = document.getElementById('dynamic-player');

    if (!overlay || !videoElement) return;

    // Elección de contenido
    const recomendacion = seleccionarRecomendacion(tituloActual, contexto);
    if (!recomendacion) {
        console.warn("No se encontró recomendación para post-play");
        return;
    }

    console.log("Mostrando Post-Play con:", recomendacion.titulo);

    // Poblar UI
    const backdropElem = document.getElementById('pp-backdrop');
    if (backdropElem) backdropElem.src = recomendacion.backdrop || recomendacion.portada;

    document.getElementById('pp-titulo').innerText = recomendacion.titulo;
    document.getElementById('pp-sinopsis').innerText = recomendacion.sinopsis;

    const btnPlay = document.getElementById('pp-btn-play');

    // Clonamos para limpiar eventos viejos
    const newBtnPlay = btnPlay.cloneNode(true);
    btnPlay.parentNode.replaceChild(newBtnPlay, btnPlay);

    newBtnPlay.addEventListener('click', () => {
        ocultarPostPlay();
        abrirModal(recomendacion); // esto mata el player actual e inicia uno nuevo
    });

    const btnCancel = document.getElementById('pp-btn-cancel');
    const newBtnCancel = btnCancel.cloneNode(true);
    btnCancel.parentNode.replaceChild(newBtnCancel, btnCancel);

    newBtnCancel.addEventListener('click', (e) => {
        e.stopPropagation();
        // Restaurar video original (para ver créditos)
        ocultarPostPlay();
        if (onCancel) onCancel();
    });

    // ACTIVAR EFECTOS "SHRINK"

    // Clase para el WRAPPER DEL VIDEO (no el contenedor principal)
    // Buscamos el wrapper generado por Plyr
    const plyrContainer = videoElement.closest('.plyr');
    if (plyrContainer) {
        const videoWrapper = plyrContainer.querySelector('.plyr__video-wrapper');
        if (videoWrapper) {
            videoWrapper.classList.add('player-minimized');
        } else {
            // Intentamos ponerlo al videoElement directo si no hay wrapper (rara vez pasa en plyr)
            videoElement.classList.add('player-minimized');
        }

        // Movemos el overlay dentro del contenedor de Plyr para que se vea en fullscreen
        // (Si ya está dentro, appendChild lo mueve al final, lo cual está bien para z-index)
        if (!plyrContainer.contains(overlay)) {
            plyrContainer.appendChild(overlay);
        }

        // Agregar clase para ocultar controles (via CSS)
        plyrContainer.classList.add('post-play-active');
    }

    // Mostrar overlay (Delay para que la transición del video empiece antes de que aparezca fondo negro)
    overlay.classList.remove('hidden');
    void overlay.offsetWidth;
    overlay.classList.add('active');

    // Ocultamos los controles de Plyr y custom overlay
    if (player) {
        player.toggleControls(false);
    }
    const customOverlay = document.querySelector('.custom-video-overlay');
    if (customOverlay) customOverlay.style.display = 'none';
}

/**
 * Restaura el player a estado normal y oculta recomendaciones.
 */
function ocultarPostPlay() {
    const overlay = document.getElementById('post-play-overlay');
    const videoElement = document.getElementById('dynamic-player');

    if (overlay) {
        overlay.classList.remove('active');
        // Esperar transición para hidden
        setTimeout(() => overlay.classList.add('hidden'), 500);

        // RESCATE DEL OVERLAY: Lo movemos de vuelta al body para que no se borre si el player se destruye
        if (overlay.parentNode !== document.body) {
            document.body.appendChild(overlay);
        }
    }

    if (videoElement) {
        const plyrContainer = videoElement.closest('.plyr');
        if (plyrContainer) {
            const videoWrapper = plyrContainer.querySelector('.plyr__video-wrapper');
            if (videoWrapper) videoWrapper.classList.remove('player-minimized');
            videoElement.classList.remove('player-minimized');

            // Quitar clase que oculta controles
            plyrContainer.classList.remove('post-play-active');
        }
    }

    // Restaurar overlay custom
    const customOverlay = document.querySelector('.custom-video-overlay');
    if (customOverlay) customOverlay.style.display = 'flex';
}

// ==========================================
// ======== LÓGICA DEL NUEVO MENUBAR ========
// ==========================================

// Función auxiliar para normalizar texto (quitar acentos y a minúsculas)
const normalizeString = (str) => {
    if (!str) return "";
    return str.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
};

function setupMenubarInteractions() {
    console.log("INIT: Configurando interacciones del Menú Cloud...");

    // 1. BUSCADOR EXPANDIBLE
    const searchBox = document.querySelector('.search-box');
    const searchBtn = document.querySelector('.search-btn');
    const searchInput = document.getElementById('menu-search-input');
    const buscadorOverlay = document.getElementById('buscador-overlay');
    const resultadosContainer = document.getElementById('resultados-busqueda');

    if (searchBtn && searchInput) {
        searchBtn.addEventListener('click', (e) => {
            e.preventDefault();
            searchBox.classList.toggle('active');

            if (searchBox.classList.contains('active')) {
                searchInput.focus();
            } else {
                searchInput.value = '';
                searchInput.blur();
                // Si cerramos manual, restauramos home por defecto
                window.renderView('home');
            }
        });

        // Debounce var
        let searchTimeout;

        // Búsqueda en tiempo real (REEMPLAZANDO CONTENIDO)
        searchInput.addEventListener('input', (e) => {
            clearTimeout(searchTimeout);

            searchTimeout = setTimeout(() => {
                const query = e.target.value.trim();

                // Ocultar siempre el overlay viejo por si acaso
                if (buscadorOverlay && !buscadorOverlay.classList.contains('hidden')) {
                    buscadorOverlay.classList.add('hidden');
                }

                if (query.length === 0) {
                    // Si borra todo, volver a HOME (o estado inicial)
                    window.renderView('home');
                    return;
                }

                // A partir de 1 caracter, mostramos resultados
                const normalizedQuery = normalizeString(query);

                const resultados = globalData.filter(item => {
                    const titulo = normalizeString(item.titulo || "");
                    const tituloOrg = normalizeString(item.titulo_original || "");
                    const generos = (item.genero || []).map(g => normalizeString(g));

                    return titulo.includes(normalizedQuery) ||
                        tituloOrg.includes(normalizedQuery) ||
                        generos.some(g => g.includes(normalizedQuery));
                });

                // RENDERIZAR EN MAIN (Limpiando todo lo demás)
                renderizarResultadosPage(resultados, query);
            }, 250); // 250ms de pausa para optimizar sin perder fluidez
        });

        // Cerrar con Escape
        searchInput.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                searchBox.classList.remove('active');
                searchInput.blur();
                searchInput.value = '';
                window.renderView('home');
            }
        });
    }
}

// 2. NOTIFICACIONES
const btnNotif = document.getElementById('btn-notifications');
const notifDropdown = document.getElementById('notification-dropdown');

if (btnNotif && notifDropdown) {
    // Cargar Notificaciones Reales
    loadNotifications(notifDropdown);

    btnNotif.addEventListener('click', (e) => {
        e.stopPropagation();

        // ANIMACIÓN SWING
        btnNotif.classList.remove('swing'); // Reset
        void btnNotif.offsetWidth; // Force reflow
        btnNotif.classList.add('swing');

        // CLEAR BADGE
        localStorage.setItem('seenNotifs', lastKnownTotalNotifs);
        const desktopBadge = document.getElementById('desktop-notif-badge');
        const mobileBadge = document.getElementById('mobile-notif-badge');
        if (desktopBadge) desktopBadge.classList.add('hidden');
        if (mobileBadge) mobileBadge.classList.add('hidden');

        // TOGGLE DROPDOWN
        const isHidden = notifDropdown.classList.contains('hidden');
        if (isHidden) {
            notifDropdown.classList.remove('hidden');
            loadNotifications(notifDropdown); // Recargar al abrir
        } else {
            notifDropdown.classList.add('hidden');
        }

        // Cerrar otros
        const configModal = document.getElementById('config-modal');
        if (configModal) configModal.classList.add('hidden');
        const btnConfig = document.getElementById('btn-config');
        if (btnConfig) btnConfig.classList.remove('rotated');
    });
}

// LÓGICA DE CREACIÓN DE NOTIFICACIÓN (ADMIN)
const btnSendNotif = document.getElementById('btn-send-notif');
const btnCancelNotif = document.getElementById('btn-cancel-notif');
const modalNotif = document.getElementById('modal-new-notification');

if (btnSendNotif && modalNotif) {
    btnSendNotif.addEventListener('click', async () => {
        const title = document.getElementById('notif-title').value;
        const message = document.getElementById('notif-message').value;
        const type = document.getElementById('notif-type').value;
        const targetType = document.getElementById('notif-target-type').value;
        const excludeUser = document.getElementById('notif-exclude-user').value;

        let targetValue = null;
        if (targetType === 'role') {
            targetValue = document.getElementById('notif-target-role').value;
        } else if (targetType === 'user') {
            targetValue = document.getElementById('notif-target-user').value;
        }

        if (!title || !message) {
            alert("Por favor completa el título y mensaje.");
            return;
        }

        try {
            const token = localStorage.getItem('vanacue_token');
            const response = await fetch(`${API_URL}/api/notifications`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({ 
                    title, 
                    message, 
                    type, 
                    targetType, 
                    targetValue, 
                    excludeUser 
                })
            });

            const data = await response.json();

            if (data.success) {
                alert("Notificación enviada.");
                modalNotif.classList.add('hidden');
                // Limpiar
                document.getElementById('notif-title').value = '';
                document.getElementById('notif-message').value = '';
                document.getElementById('notif-exclude-user').value = '';
                document.getElementById('notif-target-user').value = '';

                // RECARGAR SIEMPRE para actualizar badge y lista
                if (window.notifDropdown) loadNotifications(window.notifDropdown);
            } else {
                alert("Error: " + data.message);
            }
        } catch (e) {
            console.error(e);
            alert("Error de conexión.");
        }
    });

    if (btnCancelNotif) {
        btnCancelNotif.addEventListener('click', () => {
            modalNotif.classList.add('hidden');
            // Limpiar campos
            document.getElementById('notif-title').value = '';
            document.getElementById('notif-message').value = '';
            document.getElementById('notif-exclude-user').value = '';
            document.getElementById('notif-target-user').value = '';
            const targetTypeSelect = document.getElementById('notif-target-type');
            if (targetTypeSelect) targetTypeSelect.value = 'all';
            const targetValueContainer = document.getElementById('notif-target-value-container');
            if (targetValueContainer) targetValueContainer.classList.add('hidden');
        });
    }

    // Listener para cambiar campos según público objetivo
    const targetTypeSelect = document.getElementById('notif-target-type');
    const targetValueContainer = document.getElementById('notif-target-value-container');
    const targetRoleWrapper = document.getElementById('notif-target-role-wrapper');
    const targetUserInput = document.getElementById('notif-target-user');

    if (targetTypeSelect) {
        targetTypeSelect.addEventListener('change', (e) => {
            if (e.target.value === 'all') {
                targetValueContainer.classList.add('hidden');
            } else {
                targetValueContainer.classList.remove('hidden');
                if (e.target.value === 'role') {
                    targetRoleWrapper.classList.remove('hidden');
                    targetUserInput.classList.add('hidden');
                } else {
                    targetRoleWrapper.classList.add('hidden');
                    targetUserInput.classList.remove('hidden');
                }
            }
        });
    }
}


// 3. CONFIGURACIÓN / PERFIL
const btnConfig = document.getElementById('btn-config');
const configModal = document.getElementById('config-modal');
const configUserName = document.getElementById('config-user-name');
const configSubscription = document.getElementById('subscription-badge');
const btnEditUserConfig = document.getElementById('btn-edit-user-config');

if (btnConfig && configModal) {
    btnConfig.addEventListener('click', (e) => {
        e.stopPropagation();

        const isHidden = configModal.classList.contains('hidden');
        const icon = btnConfig.querySelector('.nav-icon');
        if (isHidden) {
            configModal.classList.remove('hidden');
            if (icon) icon.classList.add('rotated');
        } else {
            configModal.classList.add('hidden');
            if (icon) icon.classList.remove('rotated');
        }

        // Cerrar otros
        if (notifDropdown) notifDropdown.classList.add('hidden');

        // Cargar datos frescos
        const userStr = localStorage.getItem('vanacue_user');
        if (userStr) {
            const user = JSON.parse(userStr);
            if (configUserName) configUserName.textContent = user.username;

            // Lógica simple de badge (mock o basado en user role si existiera)
            if (configSubscription) {
                if (user.role === 'admin') {
                    configSubscription.textContent = "ADMIN";
                    configSubscription.className = "badge-admin";
                } else if (user.role === 'premium') {
                    configSubscription.textContent = "Premium";
                    configSubscription.className = "badge-premium";
                } else {
                    configSubscription.textContent = "Free";
                    configSubscription.className = "badge-free";
                }
            }
        }
    });

    // Botón Logout del modal nuevo
    const btnLogoutFull = document.getElementById('btn-logout-config');
    if (btnLogoutFull) {
        btnLogoutFull.addEventListener('click', () => {
            localStorage.removeItem('vanacue_token');
            localStorage.removeItem('vanacue_user');
            window.location.href = 'login.html';
        });
    }

    // --- POLLING DE NOTIFICACIONES (60s) ---
    // Refrezcar badge y lista automáticamente
    // Solo si el usuario está logueado (token existe)
    if (localStorage.getItem('vanacue_token')) {
        setInterval(() => {
            const notifDropdown = document.getElementById('notification-dropdown');
            if (notifDropdown) loadNotifications(notifDropdown);
        }, 60000);
    }

    // Botón Editar Usuario (reutilizar modal existente)
    if (btnEditUserConfig) {
        btnEditUserConfig.onclick = openEditProfileModal;
    }
}

// 4. MENU RESPONSIVE (MOBILE)
const btnMobileMenu = document.getElementById('btn-mobile-menu');
const responsiveDropdown = document.getElementById('responsive-dropdown');
const btnMobileNotif = document.getElementById('btn-mobile-notif');
const btnMobileConfig = document.getElementById('btn-mobile-config');

if (btnMobileMenu && responsiveDropdown) {
    // Inicializar contenido del menú lateral
    renderMobileMenuContent(responsiveDropdown);

    btnMobileMenu.addEventListener('click', (e) => {
        e.stopPropagation();

        // Lógica de ICONO (Swap con animación)
        if (responsiveDropdown.classList.contains('hidden')) {
            // ABRIR
            // CLEAR BADGE
            localStorage.setItem('seenNotifs', lastKnownTotalNotifs);
            const desktopBadge = document.getElementById('desktop-notif-badge');
            const mobileBadge = document.getElementById('mobile-notif-badge');
            if (desktopBadge) desktopBadge.classList.add('hidden');
            if (mobileBadge) mobileBadge.classList.add('hidden');

            btnMobileMenu.style.opacity = '0';
            btnMobileMenu.style.transform = 'scale(0.8)';
            setTimeout(() => {
                btnMobileMenu.src = 'Multimedia/menu_apertura.svg';
                btnMobileMenu.style.opacity = '1';
                btnMobileMenu.style.transform = 'scale(1)';
            }, 200);
            responsiveDropdown.classList.remove('hidden');
        } else {
            // CERRAR
            btnMobileMenu.style.opacity = '0';
            btnMobileMenu.style.transform = 'scale(0.8)';
            setTimeout(() => {
                btnMobileMenu.src = 'Multimedia/menu.svg';
                btnMobileMenu.style.opacity = '1';
                btnMobileMenu.style.transform = 'scale(1)';
            }, 200);
            responsiveDropdown.classList.add('hidden');
        }

        // Cerrar otros overlays si estuvieran abiertos
        if (notifDropdown) notifDropdown.classList.add('hidden');
        if (configModal) configModal.classList.add('hidden');
    });

    // Click en Notificaciones (Mobile)
    if (btnMobileNotif) {
        btnMobileNotif.addEventListener('click', (e) => {
            e.stopPropagation();
            responsiveDropdown.classList.add('hidden'); // Cerrar menú

            // Revertir icono
            btnMobileMenu.style.opacity = '0';
            btnMobileMenu.style.transform = 'scale(0.8)';
            setTimeout(() => {
                btnMobileMenu.src = 'Multimedia/menu.svg';
                btnMobileMenu.style.opacity = '1';
                btnMobileMenu.style.transform = 'scale(1)';
            }, 200);

            // Abrir lógica de notificaciones
            if (notifDropdown) {
                notifDropdown.classList.remove('hidden');
                // Posicionamiento especial si fuera necesario, o dejar CSS
            }
        });
    }

    // Click en Configuración (Mobile)
    if (btnMobileConfig) {
        btnMobileConfig.addEventListener('click', (e) => {
            e.stopPropagation();
            responsiveDropdown.classList.add('hidden'); // Cerrar menú

            // Revertir icono
            btnMobileMenu.style.opacity = '0';
            btnMobileMenu.style.transform = 'scale(0.8)';
            setTimeout(() => {
                btnMobileMenu.src = 'Multimedia/menu.svg';
                btnMobileMenu.style.opacity = '1';
                btnMobileMenu.style.transform = 'scale(1)';
            }, 200);

            // Abrir modal config
            if (configModal) {
                configModal.classList.remove('hidden');
                // Gatillar lógica de carga de usuario
                btnConfig.click(); // Reutilizar handler de desktop para cargar datos
            }
        });
    }
}


// CERRAR AL HACER CLICK FUERA
document.addEventListener('click', (e) => {
    if (responsiveDropdown && !responsiveDropdown.classList.contains('hidden')) {
        if (!responsiveDropdown.contains(e.target) && e.target !== btnMobileMenu) {
            responsiveDropdown.classList.add('hidden');
            // Revertir icono (si estaba abierto)
            // Chequeamos si el src es apertura para no animar innecesariamente? 
            // Mejor animar siempre para consistencia visual si se cierra
            btnMobileMenu.style.opacity = '0';
            btnMobileMenu.style.transform = 'scale(0.8)';
            setTimeout(() => {
                btnMobileMenu.src = 'Multimedia/menu.svg';
                btnMobileMenu.style.opacity = '1';
                btnMobileMenu.style.transform = 'scale(1)';
            }, 200);
        }
    }

    if (notifDropdown && !notifDropdown.classList.contains('hidden')) {
        if (!notifDropdown.contains(e.target) && e.target !== btnNotif) {
            notifDropdown.classList.add('hidden');
        }
    }
    if (configModal && !configModal.classList.contains('hidden')) {
        if (!configModal.contains(e.target) && e.target !== btnConfig) {
            configModal.classList.add('hidden');
            if (btnConfig) {
                const icon = btnConfig.querySelector('.nav-icon');
                if (icon) icon.classList.remove('rotated');
            }
        }
    }

    // Cerrar buscador si click fuera
    if (searchBox && searchBox.classList.contains('active')) {
        if (!searchBox.contains(e.target)) {
            if (searchInput.value === '') {
                searchBox.classList.remove('active');
            }
        }
    }
});

function renderizarResultadosPage(resultados, query) {
    // Resetear scroll al inicio para que los resultados se vean desde arriba
    window.scrollTo({ top: 0, behavior: 'instant' });



    const main = document.querySelector("main");
    const menubar = document.querySelector(".menubar");
    const hero = document.querySelector(".hero");

    // Preparar UI
    if (menubar) menubar.classList.add("scrolled");
    if (hero) hero.style.display = "none";

    // Limpiar Main
    main.innerHTML = `
        <section class="genero-main" style="padding-top: 100px; min-height: 80vh;">
          <h1 id="titulo-genero">Resultados para: "${query}"</h1>
          <p class="contador-titulo">(${resultados.length})</p>
          <div id="grid-resultados" class="grid-genero"></div>
        </section>
    `;

    const grid = main.querySelector("#grid-resultados");

    if (resultados.length === 0) {
        grid.innerHTML = `
           <div style="width: 100%; text-align: center; margin-top: 50px; color: #777;">
              <p style="font-size: 1.2rem;">No se encontraron títulos relacionados con "${query}".</p>
              <p style="font-size: 0.9rem;">Prueba con otro término (título, género, etc).</p>
           </div>
        `;
        return;
    }

    resultados.forEach(item => {
        const card = createCardElement(item);
        grid.appendChild(card);
    });
}

async function deleteNotification(id) {
    const token = localStorage.getItem('vanacue_token');
    try {
        const response = await fetch(`${API_URL}/api/notifications/${id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();
        if (data.success) {
            // alert("Notificación eliminada"); // Opcional, feedback visual is enough usually
        } else {
            alert("Error al eliminar: " + data.message);
        }
    } catch (e) {
        console.error(e);
        alert("Error de conexión al eliminar.");
    }
}


let lastKnownTotalNotifs = 0;

async function loadNotifications(container) {
    const token = localStorage.getItem('vanacue_token');
    const userStr = localStorage.getItem('vanacue_user');
    const user = userStr ? JSON.parse(userStr) : {};
    const isAdmin = user.role === 'admin';

    try {
        const response = await fetch(`${API_URL}/api/notifications`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();

        // --- BADGE LOGIC ---
        if (data.success && data.notifications) {
            lastKnownTotalNotifs = data.notifications.length;
            let seen = parseInt(localStorage.getItem('seenNotifs') || '0');

            // Si hay MENOS notificaciones de las que el usuario "vio" (ej: se borraron),
            // reseteamos 'seen' para que no quede negativo el unseen.

            if (lastKnownTotalNotifs < seen) {
                seen = lastKnownTotalNotifs;
                localStorage.setItem('seenNotifs', seen);
            }

            const unseen = lastKnownTotalNotifs - seen;

            const desktopBadge = document.querySelector('.desktop-icon-wrapper #desktop-notif-badge');
            const mobileBadge = document.getElementById('mobile-notif-badge');

            const updateBadge = (badge) => {
                if (!badge) return;
                if (unseen > 0) {
                    badge.textContent = unseen > 9 ? '9+' : unseen;
                    badge.classList.remove('hidden');
                } else {
                    badge.classList.add('hidden');
                }
            };

            updateBadge(desktopBadge);
            updateBadge(mobileBadge);
        }
        // -------------------

        container.innerHTML = '';

        // HEADER
        const header = document.createElement('div');
        header.className = 'notif-header';

        // AJUSTE MOBILE: Título más arriba
        if (container.id === 'mobile-notif-internal') {
            header.style.paddingTop = '0px';
            header.style.marginTop = '-5px'; // Subirlo un poco más visualmente
        }

        // Icono campanita (blanco) - FEEDBACK: Ensure white
        let headerHTML = `
            <img src="Multimedia/notification.svg" style="width:16px; height:16px; filter: brightness(0) invert(1);">
            Notificaciones
        `;

        // Si es admin, mostrar botón +
        if (isAdmin) {
            headerHTML += `
                <button id="btn-open-new-notif" style="margin-left: auto; background: none; border: none; cursor: pointer; padding: 0;">
                    <img src="Multimedia/plus.svg" style="width: 20px; height: 20px; filter: brightness(0) invert(1);">
                </button>
            `;
        }

        header.innerHTML = headerHTML;
        container.appendChild(header);

        // EVENTO ABRIR MODAL (Si existe botón)
        if (isAdmin) {
            const btnOpen = header.querySelector('#btn-open-new-notif');
            if (btnOpen) {
                btnOpen.addEventListener('click', (e) => {
                    e.stopPropagation(); // Evitar cerrar dropdown
                    const modal = document.getElementById('modal-new-notification');
                    if (modal) {
                        modal.classList.remove('hidden');
                        // Cerrar dropdown/menu para que no estorbe
                        if (container.id === 'notification-dropdown') {
                            container.classList.add('hidden');
                        }
                    }
                });
            }
        }

        const listContainer = document.createElement('div');
        listContainer.className = 'notif-list';
        listContainer.style.maxHeight = '300px';
        // Note: CSS handles max-height too, but keeping inline or relying on CSS class is fine.
        // We removed inline max-height in favor of CSS class in previous step, but let's leave it compatible.
        // Actually adhering to styles.css rule is better.
        listContainer.removeAttribute('style'); // Use CSS class

        container.appendChild(listContainer);

        if (data.success && data.notifications.length > 0) {
            data.notifications.forEach(notif => {
                const item = document.createElement('div');
                item.className = 'notif-item';

                // Determinar icono y clase según tipo
                let iconSrc = 'Multimedia/info.svg'; // Default
                let typeClass = 'notif-type-info';

                if (notif.type === 'alert') {
                    iconSrc = 'Multimedia/alert.svg';
                    typeClass = 'notif-type-alert';
                }

                item.classList.add(typeClass);

                // Formatear fecha
                // Aseguramos formato ISO 8601 válido (YYYY-MM-DDTHH:mm:ssZ) para compatibilidad total
                let cleanDate = notif.created_at.replace(' ', 'T');
                if (!cleanDate.endsWith('Z')) cleanDate += 'Z';

                const rawDate = cleanDate;

                const fecha = new Date(rawDate).toLocaleString('es-MX', {
                    timeZone: 'America/Mexico_City',
                    day: '2-digit', month: '2-digit', year: 'numeric',
                    hour: 'numeric', minute: '2-digit', hour12: true
                }).replace(',', ''); // Quitar coma si sobra

                // Generamos HTML con la nueva estructura Flexbox (icono izquierda, contenido derecha)
                item.innerHTML = `
                    <div class="notif-left">
                        <div class="notif-icon-circle">
                            <img src="${iconSrc}" alt="${notif.type}">
                        </div>
                    </div>
                    <div class="notif-content">
                        <div class="notif-title">${notif.title}</div>
                        <div class="notif-message">${notif.message}</div>
                        <div class="notif-date">
                            <img src="Multimedia/clock.svg" style="width:12px; height:12px; opacity:0.6; filter:invert(1);">
                            ${fecha}
                        </div>
                    </div>
                    ${isAdmin ? `
                    <button class="btn-delete-notif" data-id="${notif.id}" style="background:none; border:none; cursor:pointer; margin-left:5px; padding:0;">
                        <img src="Multimedia/cancel.svg" style="width: 16px; height: 16px; filter: brightness(0) invert(1) sepia(1) saturate(5) hue-rotate(-50deg);">
                    </button>` : ''}
                `;

                // Evento borrar (Admin)
                if (isAdmin) {
                    const btnDel = item.querySelector('.btn-delete-notif');
                    if (btnDel) {
                        btnDel.addEventListener('click', async (e) => {
                            e.stopPropagation();
                            if (confirm("¿Borrar notificación?")) {
                                await deleteNotification(notif.id);
                                loadNotifications(container); // Recargar
                            }
                        });
                    }
                }

                listContainer.appendChild(item);
            });
        } else {
            listContainer.innerHTML = '<div style="padding:20px; text-align:center; color:#888;">No hay notificaciones nuevas.</div>';
        }
    } catch (e) {
        console.error(e);
        container.innerHTML = '<div style="padding:15px; text-align:center; color:#f00;">Error al cargar notificaciones.</div>';
    }
}

function obtenerTiempoRelativo(fechaStr) {
    // Formato esperado DD/MM/YYYY HH:mm pero mockeado simple
    // Retornamos el string tal cual o calculamos. Para el mock, retornamos string
    return fechaStr;
}

// === INICIALIZACIÓN ===
document.addEventListener('DOMContentLoaded', () => {
    setupMenubarInteractions();
});

function renderMobileMenuContent(container) {
    container.innerHTML = '';

    // 1. OBTENER USUARIO
    const userStr = localStorage.getItem('vanacue_user');
    const user = userStr ? JSON.parse(userStr) : { username: 'Invitado', role: 'free' };

    // --- HEADER (Menú + Cerrar) ---
    const headerSection = document.createElement('div');
    headerSection.style.padding = '10px 20px 5px 20px'; /* Menos espacio abajo */
    headerSection.style.borderBottom = '1px solid #333';
    headerSection.style.display = 'flex';
    headerSection.style.justifyContent = 'space-between';
    headerSection.style.alignItems = 'center';
    headerSection.style.marginBottom = '0'; /* Sin margen extra */

    headerSection.innerHTML = `
        <span style="font-size: 1.2rem; font-weight: bold; color: #e50914;">Menú</span> <!-- Tamaño balanceado -->
        <span id="close-mobile-menu" style="font-size: 1.5rem; cursor: pointer; color: #fff; line-height: 1;">&times;</span>
    `;
    container.appendChild(headerSection);

    // Evento Cerrar
    setTimeout(() => {
        const closeBtn = container.querySelector('#close-mobile-menu');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                const dropdown = document.getElementById('responsive-dropdown');
                if (dropdown) dropdown.classList.add('hidden');

                // Revertir icono
                const btnMobileMenu = document.getElementById('btn-mobile-menu');
                if (btnMobileMenu) {
                    btnMobileMenu.style.opacity = '0';
                    btnMobileMenu.style.transform = 'scale(0.8)';
                    setTimeout(() => {
                        btnMobileMenu.src = 'Multimedia/menu.svg';
                        btnMobileMenu.style.opacity = '1';
                        btnMobileMenu.style.transform = 'scale(1)';
                    }, 200);
                }
            });
        }
    }, 0);

    // --- SECCIÓN PERFIL ---
    const profileSection = document.createElement('div');
    profileSection.style.padding = '15px 20px';
    // profileSection.style.borderBottom = '1px solid #333'; // Separator is below badge
    profileSection.style.display = 'flex';
    profileSection.style.alignItems = 'flex-start'; // Align top
    profileSection.style.justifyContent = 'space-between';

    let roleBadge = `<span class="badge-free">FREE</span>`;
    if (user.role === 'admin') {
        roleBadge = `<span class="badge-admin">ADMIN</span>`;
    } else if (user.role === 'premium') {
        roleBadge = `<span class="badge-premium">PREMIUM</span>`;
    }

    profileSection.innerHTML = `
        <div style="display:flex; flex-direction:column; gap: 4px; align-items: flex-start; text-align: left;">
            <span style="color:#fff; font-weight:bold; font-size:1.2rem;">${user.username}</span> <!-- Coincidiendo con titulo -->
            <div>${roleBadge}</div>
        </div>
        <img src="Multimedia/edit.svg" class="edit-icon" style="cursor:pointer; filter: brightness(0) invert(1); width:18px; height:18px;" id="mobile-edit-user">
    `;
    container.appendChild(profileSection);

    // Separator line
    const separator1 = document.createElement('div');
    separator1.style.borderBottom = '1px solid #333';
    separator1.style.margin = '15px 20px';
    container.appendChild(separator1);

    // Evento Editar (Mobile)
    setTimeout(() => {
        const mobileEditBtn = container.querySelector('#mobile-edit-user');
        if (mobileEditBtn) {
            mobileEditBtn.addEventListener('click', () => {
                document.getElementById('responsive-dropdown').classList.add('hidden');

                // Revertir icono
                const btnMobileMenu = document.getElementById('btn-mobile-menu');
                if (btnMobileMenu) {
                    btnMobileMenu.style.opacity = '0';
                    btnMobileMenu.style.transform = 'scale(0.8)';
                    setTimeout(() => {
                        btnMobileMenu.src = 'Multimedia/menu.svg';
                        btnMobileMenu.style.opacity = '1';
                        btnMobileMenu.style.transform = 'scale(1)';
                    }, 200);
                }

                if (typeof openEditProfileModal === 'function') {
                    openEditProfileModal();
                }
            });
        }
    }, 0);


    // --- SECCIÓN NOTIFICACIONES ---
    const notifSection = document.createElement('div');
    notifSection.style.padding = '0 20px'; // Less padding vertical

    // Contenedor especifico para que loadNotifications lo llene
    const notifListContainer = document.createElement('div');
    notifListContainer.id = 'mobile-notif-internal';
    notifSection.appendChild(notifListContainer);

    container.appendChild(notifSection);

    // Cargar dinámicamente
    // Usamos setTimeout para asegurar que el DOM esté listo o simplemente llamar directo
    loadNotifications(notifListContainer);

    // Separator line REMOVED as per request
    // const separator2 = document.createElement('div');
    // separator2.style.borderBottom = '1px solid #333';
    // separator2.style.margin = '15px 20px';
    // container.appendChild(separator2);

    // --- SECCIÓN LOGOUT ---
    const logoutSection = document.createElement('div');
    logoutSection.style.padding = '0 20px 20px 20px';
    logoutSection.style.marginTop = '30px'; // Separación extra de lo anterior

    const logoutBtn = document.createElement('button');
    logoutBtn.textContent = 'Cerrar Sesión';
    logoutBtn.style.width = '100%';
    logoutBtn.style.padding = '12px';
    logoutBtn.style.backgroundColor = '#e50914';
    logoutBtn.style.color = 'white';
    logoutBtn.style.border = 'none';
    logoutBtn.style.borderRadius = '4px';
    logoutBtn.style.cursor = 'pointer';
    logoutBtn.style.fontWeight = 'bold';
    logoutBtn.style.fontSize = '1rem';

    logoutBtn.addEventListener('click', () => {
        localStorage.removeItem('vanacue_token');
        localStorage.removeItem('vanacue_user');
        window.location.href = 'login.html';
    });

    logoutSection.appendChild(logoutBtn);
    container.appendChild(logoutSection);
}

// === SCANNER FEATURE ===
let scannerInterval = null;

window.mostrarScanner = function () {
    const main = document.querySelector("main");
    main.innerHTML = "";

    const userStr = localStorage.getItem('vanacue_user');
    const user = userStr ? JSON.parse(userStr) : null;

    if (!user || user.role !== 'admin') {
        main.innerHTML = "<h2 style='color:red; text-align:center; padding: 50px;'>Acceso denegado</h2>";
        return;
    }

    const scannerContainer = document.createElement('div');
    scannerContainer.className = 'seccion-scanner';
    scannerContainer.innerHTML = `
        <div class="scanner-header">
            <h2>Scanner</h2>
        </div>
        <div class="scanner-table-container">
            <table class="scanner-table">
                <thead>
                    <tr>
                        <th>Usuario</th>
                        <th>Estado</th>
                        <th>Viendo</th>
                        <th>Última vista</th>
                        <th>Última Conexión</th>
                    </tr>
                </thead>
                <tbody id="scanner-tbody">
                    <tr><td colspan="5" style="text-align:center;">Cargando datos...</td></tr>
                </tbody>
            </table>
        </div>
    `;
    main.appendChild(scannerContainer);

    fetchScannerData();

    if (scannerInterval) clearInterval(scannerInterval);
    scannerInterval = setInterval(() => {
        // Solo actualizar si seguimos en la vista de scanner
        if (window.location.search.includes('accion=scanner')) {
            fetchScannerData();
        } else {
            clearInterval(scannerInterval);
        }
    }, 10000);
};

async function fetchScannerData() {
    const token = localStorage.getItem('vanacue_token');
    if (!token) return;

    try {
        const response = await fetch(`${API_URL}/api/scanner`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();

        if (data.success) {
            renderScannerTable(data.scannerData);
        }
    } catch (e) {
        console.error("Error fetching scanner data:", e);
    }
}

function renderScannerTable(users) {
    const tbody = document.getElementById('scanner-tbody');
    if (!tbody) return;

    if (users.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;">No hay usuarios registrados</td></tr>';
        return;
    }

    tbody.innerHTML = '';
    users.forEach(u => {
        const tr = document.createElement('tr');

        const isOnline = u.isOnline;
        const statusClass = isOnline ? 'online' : 'offline';
        const roleClass = u.role === 'admin' ? 'admin' : (u.role === 'premium' ? 'premium' : 'free');

        let lastSeenText = 'Nunca';
        if (u.lastSeen) {
            const date = new Date(u.lastSeen);
            lastSeenText = date.toLocaleString();
        } else if (u.last_login) {
            const dateString = u.last_login.includes('T') ? u.last_login : u.last_login.replace(' ', 'T') + 'Z';
            const date = new Date(dateString);
            lastSeenText = date.toLocaleString();
        } else if (u.created_at) {
            const dateString = u.created_at.includes('T') ? u.created_at : u.created_at.replace(' ', 'T') + 'Z';
            const date = new Date(dateString);
            lastSeenText = 'Registro: ' + date.toLocaleDateString();
        }

        tr.innerHTML = `
            <td>
                ${u.username}
                <span class="scanner-badge ${roleClass}">${u.role}</span>
            </td>
            <td>
                <div class="scanner-status">
                    <span class="status-dot ${statusClass}"></span>
                    <span>${isOnline ? 'Conectado' : 'Desconectado'}</span>
                </div>
            </td>
            <td>${u.media || 'Ninguna'}</td>
            <td>${u.last_viewed || 'Ninguna'}</td>
            <td>${lastSeenText}</td>
        `;
        tbody.appendChild(tr);
    });
}
// =======================

// ==========================================
// LÓGICA DE ESCRITURA DE RESEÑAS (MODAL)
// ==========================================

let currentReviewMedia = null;
let currentRating = 0;

window.openWriteReviewModal = function (pelicula) {
    currentReviewMedia = pelicula;
    currentRating = 0; // Reset

    const modal = document.getElementById('modal-write-review');
    const title = document.getElementById('review-media-title');
    const meta = document.getElementById('review-media-meta');
    const img = document.getElementById('review-media-img');
    const textArea = document.getElementById('review-text-input');

    if (title) title.innerText = pelicula.titulo;
    if (meta) meta.innerText = `${pelicula.tipo} • ${pelicula.fecha.substring(0, 4)}`;
    if (img) img.src = pelicula.portada;
    if (textArea) textArea.value = "";

    // Reset stars
    document.querySelectorAll('#star-rating-input .star-wrapper').forEach(w => {
        w.classList.remove('active');
    });

    if (modal) {
        modal.classList.remove('hidden');
        document.body.style.overflow = 'hidden';
    }
};

// Inicializar listeners del modal de reseñas
document.addEventListener('DOMContentLoaded', () => {
    const modalReview = document.getElementById('modal-write-review');
    const btnClose = document.getElementById('btn-close-review');
    const btnCancel = document.getElementById('btn-cancel-review');
    const btnSubmit = document.getElementById('btn-submit-review');
    const starWrappers = document.querySelectorAll('#star-rating-input .star-wrapper');

    const closeModal = () => {
        if (modalReview) modalReview.classList.add('hidden');
        // Solo restaurar overflow si el modal de info no está abierto
        const modalInfo = document.getElementById('modal-info');
        if (modalInfo && modalInfo.classList.contains('hidden')) {
            document.body.style.overflow = 'auto';
        }
    };

    if (btnClose) btnClose.onclick = closeModal;
    if (btnCancel) btnCancel.onclick = closeModal;

    starWrappers.forEach(wrapper => {
        wrapper.onclick = () => {
            const val = parseInt(wrapper.dataset.value);
            currentRating = val;

            starWrappers.forEach(w => {
                const wVal = parseInt(w.dataset.value);
                if (wVal <= val) {
                    w.classList.add('active');
                } else {
                    w.classList.remove('active');
                }
            });
        };
    });

    if (btnSubmit) {
        btnSubmit.onclick = async () => {
            const text = document.getElementById('review-text-input').value.trim();

            if (currentRating === 0) {
                if (typeof mostrarToast === 'function') mostrarToast("Por favor, selecciona una puntuación.");
                return;
            }

            if (text.length < 10) {
                if (typeof mostrarToast === 'function') mostrarToast("La reseña es muy corta.");
                return;
            }

            try {
                const token = localStorage.getItem('vanacue_token');
                const response = await fetch(`${API_URL}/api/reviews`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`
                    },
                    body: JSON.stringify({
                        tmdb_id: currentReviewMedia.tmdbId || generateId(currentReviewMedia),
                        movie_title: currentReviewMedia.titulo,
                        movie_type: currentReviewMedia.tipo,
                        movie_year: currentReviewMedia.fecha.substring(0, 4),
                        rating: currentRating,
                        comment: text
                    })
                });

                const data = await response.json();

                if (data.success) {
                    if (typeof mostrarToast === 'function') {
                        mostrarToast("Reseña enviada para revisión.");
                    }
                    closeModal();
                } else {
                    if (typeof mostrarToast === 'function') mostrarToast("Error: " + data.message);
                }
            } catch (e) {
                console.error("Error al publicar reseña:", e);
                if (typeof mostrarToast === 'function') mostrarToast("Error de conexión.");
            }
        };

    }
});

// --- SISTEMA DE COMPARTIR RESEÑAS (9:16) ---

function truncateText(text, limit) {
    if (text.length <= limit) return text;
    return text.substring(0, limit) + "...";
}

window.openShareModal = function (review) {
    const modal = document.getElementById('modal-share-review');
    if (!modal) return;

    // Adaptar campos del backend al formato del ticket
    const dateStr = new Date(review.created_at).toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' });

    const formattedReview = {
        user: review.username,
        date: dateStr,
        text: review.comment,
        movie: review.movie_title,
        year: review.movie_year,
        stars: review.rating,
        id: review.id
    };

    // 1. Poblar datos en Diseño ESTÁNDAR
    document.getElementById('share-user-name').innerText = formattedReview.user;
    document.getElementById('share-date').innerText = formattedReview.date;
    document.getElementById('share-text').innerText = `"${truncateText(formattedReview.text, 180)}"`;
    document.getElementById('share-movie-title-full').innerText = `${formattedReview.movie} (${formattedReview.year})`;

    // Avatar del autor de la reseña
    const avatarImg = document.getElementById('share-avatar-img');
    if (avatarImg) {
        const picFile = review.profile_pic || 'alucard.jpg';
        avatarImg.src = `Multimedia/Profiles/${picFile}`;
        avatarImg.onerror = function () { this.src = 'Multimedia/logo.png'; };
    }

    // Estrellas
    const starsS = document.getElementById('share-stars');
    starsS.innerHTML = Array(5).fill(0).map((_, i) =>
        `<img src="Multimedia/star_r.svg" style="opacity: ${i >= formattedReview.stars ? '0.2' : '1'}; width: 22px; margin-right: 5px;">`
    ).join("");

    // 2. Poblar datos en Diseño TICKET
    document.getElementById('ticket-user-name').innerText = formattedReview.user.toUpperCase();
    document.getElementById('ticket-date').innerText = formattedReview.date;
    document.getElementById('ticket-text').innerText = `"${truncateText(formattedReview.text, 200)}"`;
    document.getElementById('ticket-movie-title-full').innerText = `${formattedReview.movie.toUpperCase()} (${formattedReview.year})`;
    document.getElementById('ticket-receipt-id').innerText = `RECEIPT ID: #VN-${formattedReview.year}-${1000 + formattedReview.id}`;

    const starsT = document.getElementById('ticket-stars');
    const isLightInitial = true;
    const starSrcInitial = isLightInitial ? 'Multimedia/star_black.svg' : 'Multimedia/star_white.svg';

    starsT.innerHTML = Array(5).fill(0).map((_, i) =>
        `<img src="${starSrcInitial}" style="opacity: ${i >= formattedReview.stars ? '0.2' : '1'}">`
    ).join("");

    // 3. Resetear ajustes UI
    const card = document.getElementById('share-card-container');
    const stdContent = document.getElementById('standard-share-content');
    const tktContent = document.getElementById('ticket-share-content');
    const grpStd = document.getElementById('grp-standard-opts');
    const grpColor = document.getElementById('grp-bg-color');

    // Estado inicial: Estándar
    card.className = 'share-card-916 has-gradient';
    stdContent.style.display = 'flex';
    tktContent.style.display = 'none';
    grpStd.style.display = 'block';
    grpColor.style.display = 'none';

    // Botones activos
    document.getElementById('btn-fmt-standard').classList.add('active');
    document.getElementById('btn-fmt-ticket').classList.remove('active');
    document.querySelectorAll('.color-circle').forEach(c => c.classList.remove('active'));
    document.querySelector('.color-circle.light').classList.add('active');

    // Chks
    document.getElementById('chk-include-link').checked = true;
    document.getElementById('share-footer-link').style.display = 'block';

    const tktFooter = document.getElementById('ticket-footer-promo');
    if (tktFooter) tktFooter.style.display = 'block';

    modal.style.display = 'block';
    document.documentElement.style.overflow = 'hidden';
    document.body.style.overflow = 'hidden';

    setTimeout(() => { modal.scrollTop = 0; }, 10);

    document.getElementById('btn-download-share').onclick = () => downloadShareImage(formattedReview);
};

function closeShareModal() {
    const modal = document.getElementById('modal-share-review');
    if (modal) modal.style.display = 'none';
    document.documentElement.style.overflow = '';
    document.body.style.overflow = '';
}

// Controladores de UI para el modal de compartir
document.addEventListener('DOMContentLoaded', () => {
    const modal = document.getElementById('modal-share-review');
    const card = document.getElementById('share-card-container');
    const stdContent = document.getElementById('standard-share-content');
    const tktContent = document.getElementById('ticket-share-content');
    const grpStd = document.getElementById('grp-standard-opts');
    const grpColor = document.getElementById('grp-bg-color');

    // Toggles de Formato
    document.getElementById('btn-fmt-standard').onclick = function () {
        this.classList.add('active');
        document.getElementById('btn-fmt-ticket').classList.remove('active');
        stdContent.style.display = 'flex';
        tktContent.style.display = 'none';
        grpStd.style.display = 'block';
        document.getElementById('grp-gradient-opt').style.display = 'block';
        grpColor.style.display = 'none';

        // Restore gradient if checked, remove light theme
        card.classList.remove('is-light-theme');
        card.classList.remove('is-ticket-mode');
        if (document.getElementById('chk-gradient').checked) {
            card.classList.add('has-gradient');
        }
    };

    document.getElementById('btn-fmt-ticket').onclick = function () {
        this.classList.add('active');
        document.getElementById('btn-fmt-standard').classList.remove('active');
        stdContent.style.display = 'none';
        tktContent.style.display = 'flex';
        grpStd.style.display = 'block';
        document.getElementById('grp-gradient-opt').style.display = 'none';
        grpColor.style.display = 'block';

        card.classList.add('is-ticket-mode');
        card.classList.remove('has-gradient');
        // Mantener el color elegido por el usuario en ticket (por defecto light)
        if (document.querySelector('.color-circle.light').classList.contains('active')) {
            card.classList.add('is-light-theme');
        }
    };

    // Toggles de Color
    document.querySelectorAll('.color-circle').forEach(circle => {
        circle.onclick = function () {
            document.querySelectorAll('.color-circle').forEach(c => c.classList.remove('active'));
            this.classList.add('active');

            const isLight = this.dataset.color === 'light';
            if (isLight) card.classList.add('is-light-theme');
            else card.classList.remove('is-light-theme');

            // ACTUALIZAR ESTRELLAS EN MODO TICKET para evitar filtros CSS en el export
            const ticketStars = document.getElementById('ticket-stars');
            if (ticketStars) {
                const starSrc = isLight ? 'Multimedia/star_black.svg' : 'Multimedia/star_white.svg';
                ticketStars.querySelectorAll('img').forEach(img => {
                    img.src = starSrc;
                });
            }
        };
    });

    // Chks Estándar
    document.getElementById('chk-include-link').onchange = (e) => {
        const isChecked = e.target.checked;
        document.getElementById('share-footer-link').style.display = isChecked ? 'block' : 'none';

        // También afectar al footer del ticket si existe
        const tktFooter = document.getElementById('ticket-footer-promo');
        if (tktFooter) tktFooter.style.display = isChecked ? 'block' : 'none';
    };

    document.getElementById('chk-gradient').onchange = (e) => {
        if (e.target.checked) card.classList.add('has-gradient');
        else card.classList.remove('has-gradient');
    }

    // Cerrar modal
    const closeBtns = ['btn-close-share', 'btn-close-share-desktop', 'btn-cancel-share'];
    closeBtns.forEach(id => {
        const btn = document.getElementById(id);
        if (btn) btn.onclick = closeShareModal;
    });

    window.addEventListener('click', (e) => {
        if (e.target === modal) closeShareModal();
    });
});

async function downloadShareImage(review) {
    const card = document.getElementById('share-card-container');
    const btnDown = document.getElementById('btn-download-share');

    if (!card) return;

    const originalBtnText = btnDown.innerHTML;
    btnDown.innerHTML = "Generando...";
    btnDown.disabled = true;

    try {
        // html2canvas captura el elemento y lo convierte a canvas
        const canvas = await html2canvas(card, {
            scale: 2, // DOBLE RESOLUCIÓN para que se vea premium
            backgroundColor: null,
            logging: false,
            useCORS: true
        });

        const image = canvas.toDataURL("image/png", 1.0);
        const link = document.createElement('a');
        link.download = `Vanacue_Review_${review.movie.replace(/\s+/g, '_')}.png`;
        link.href = image;
        link.click();

        if (typeof mostrarToast === 'function') mostrarToast("Imagen descargada con éxito");
    } catch (err) {
        console.error("Error al generar imagen:", err);
        if (typeof mostrarToast === 'function') mostrarToast("Error al generar la imagen");
    } finally {
        btnDown.innerHTML = originalBtnText;
        btnDown.disabled = false;
        closeShareModal();
    }
}

window.deleteComment = async function (commentId, reviewId) {
    if (!confirm("¿Segur@ que quieres eliminar este comentario?")) return;

    const token = localStorage.getItem('vanacue_token');
    if (!token) return;

    try {
        const response = await fetch(`${API_URL}/api/reviews/comment/${commentId}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const data = await response.json();
        if (data.success) {
            const container = document.getElementById(`discussion-${reviewId}`);
            if (container) renderDiscussionArea(reviewId, container);
            mostrarToast("Comentario eliminado.");
        } else {
            mostrarToast(data.message);
        }
    } catch (e) {
        console.error(e);
        mostrarToast("Error de conexión al eliminar.");
    }
}
