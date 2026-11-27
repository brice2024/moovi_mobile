<script setup>
import { computed, nextTick, onMounted, onUnmounted, reactive, ref, watch } from 'vue'
import { createOsmProvider } from '../components/map/mapProviders'
import { useDetail } from '../composables/useDetail'
import { get } from '../services/api'
import { acquireSocket, releaseSocket } from '../services/realtime'
import { RIDE_STATUS, VEHICLE_TYPE, label, parseDate, timeAgo } from '../utils/format'

const DEFAULT_CENTER = [0.4162, 9.4673] // Libreville
const STATES = {
  available: { text: 'Disponible', color: '#22C55E' },
  busy: { text: 'En course', color: '#F97316' },
  offline: { text: 'Hors ligne', color: '#94A3B8' },
}
const VEHICLE_ICON = { voiture: 'bi-car-front-fill', confort: 'bi-car-front-fill', moto: 'bi-scooter' }
const BUSY_STATUSES = ['accepted', 'driver_arrived', 'in_progress']
const STALE_MS = 2 * 60 * 1000

const detail = useDetail()
const mapEl = ref(null)
const drivers = ref([])
const loading = ref(false)
const error = ref('')
const live = ref(false)
const lastEvent = ref(null)
const selectedId = ref(null)
const now = ref(Date.now())
const filters = reactive({ available: true, busy: true, offline: false, vehicleType: '', q: '' })

let map = null
let socket = null
let clock = null
let connectedOnce = false
let fittedOnce = false

const escapeHtml = (v) =>
  String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])

const isStale = (d) => {
  const at = parseDate(d.lastLocationAt)
  return !at || now.value - at.getTime() > STALE_MS
}

const counts = computed(() => {
  const c = { available: 0, busy: 0, offline: 0 }
  drivers.value.forEach((d) => c[d.state]++)
  return c
})

const visible = computed(() => {
  const q = filters.q.trim().toLowerCase()
  const order = ['busy', 'available', 'offline']
  return drivers.value
    .filter((d) => filters[d.state])
    .filter((d) => !filters.vehicleType || d.vehicleType === filters.vehicleType)
    .filter((d) => !q || [d.name, d.phoneNumber, d.plate, d.vehicleLabel].some((v) => (v || '').toLowerCase().includes(q)))
    .sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state))
})

function pinHtml(d) {
  const stale = d.state !== 'offline' && isStale(d)
  const heading =
    d.state !== 'offline' && d.heading != null
      ? `<span class="driver-heading" style="transform: rotate(${Number(d.heading) || 0}deg)"></span>`
      : ''
  return `<div class="driver-pin ${d.id === selectedId.value ? 'selected' : ''} ${stale ? 'stale' : ''}"
    style="background:${STATES[d.state].color}" title="${escapeHtml(d.name || '')}">
    <i class="bi ${VEHICLE_ICON[d.vehicleType] || 'bi-car-front-fill'}"></i>${heading}</div>`
}

function popupHtml(d) {
  const ride = d.ride
    ? `<div class="mt-1"><span class="badge bg-warning text-dark">${escapeHtml(label(RIDE_STATUS, d.ride.status))}</span>
       vers ${escapeHtml(d.ride.destination || '—')}</div>
       <button class="btn btn-sm btn-outline-dark mt-2 w-100" data-open-ride="${escapeHtml(d.ride.id)}">Voir la course</button>`
    : ''
  return `<div style="min-width:220px;font-family:'Plus Jakarta Sans',sans-serif">
    <div class="fw-bold">${escapeHtml(d.name || 'Chauffeur')}</div>
    <div class="text-muted small">${escapeHtml(d.phoneNumber || '')}</div>
    <div class="small mt-1">${escapeHtml(label(VEHICLE_TYPE, d.vehicleType))} · ${escapeHtml(d.vehicleLabel || '')}
      · <span style="font-family:monospace">${escapeHtml(d.plate || '')}</span></div>
    <div class="small mt-1"><span style="color:${STATES[d.state].color}">●</span> ${STATES[d.state].text}
      · position ${escapeHtml(timeAgo(d.lastLocationAt))}${d.isWalletBlocked ? ' · <span class="text-danger">bloqué</span>' : ''}</div>
    ${ride}
    <button class="btn btn-sm btn-dark mt-2 w-100" data-open-driver="${escapeHtml(d.id)}">Ouvrir la fiche</button>
  </div>`
}

function render() {
  if (!map) return
  const keep = new Set()
  for (const d of visible.value) {
    keep.add(d.id)
    map.upsert(d.id, {
      lat: d.latitude,
      lng: d.longitude,
      html: pinHtml(d),
      onClick: () => select(d.id, false),
    })
    map.refreshPopup(d.id, popupHtml(d))
  }
  for (const d of drivers.value) if (!keep.has(d.id)) map.remove(d.id)
  // Marqueurs de chauffeurs disparus de la liste
  if (render.shown) for (const id of render.shown) if (!keep.has(id)) map.remove(id)
  render.shown = keep
  if (!fittedOnce && visible.value.length) {
    fittedOnce = true
    fitAll()
  }
}

function fitAll() {
  map?.fit(visible.value.map((d) => [d.latitude, d.longitude]))
}

function select(id, move = true) {
  const d = drivers.value.find((x) => x.id === id)
  if (!d || !map) return
  selectedId.value = id
  if (move) map.focus(d.latitude, d.longitude)
  nextTick(() => map.openPopup(id, popupHtml(d)))
}

async function load() {
  loading.value = true
  try {
    const data = await get('/api/admin/drivers/map', { scope: filters.offline ? 'all' : 'online' })
    drivers.value = data.drivers
    error.value = ''
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

// ── Temps réel ──────────────────────────────────────────────────────────
/** Fiche complète envoyée par l'API à chaque position (aucune requête). */
function onDriverUpdate(entry) {
  lastEvent.value = entry.lastLocationAt || new Date().toISOString()
  const i = drivers.value.findIndex((x) => x.id === entry.id)
  if (i === -1) drivers.value.push(entry)
  else Object.assign(drivers.value[i], entry)
}

function onAvailability(p) {
  lastEvent.value = new Date().toISOString()
  const d = drivers.value.find((x) => x.id === p.driverId)
  if (!d) return // apparaîtra avec sa prochaine position
  d.isAvailable = !!p.isAvailable
  if (!d.ride) d.state = p.isAvailable ? 'available' : 'offline'
}

function onRide(ride) {
  lastEvent.value = new Date().toISOString()
  const d = drivers.value.find((x) => x.id === ride.driverId)
  if (!d) return
  if (BUSY_STATUSES.includes(ride.status)) {
    d.state = 'busy'
    d.ride = { id: ride.id, status: ride.status, destination: ride.destinationAddress }
  } else {
    d.ride = null
    d.state = d.isAvailable ? 'available' : 'offline'
  }
}

function onMapClickDelegate(e) {
  const driverBtn = e.target.closest?.('[data-open-driver]')
  const rideBtn = e.target.closest?.('[data-open-ride]')
  if (driverBtn) detail.open('driver', driverBtn.dataset.openDriver)
  if (rideBtn) detail.open('ride', rideBtn.dataset.openRide)
}

watch(visible, render, { deep: true })
watch(selectedId, render)
watch(now, render)
watch(() => filters.offline, load)

onMounted(async () => {
  mapEl.value.addEventListener('click', onMapClickDelegate)
  map = await createOsmProvider(mapEl.value, {
    center: DEFAULT_CENTER,
    zoom: 13,
    onMapClick: () => (selectedId.value = null),
  })
  await load() // chargement unique : ensuite, tout arrive en temps réel
  render()

  socket = acquireSocket()
  socket.on('connect', () => {
    live.value = true
    // Après une coupure seulement : rattrape les événements manqués.
    if (connectedOnce) load()
    connectedOnce = true
  })
  socket.on('disconnect', () => (live.value = false))
  socket.on('admin:driver_update', onDriverUpdate)
  socket.on('driver:availability_changed', onAvailability)
  for (const ev of ['ride:accepted', 'ride:status_changed', 'ride:cancelled', 'ride:paid']) socket.on(ev, onRide)
  live.value = socket.connected
  connectedOnce = socket.connected

  // Horloge locale (aucune requête) : « il y a … » et signal perdu.
  clock = setInterval(() => (now.value = Date.now()), 15000)
})

onUnmounted(() => {
  clearInterval(clock)
  if (socket) {
    socket.off('admin:driver_update', onDriverUpdate)
    socket.off('driver:availability_changed', onAvailability)
    for (const ev of ['ride:accepted', 'ride:status_changed', 'ride:cancelled', 'ride:paid']) socket.off(ev, onRide)
    socket.off('connect')
    socket.off('disconnect')
    releaseSocket()
  }
  mapEl.value?.removeEventListener('click', onMapClickDelegate)
  map?.destroy()
  map = null
})
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Carte des chauffeurs</h1>
        <p class="page-subtitle mb-0">
          Position de chaque chauffeur en temps réel.
          <span class="badge ms-1" :class="live ? 'bg-success' : 'bg-secondary'">
            <i class="bi" :class="live ? 'bi-broadcast' : 'bi-wifi-off'"></i>
            {{ live ? 'En direct' : 'Reconnexion…' }}
          </span>
          <span v-if="lastEvent" class="text-muted ms-1 text-xs">· dernier signal {{ timeAgo(lastEvent) }}</span>
        </p>
      </div>
      <div class="d-flex gap-2">
        <button class="btn btn-sm btn-outline-dark" @click="fitAll"><i class="bi bi-arrows-fullscreen"></i> Tout afficher</button>
        <button class="btn btn-sm btn-dark" :disabled="loading" @click="load"><i class="bi bi-arrow-clockwise"></i> Actualiser</button>
      </div>
    </div>

    <div v-if="error" class="alert alert-danger">{{ error }}</div>

    <div class="row g-3">
      <div class="col-xl-9">
        <div class="map-card">
          <div ref="mapEl" class="map-canvas"></div>
          <div class="map-legend">
            <label v-for="(s, key) in STATES" :key="key" class="d-flex align-items-center gap-2 small cursor-pointer">
              <input v-model="filters[key]" type="checkbox" class="form-check-input m-0" />
              <span class="legend-dot" :style="{ background: s.color }"></span>
              {{ s.text }}
              <strong>{{ counts[key] }}</strong>
            </label>
          </div>
        </div>
      </div>

      <div class="col-xl-3">
        <div class="table-card-custom d-flex flex-column" style="height: calc(100vh - 230px); min-height: 420px">
          <div class="p-3 border-bottom d-flex flex-column gap-2">
            <div class="table-search-box">
              <i class="bi bi-search table-search-icon"></i>
              <input v-model="filters.q" class="table-search-input" placeholder="Nom, téléphone, plaque…" />
            </div>
            <select v-model="filters.vehicleType" class="form-select form-select-sm">
              <option value="">Tous véhicules</option>
              <option value="voiture">Voiture</option>
              <option value="moto">Moto</option>
              <option value="confort">Confort</option>
            </select>
            <span class="text-xs text-muted">{{ visible.length }} chauffeur(s) affiché(s)</span>
          </div>
          <div class="flex-grow-1 overflow-auto">
            <button
              v-for="d in visible"
              :key="d.id"
              type="button"
              class="driver-row"
              :class="{ active: d.id === selectedId }"
              @click="select(d.id)"
            >
              <span class="legend-dot" :style="{ background: STATES[d.state].color }"></span>
              <span class="flex-grow-1 text-start min-w-0">
                <span class="d-block fw-semibold text-truncate">{{ d.name || 'Chauffeur' }}</span>
                <span class="d-block text-xs text-muted text-truncate">
                  {{ label(VEHICLE_TYPE, d.vehicleType) }} · {{ d.plate }} · {{ timeAgo(d.lastLocationAt) }}
                </span>
                <span v-if="d.ride" class="d-block text-xs text-warning text-truncate">
                  {{ label(RIDE_STATUS, d.ride.status) }} → {{ d.ride.destination }}
                </span>
              </span>
              <i
                v-if="d.state !== 'offline' && isStale(d)"
                class="bi bi-exclamation-triangle text-warning"
                title="Pas de position depuis plus de 2 min"
              ></i>
            </button>
            <div v-if="!visible.length && !loading" class="p-4 text-center text-muted small">
              Aucun chauffeur à afficher.
              <div v-if="!filters.offline" class="mt-1">Cochez « Hors ligne » pour voir les dernières positions connues.</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style>
.map-card {
  position: relative;
  border-radius: 16px;
  overflow: hidden;
  border: 1px solid var(--border-light);
  background: #fff;
}
.map-canvas {
  height: calc(100vh - 230px);
  min-height: 420px;
  z-index: 0;
}
.map-legend {
  position: absolute;
  left: 12px;
  bottom: 24px;
  z-index: 500;
  background: #fff;
  border-radius: 12px;
  padding: 0.6rem 0.8rem;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}
.legend-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  display: inline-block;
  flex: none;
}
.driver-marker {
  background: none;
  border: none;
}
.driver-pin {
  position: relative;
  width: 34px;
  height: 34px;
  border-radius: 50%;
  border: 3px solid #fff;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 15px;
  transition: transform 0.2s;
}
.driver-pin.selected {
  transform: scale(1.25);
  border-color: var(--brand-lime);
  z-index: 2;
}
.driver-pin.stale {
  opacity: 0.6;
}
.driver-heading {
  position: absolute;
  inset: -9px;
  pointer-events: none;
}
.driver-heading::before {
  content: '';
  position: absolute;
  left: 50%;
  top: 0;
  transform: translateX(-50%);
  border-left: 5px solid transparent;
  border-right: 5px solid transparent;
  border-bottom: 7px solid var(--brand-forest-dark);
}
.driver-row {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  width: 100%;
  border: none;
  border-bottom: 1px solid var(--border-light);
  background: #fff;
  padding: 0.6rem 1rem;
}
.driver-row:hover,
.driver-row.active {
  background: #f4f6f5;
}
</style>
