<script setup>
import { onUnmounted, ref, watch } from 'vue'
import { fetchProtectedFile } from '../../services/api'

// Image servie par l'API derrière authentification (documents chauffeur).
const props = defineProps({
  src: { type: String, default: null },
  placeholder: { type: String, default: 'Non envoyé' },
})
const emit = defineEmits(['open'])

const objectUrl = ref(null)
const state = ref('idle')

async function load() {
  if (objectUrl.value) URL.revokeObjectURL(objectUrl.value)
  objectUrl.value = null
  if (!props.src) {
    state.value = 'empty'
    return
  }
  state.value = 'loading'
  objectUrl.value = await fetchProtectedFile(props.src)
  state.value = objectUrl.value ? 'ready' : 'error'
}

watch(() => props.src, load, { immediate: true })
onUnmounted(() => objectUrl.value && URL.revokeObjectURL(objectUrl.value))
</script>

<template>
  <div
    class="doc-thumb"
    :style="objectUrl ? { backgroundImage: `url(${objectUrl})` } : {}"
    @click="objectUrl && emit('open', objectUrl)"
  >
    <span v-if="state === 'empty'">{{ placeholder }}</span>
    <span v-else-if="state === 'loading'" class="spinner-border spinner-border-sm"></span>
    <span v-else-if="state === 'error'">Image indisponible</span>
  </div>
</template>
