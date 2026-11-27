import { defineStore } from 'pinia'
import { ref } from 'vue'
import { get } from '../services/api'

/** Indicateurs partagés (badges du menu, alertes de la barre du haut). */
export const usePlatformStore = defineStore('platform', () => {
  const overview = ref(null)
  const loading = ref(false)
  const error = ref('')
  let timer = null
  let lastDays = 14

  async function refresh(days = lastDays) {
    lastDays = days
    loading.value = true
    try {
      overview.value = await get('/api/admin/overview', { days })
      error.value = ''
    } catch (e) {
      error.value = e.message
    } finally {
      loading.value = false
    }
    return overview.value
  }

  function startAutoRefresh() {
    stopAutoRefresh()
    refresh()
    // Compteurs du menu : seulement quand l'onglet est affiché.
    timer = setInterval(() => {
      if (!document.hidden) refresh()
    }, 60_000)
  }

  function stopAutoRefresh() {
    if (timer) clearInterval(timer)
    timer = null
  }

  return { overview, loading, error, refresh, startAutoRefresh, stopAutoRefresh }
})
