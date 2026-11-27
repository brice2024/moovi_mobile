<script setup>
import { computed } from 'vue'
import { label, tone } from '../../utils/format'

const props = defineProps({
  map: { type: Object, required: true },
  value: { type: [String, Boolean, null], default: null },
})

const text = computed(() => label(props.map, props.value))
const cls = computed(() => tone(props.map, props.value))
</script>

<template>
  <span class="badge-table" :class="cls">{{ text }}</span>
</template>
