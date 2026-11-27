<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../../stores/auth'
import { usePlatformStore } from '../../stores/platform'

const props = defineProps({
  isSidebarMinimized: { type: Boolean, default: false },
})
const emit = defineEmits(['toggle-desktop-sidebar', 'toggle-mobile-sidebar'])

const router = useRouter()
const auth = useAuthStore()
const platform = usePlatformStore()
const isFullscreen = ref(false)
const search = ref('')
const searchTarget = ref('rides')

const alerts = computed(() => {
  const a = platform.overview?.alerts || {}
  return [
    { n: a.pendingVerifications, to: '/documents', icon: 'bi-person-plus-fill', cls: 'bg-warning text-dark', text: 'dossier(s) chauffeur à valider' },
    { n: a.pendingVehicles, to: '/vehicles?verificationStatus=pending', icon: 'bi-car-front', cls: 'bg-warning text-dark', text: 'véhicule(s) à valider' },
    { n: a.duplicatePayments, to: '/payments?status=duplicate', icon: 'bi-exclamation-octagon', cls: 'bg-danger text-white', text: 'paiement(s) en double à rembourser' },
    { n: a.stalePendingPayments, to: '/payments?status=pending', icon: 'bi-hourglass-split', cls: 'bg-danger text-white', text: 'paiement(s) Mobile Money en attente depuis plus de 10 min' },
    { n: a.stalePendingRecharges, to: '/payments?tab=wallet&status=pending', icon: 'bi-wallet2', cls: 'bg-danger text-white', text: 'recharge(s) en attente depuis plus de 10 min' },
    { n: a.blockedDrivers, to: '/drivers?blocked=true', icon: 'bi-slash-circle', cls: 'bg-secondary text-white', text: 'chauffeur(s) bloqué(s) (solde négatif)' },
  ].filter((x) => x.n > 0)
})

function submitSearch() {
  const q = search.value.trim()
  if (!q) return
  router.push({ path: `/${searchTarget.value}`, query: { q } })
}

async function logout() {
  await auth.logout()
  router.push({ name: 'login' })
}

const toggleFullscreen = () => {
  if (!document.fullscreenElement) document.documentElement.requestFullscreen().catch(() => {})
  else document.exitFullscreen().catch(() => {})
}
const onFs = () => (isFullscreen.value = !!document.fullscreenElement)
onMounted(() => document.addEventListener('fullscreenchange', onFs))
onUnmounted(() => document.removeEventListener('fullscreenchange', onFs))
</script>

<template>
  <header class="navbar-custom">
    <div class="navbar-left">
      <button
        class="btn-desktop-toggle d-none d-xl-flex align-items-center justify-content-center me-3"
        aria-label="Réduire le menu"
        @click="emit('toggle-desktop-sidebar')"
      >
        <i :class="props.isSidebarMinimized ? 'bi bi-chevron-bar-right' : 'bi bi-chevron-bar-left'"></i>
      </button>
      <button class="sidebar-toggle-btn me-2" aria-label="Menu" @click="emit('toggle-mobile-sidebar')">
        <i class="bi bi-list"></i>
      </button>
    </div>

    <form class="navbar-search-wrapper d-flex" @submit.prevent="submitSearch">
      <select
        v-model="searchTarget"
        class="form-select form-select-sm border-0 bg-transparent"
        style="width: auto"
        aria-label="Rechercher dans"
      >
        <option value="rides">Courses</option>
        <option value="drivers">Chauffeurs</option>
        <option value="users">Utilisateurs</option>
        <option value="vehicles">Véhicules</option>
      </select>
      <input
        v-model="search"
        type="text"
        class="navbar-search-input"
        placeholder="Nom, téléphone, plaque, adresse, n° de course…"
      />
      <button class="navbar-search-btn" type="submit" aria-label="Rechercher">
        <i class="bi bi-search"></i>
      </button>
    </form>

    <div class="navbar-actions">
      <button class="navbar-action-btn me-1" aria-label="Plein écran" @click="toggleFullscreen">
        <i :class="isFullscreen ? 'bi bi-fullscreen-exit' : 'bi bi-arrows-fullscreen'"></i>
      </button>
      <button
        class="navbar-action-btn me-1"
        aria-label="Actualiser"
        title="Actualiser les indicateurs"
        :disabled="platform.loading"
        @click="platform.refresh()"
      >
        <i class="bi bi-arrow-clockwise"></i>
      </button>

      <div class="dropdown">
        <button
          class="navbar-action-btn dropdown-toggle"
          type="button"
          data-bs-toggle="dropdown"
          aria-expanded="false"
          data-bs-auto-close="outside"
          aria-label="Alertes"
        >
          <i class="bi bi-bell"></i>
          <span v-if="alerts.length" class="navbar-action-badge"></span>
        </button>
        <div class="dropdown-menu dropdown-menu-end dropdown-menu-notification p-0">
          <div class="notification-header">
            <h6 class="notification-title">Alertes de la plateforme</h6>
          </div>
          <div class="notification-list">
            <router-link v-for="a in alerts" :key="a.text" :to="a.to" class="notification-item">
              <div class="notification-icon" :class="a.cls"><i class="bi" :class="a.icon"></i></div>
              <div class="notification-content">
                <p class="notification-text"><strong>{{ a.n }}</strong> {{ a.text }}</p>
              </div>
            </router-link>
            <div v-if="!alerts.length" class="p-3 text-muted text-center text-xs">
              <i class="bi bi-check-circle me-1"></i> Aucune alerte en cours
            </div>
          </div>
          <div v-if="platform.error" class="p-2 text-danger text-xs border-top">{{ platform.error }}</div>
        </div>
      </div>

      <div class="dropdown ms-2">
        <button
          class="navbar-profile-btn dropdown-toggle"
          type="button"
          data-bs-toggle="dropdown"
          aria-expanded="false"
        >
          <span
            class="navbar-profile-img d-inline-flex align-items-center justify-content-center bg-lime-accent text-dark fw-bold"
            >{{ (auth.user?.firstName || 'A').charAt(0) }}</span
          >
          <span class="navbar-profile-name d-none d-md-inline">{{ auth.user?.fullname || 'Administrateur' }}</span>
          <i class="bi bi-chevron-down navbar-profile-caret"></i>
        </button>
        <ul class="dropdown-menu dropdown-menu-end dropdown-menu-profile">
          <li class="dropdown-header">{{ auth.user?.email }}</li>
          <li>
            <router-link class="dropdown-item" to="/settings"><i class="bi bi-gear"></i> Paramètres</router-link>
          </li>
          <li><hr class="dropdown-divider" /></li>
          <li>
            <button class="dropdown-item text-danger" type="button" @click="logout">
              <i class="bi bi-box-arrow-right"></i> Déconnexion
            </button>
          </li>
        </ul>
      </div>
    </div>
  </header>
</template>
