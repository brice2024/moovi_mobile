<script setup>
import { computed } from 'vue'
import { useAuthStore } from '../../stores/auth'
import { usePlatformStore } from '../../stores/platform'

defineEmits(['close-mobile'])
const auth = useAuthStore()
const platform = usePlatformStore()

const alerts = computed(() => platform.overview?.alerts || {})
const drivers = computed(() => platform.overview?.drivers || {})

const sections = computed(() => [
  {
    title: 'Supervision',
    items: [
      { to: '/', icon: 'bi-grid-fill', label: 'Tableau de bord', exact: true },
      { to: '/map', icon: 'bi-geo-alt-fill', label: 'Carte des chauffeurs', badge: drivers.value.online, tone: 'success' },
      { to: '/rides', icon: 'bi-signpost-2-fill', label: 'Courses', badge: alerts.value.unpaidCompletedRides, tone: 'secondary' },
      {
        to: '/payments',
        icon: 'bi-cash-coin',
        label: 'Paiements',
        badge: (alerts.value.duplicatePayments || 0) + (alerts.value.stalePendingPayments || 0),
        tone: 'danger',
      },
    ],
  },
  {
    title: 'Chauffeurs & flotte',
    items: [
      { to: '/drivers', icon: 'bi-person-badge-fill', label: `Chauffeurs${drivers.value.total != null ? ` (${drivers.value.total})` : ''}` },
      { to: '/documents', icon: 'bi-file-earmark-check-fill', label: 'Validation des dossiers', badge: alerts.value.pendingVerifications, tone: 'warning' },
      { to: '/vehicles', icon: 'bi-car-front-fill', label: 'Flotte', badge: alerts.value.pendingVehicles, tone: 'warning' },
    ],
  },
  {
    title: 'Clients & marketing',
    items: [
      { to: '/users', icon: 'bi-people-fill', label: 'Utilisateurs' },
      { to: '/promo-codes', icon: 'bi-ticket-perforated-fill', label: 'Codes promo' },
      { to: '/notifications', icon: 'bi-megaphone-fill', label: 'Notifications' },
    ],
  },
  {
    title: 'Système',
    items: [{ to: '/settings', icon: 'bi-gear-fill', label: 'Paramètres' }],
  },
])
</script>

<template>
  <div class="sidebar-wrapper" id="sidebar">
    <router-link to="/" class="sidebar-brand">
      <i class="bi bi-car-front-fill text-lime"></i>
      <span>Moovi Admin</span>
    </router-link>

    <div class="flex-grow-1 overflow-y-auto">
      <div v-for="section in sections" :key="section.title" class="sidebar-menu-section">
        <div class="sidebar-menu-title">{{ section.title }}</div>
        <ul class="sidebar-menu-list">
          <li v-for="item in section.items" :key="item.to" class="sidebar-menu-item">
            <router-link
              :to="item.to"
              class="sidebar-menu-link"
              :exact-active-class="item.exact ? 'active' : ''"
              :active-class="item.exact ? '' : 'active'"
              :title="item.label"
              @click="$emit('close-mobile')"
            >
              <i class="bi" :class="item.icon"></i>
              <span>{{ item.label }}</span>
              <span
                v-if="item.badge > 0"
                class="badge ms-auto fs-xs"
                :class="item.tone === 'warning' ? 'bg-warning text-dark' : `bg-${item.tone}`"
              >
                {{ item.badge }}
              </span>
            </router-link>
          </li>
        </ul>
      </div>
    </div>

    <div class="sidebar-profile">
      <div
        class="sidebar-profile-img d-flex align-items-center justify-content-center bg-lime-accent text-dark fw-bold"
      >
        {{ (auth.user?.firstName || 'A').charAt(0) }}
      </div>
      <div class="sidebar-profile-info">
        <div class="sidebar-profile-name">{{ auth.user?.fullname || 'Administrateur' }}</div>
        <div class="sidebar-profile-email">{{ auth.user?.email }}</div>
      </div>
    </div>
  </div>
</template>
