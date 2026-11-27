<script setup>
import { onMounted, onUnmounted, ref, watch } from 'vue'

// Enveloppe minimale d'ApexCharts (chargé globalement par index.html).
const props = defineProps({
  options: { type: Object, required: true },
})

const el = ref(null)
let chart = null

function render() {
  if (!el.value || !window.ApexCharts) return
  if (chart) chart.destroy()
  chart = new window.ApexCharts(el.value, {
    ...props.options,
    chart: { fontFamily: 'Plus Jakarta Sans, sans-serif', toolbar: { show: false }, ...props.options.chart },
  })
  chart.render()
}

onMounted(render)
watch(() => props.options, render, { deep: true })
onUnmounted(() => chart && chart.destroy())
</script>

<template>
  <div ref="el"></div>
</template>
