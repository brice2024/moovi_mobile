<script setup>
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { API_URL } from '../services/api'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const loading = ref(false)
const error = ref('')

async function submit() {
  error.value = ''
  loading.value = true
  try {
    await auth.login(email.value.trim(), password.value)
    router.replace(route.query.redirect?.toString() || '/')
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-wrapper">
    <div class="login-bg-shape login-bg-shape-1"></div>
    <div class="login-bg-shape login-bg-shape-2"></div>

    <div class="login-card">
      <div class="login-brand">
        <i class="bi bi-car-front-fill"></i>
        <span>Moovi Admin</span>
      </div>
      <p class="login-subtitle">Back-office de la plateforme Moovi Gabon</p>

      <form @submit.prevent="submit">
        <div class="login-form-group">
          <label for="email" class="login-form-label">Adresse e-mail</label>
          <div class="login-input-group">
            <i class="bi bi-envelope input-icon"></i>
            <input
              id="email"
              v-model="email"
              type="email"
              class="login-input"
              placeholder="admin@moovi.ga"
              autocomplete="username"
              required
            />
          </div>
        </div>

        <div class="login-form-group">
          <label for="password" class="login-form-label">Mot de passe</label>
          <div class="login-input-group">
            <i class="bi bi-shield-lock input-icon"></i>
            <input
              id="password"
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              class="login-input login-input-password"
              placeholder="••••••••"
              autocomplete="current-password"
              required
            />
            <button
              type="button"
              class="password-toggle-btn"
              :aria-label="showPassword ? 'Masquer' : 'Afficher'"
              @click="showPassword = !showPassword"
            >
              <i :class="showPassword ? 'bi bi-eye-slash' : 'bi bi-eye'"></i>
            </button>
          </div>
        </div>

        <div v-if="error" class="alert alert-danger py-2 small">{{ error }}</div>

        <button type="submit" class="btn-login" :disabled="loading">
          <span>{{ loading ? 'Connexion…' : 'Se connecter' }}</span>
          <i class="bi bi-arrow-right"></i>
        </button>
      </form>

      <p class="login-footer-text">
        Réservé aux comptes administrateurs.<br />
        <span class="text-muted text-xs">API : {{ API_URL }}</span>
      </p>
    </div>
  </div>
</template>
