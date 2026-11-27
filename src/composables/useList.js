import { reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { get } from '../services/api'
import { useDetail } from './useDetail'

/**
 * Liste paginée liée à une route de l'API, avec filtres synchronisés dans
 * l'URL (?q=…&status=…) et rechargement après une action dans une fiche.
 */
export function useList(endpoint, key, defaults = {}, { urlSync = true } = {}) {
  const route = useRoute()
  const router = useRouter()
  const detail = useDetail()

  const filters = reactive({ ...defaults })
  if (urlSync) {
    Object.keys(defaults).forEach((k) => {
      if (route.query[k] !== undefined) filters[k] = route.query[k]
    })
  }
  const page = ref((urlSync && Number(route.query.page)) || 1)
  const items = ref([])
  const pagination = ref(null)
  const loading = ref(false)
  const error = ref('')

  async function load() {
    loading.value = true
    error.value = ''
    try {
      const data = await get(typeof endpoint === 'function' ? endpoint() : endpoint, {
        ...filters,
        page: page.value,
      })
      items.value = data[key] || []
      pagination.value = data.pagination || null
    } catch (e) {
      error.value = e.message
    } finally {
      loading.value = false
    }
  }

  function syncUrl() {
    if (!urlSync) return
    const query = { ...route.query }
    Object.entries(filters).forEach(([k, v]) => {
      if (v === '' || v === null || v === undefined || v === defaults[k]) delete query[k]
      else query[k] = v
    })
    if (page.value > 1) query.page = page.value
    else delete query.page
    router.replace({ query })
  }

  let debounce = null
  watch(
    filters,
    () => {
      clearTimeout(debounce)
      debounce = setTimeout(() => {
        page.value = 1
        syncUrl()
        load()
      }, 300)
    },
    { deep: true },
  )

  // Recherche lancée depuis la barre du haut (même page, nouvelle requête).
  watch(
    () => route.query.q,
    (q) => {
      if (urlSync && 'q' in defaults && (q || '') !== filters.q) filters.q = q || ''
    },
  )

  watch(detail.changes, load)

  function goTo(p) {
    page.value = p
    syncUrl()
    load()
  }

  load()
  return { filters, items, pagination, loading, error, load, goTo }
}
