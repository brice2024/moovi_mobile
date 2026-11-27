<script setup>
import { onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AppSidebar from '../components/layout/AppSidebar.vue'
import AppNavbar from '../components/layout/AppNavbar.vue'
import AppFooter from '../components/layout/AppFooter.vue'
import DetailHost from '../components/admin/DetailHost.vue'
import { useDetail } from '../composables/useDetail'
import { onSessionChange } from '../services/api'
import { usePlatformStore } from '../stores/platform'

const route = useRoute()
const router = useRouter()
const platform = usePlatformStore()
const detail = useDetail()
const isSidebarMinimized = ref(false)
const isMobileSidebarOpen = ref(false)

const toggleDesktopSidebar = () => {
  isSidebarMinimized.value = !isSidebarMinimized.value
  document.body.classList.toggle('sidebar-minimized', isSidebarMinimized.value)
  setTimeout(() => window.dispatchEvent(new Event('resize')), 300)
}

watch(
  () => route.path,
  () => {
    isMobileSidebarOpen.value = false
    detail.close()
  },
)

// Session expirée ou révoquée : retour à l'écran de connexion.
const stopSessionWatch = onSessionChange((value) => {
  if (!value) router.push({ name: 'login', query: { redirect: route.fullPath } })
})

onMounted(() => platform.startAutoRefresh())
onUnmounted(() => {
  platform.stopAutoRefresh()
  stopSessionWatch()
  document.body.classList.remove('sidebar-minimized')
})
</script>

<template>
  <div>
    <div
      class="sidebar-overlay"
      :class="{ show: isMobileSidebarOpen }"
      @click="isMobileSidebarOpen = false"
    ></div>
    <AppSidebar :class="{ show: isMobileSidebarOpen }" @close-mobile="isMobileSidebarOpen = false" />
    <div class="main-wrapper">
      <AppNavbar
        :is-sidebar-minimized="isSidebarMinimized"
        @toggle-desktop-sidebar="toggleDesktopSidebar"
        @toggle-mobile-sidebar="isMobileSidebarOpen = !isMobileSidebarOpen"
      />
      <router-view />
      <AppFooter />
    </div>
    <DetailHost @changed="detail.notifyChanged()" />
  </div>
</template>
