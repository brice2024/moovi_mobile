<script setup>
import { useToastStore } from '../../stores/toast'

const toast = useToastStore()
</script>

<template>
  <div class="toast-host">
    <div
      v-for="t in toast.items"
      :key="t.id"
      class="alert shadow-sm mb-0 d-flex align-items-start gap-2"
      :class="`alert-${t.type}`"
      role="status"
    >
      <i
        class="bi mt-1"
        :class="t.type === 'danger' ? 'bi-exclamation-octagon' : 'bi-check-circle'"
      ></i>
      <div class="flex-grow-1">{{ t.message }}</div>
      <button class="btn-close" aria-label="Fermer" @click="toast.dismiss(t.id)"></button>
    </div>
  </div>
</template>
