<script setup>
import { API_URL } from '../../services/api'
</script>

<template>
  <footer class="footer-custom">
    <div class="footer-left">
      <span class="footer-logo"> <i class="bi bi-car-front-fill"></i> Moovi Admin </span>
      <span class="footer-separator">|</span>
      <span class="footer-copy">&copy; {{ new Date().getFullYear() }} Moovi Gabon</span>
    </div>
    <div class="footer-right">
      <ul class="footer-links">
        <li><router-link to="/" class="footer-link">Tableau de bord</router-link></li>
        <li><router-link to="/settings" class="footer-link">Paramètres</router-link></li>
        <li>
          <a :href="`${API_URL}/api/docs`" target="_blank" rel="noopener" class="footer-link">Documentation API</a>
        </li>
      </ul>
    </div>
  </footer>
</template>
