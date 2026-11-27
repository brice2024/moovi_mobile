// Client de l'API Moovi pour le back-office.
//
// L'adresse de l'API vient de VITE_API_URL (fichiers .env*). Vide = même
// origine que la page (back-office servi par l'API sur /admin).

const SESSION_KEY = 'moovi_admin_session'

export const API_URL = (import.meta.env.VITE_API_URL || window.location.origin).replace(/\/$/, '')

export class ApiError extends Error {
  constructor(message, status, code, details) {
    super(message)
    this.status = status
    this.code = code
    this.details = details
  }
}

let session = loadSession()
let refreshing = null
const listeners = new Set()

function loadSession() {
  try {
    return JSON.parse(localStorage.getItem(SESSION_KEY)) || null
  } catch {
    return null
  }
}

export function getSession() {
  return session
}

export function setSession(value) {
  session = value
  if (value) localStorage.setItem(SESSION_KEY, JSON.stringify(value))
  else localStorage.removeItem(SESSION_KEY)
  listeners.forEach((fn) => fn(value))
}

export function onSessionChange(fn) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

function buildUrl(path, query) {
  const url = new URL(API_URL + path)
  Object.entries(query || {}).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') url.searchParams.set(key, value)
  })
  return url.toString()
}

async function refreshAccessToken() {
  if (!session?.refreshToken) return false
  refreshing ??= fetch(API_URL + '/api/auth/refresh', {
    method: 'POST',
    headers: { Authorization: `Bearer ${session.refreshToken}` },
  })
    .then(async (res) => {
      if (!res.ok) return false
      const json = await res.json()
      setSession({ ...session, accessToken: json.data.accessToken })
      return true
    })
    .catch(() => false)
    .finally(() => {
      refreshing = null
    })
  return refreshing
}

/**
 * Appelle l'API et renvoie `data`. Lève ApiError avec le message de l'API.
 * Un jeton expiré est renouvelé une fois automatiquement.
 */
export async function api(method, path, { body, query, auth = true, retry = true } = {}) {
  const headers = { Accept: 'application/json' }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (auth && session?.accessToken) headers.Authorization = `Bearer ${session.accessToken}`

  let res
  try {
    res = await fetch(buildUrl(path, query), {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    })
  } catch {
    throw new ApiError(`API injoignable (${API_URL}). Vérifiez que le serveur est démarré.`, 0, 'NETWORK')
  }

  let json = {}
  try {
    json = await res.json()
  } catch {
    /* réponse vide */
  }

  if (res.status === 401 && auth && retry) {
    if (await refreshAccessToken()) return api(method, path, { body, query, auth, retry: false })
    setSession(null)
  }
  if (!res.ok || json.success === false) {
    const error = json.error || {}
    throw new ApiError(
      error.message || json.message || `Erreur ${res.status}`,
      res.status,
      error.code,
      error.details,
    )
  }
  return json.data ?? {}
}

export const get = (path, query) => api('GET', path, { query })
export const post = (path, body) => api('POST', path, { body: body ?? {} })
export const patch = (path, body) => api('PATCH', path, { body: body ?? {} })

/**
 * Charge un fichier protégé (documents chauffeur) et renvoie une URL locale.
 * Le jeton n'est envoyé qu'à l'API configurée, jamais à une autre adresse.
 */
export async function fetchProtectedFile(fileUrl) {
  if (!fileUrl) return null
  let path
  try {
    const parsed = new URL(fileUrl, API_URL)
    path = parsed.pathname + parsed.search
  } catch {
    return null
  }
  if (!path.startsWith('/api/files/')) return null
  const res = await fetch(API_URL + path, {
    headers: { Authorization: `Bearer ${session?.accessToken || ''}` },
  })
  if (!res.ok) return null
  return URL.createObjectURL(await res.blob())
}
