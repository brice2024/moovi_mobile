import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { ApiError, api, getSession, onSessionChange, setSession } from '../services/api'

export const useAuthStore = defineStore('auth', () => {
  const session = ref(getSession())
  onSessionChange((value) => (session.value = value))

  const user = computed(() => session.value?.user || null)
  const isAuthenticated = computed(() => !!session.value?.accessToken)

  async function login(email, password) {
    const data = await api('POST', '/api/auth/login', {
      body: { email, password },
      auth: false,
    })
    if (data.user?.role !== 'admin') {
      throw new ApiError("Ce compte n'a pas les droits d'administration.", 403, 'NOT_ADMIN')
    }
    setSession({
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
      user: data.user,
    })
  }

  /** Vérifie que la session enregistrée est toujours valide et administrateur. */
  async function verify() {
    if (!session.value) return false
    try {
      const me = await api('GET', '/api/auth/me')
      if (me.role !== 'admin') {
        setSession(null)
        return false
      }
      setSession({ ...session.value, user: me })
      return true
    } catch {
      setSession(null)
      return false
    }
  }

  async function logout() {
    const refreshToken = session.value?.refreshToken
    try {
      await api('POST', '/api/auth/logout', { body: { refreshToken } })
    } catch {
      /* session déjà expirée */
    }
    setSession(null)
  }

  return { session, user, isAuthenticated, login, verify, logout }
})
