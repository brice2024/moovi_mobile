import { createRouter, createWebHistory } from 'vue-router'
import DefaultLayout from '../layouts/DefaultLayout.vue'
import { useAuthStore } from '../stores/auth'

const page = (title, loader) => ({ component: loader, meta: { title } })

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  scrollBehavior() {
    return { top: 0 }
  },
  routes: [
    {
      path: '/',
      component: DefaultLayout,
      meta: { requiresAuth: true },
      children: [
        { path: '', name: 'dashboard', ...page('Tableau de bord', () => import('../views/DashboardView.vue')) },
        { path: 'map', name: 'map', ...page('Carte des chauffeurs', () => import('../views/MapView.vue')) },
        { path: 'drivers', name: 'drivers', ...page('Chauffeurs', () => import('../views/DriversView.vue')) },
        { path: 'documents', name: 'documents', ...page('Validation des dossiers', () => import('../views/DocumentsValidationView.vue')) },
        { path: 'vehicles', name: 'vehicles', ...page('Flotte', () => import('../views/VehiclesView.vue')) },
        { path: 'rides', name: 'rides', ...page('Courses', () => import('../views/RidesView.vue')) },
        { path: 'users', name: 'users', ...page('Utilisateurs', () => import('../views/UsersView.vue')) },
        { path: 'payments', name: 'payments', ...page('Paiements', () => import('../views/PaymentsView.vue')) },
        { path: 'promo-codes', name: 'promo-codes', ...page('Codes promo', () => import('../views/PromoCodesView.vue')) },
        { path: 'notifications', name: 'notifications', ...page('Notifications', () => import('../views/NotificationsView.vue')) },
        { path: 'settings', name: 'settings', ...page('Paramètres', () => import('../views/SettingsView.vue')) },
      ],
    },
    { path: '/login', name: 'login', ...page('Connexion', () => import('../views/LoginView.vue')) },
    { path: '/:pathMatch(.*)*', name: 'not-found', ...page('Page introuvable', () => import('../views/NotFoundView.vue')) },
  ],
})

let verified = false

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (to.matched.some((r) => r.meta.requiresAuth)) {
    if (!auth.isAuthenticated) return { name: 'login', query: { redirect: to.fullPath } }
    // Une fois par chargement : la session enregistrée est-elle encore valide ?
    if (!verified) {
      verified = true
      if (!(await auth.verify())) return { name: 'login', query: { redirect: to.fullPath } }
    }
  }
  if (to.name === 'login' && auth.isAuthenticated) return { name: 'dashboard' }
})

router.afterEach((to) => {
  document.title = to.meta.title ? `${to.meta.title} · Moovi Admin` : 'Moovi Admin'
})

export default router
