<script setup>
defineProps({
  pagination: { type: Object, default: null },
})
const emit = defineEmits(['change'])
</script>

<template>
  <div
    v-if="pagination && pagination.total > 0"
    class="d-flex flex-wrap justify-content-between align-items-center gap-2 p-3 border-top"
  >
    <span class="text-muted text-xs">
      {{ pagination.total }} résultat{{ pagination.total > 1 ? 's' : '' }} · page
      {{ pagination.page }} / {{ Math.max(1, pagination.pages) }}
    </span>
    <div class="btn-group btn-group-sm">
      <button
        class="btn btn-outline-secondary"
        :disabled="pagination.page <= 1"
        @click="emit('change', pagination.page - 1)"
      >
        <i class="bi bi-chevron-left"></i> Précédent
      </button>
      <button
        class="btn btn-outline-secondary"
        :disabled="pagination.page >= pagination.pages"
        @click="emit('change', pagination.page + 1)"
      >
        Suivant <i class="bi bi-chevron-right"></i>
      </button>
    </div>
  </div>
</template>
