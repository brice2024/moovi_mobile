<script setup>
import { onMounted, onUnmounted } from 'vue'

defineProps({
  size: { type: String, default: 'xl' },
})
const emit = defineEmits(['close'])

const onKey = (e) => {
  if (e.key === 'Escape') emit('close')
}
onMounted(() => {
  document.addEventListener('keydown', onKey)
  document.body.style.overflow = 'hidden'
})
onUnmounted(() => {
  document.removeEventListener('keydown', onKey)
  document.body.style.overflow = ''
})
</script>

<template>
  <Teleport to="body">
    <div class="moovi-modal-backdrop" @mousedown.self="emit('close')">
      <div class="moovi-modal" :class="`size-${size}`" role="dialog" aria-modal="true">
        <div class="moovi-modal-header">
          <div class="flex-grow-1 min-w-0"><slot name="header" /></div>
          <button class="btn btn-sm btn-outline-light" aria-label="Fermer" @click="emit('close')">
            <i class="bi bi-x-lg"></i>
          </button>
        </div>
        <slot name="tabs" />
        <div class="moovi-modal-body">
          <slot />
        </div>
      </div>
    </div>
  </Teleport>
</template>
