<script setup>
import { ref } from 'vue'
import ModalShell from '../ui/ModalShell.vue'
import StatusBadge from '../ui/StatusBadge.vue'
import { get, post } from '../../services/api'
import { useToastStore } from '../../stores/toast'
import { PAYMENT_METHOD, RIDE_STATUS, dateOnly, dateTime, label, money, shortId } from '../../utils/format'

const props = defineProps({ userId: { type: String, required: true } })
const emit = defineEmits(['close', 'changed', 'open-ride', 'open-driver'])

const toast = useToastStore()
const data = ref(null)
const busy = ref(false)
const message = ref({ title: '', body: '' })

async function load() {
  try {
    data.value = await get(`/api/admin/users/${props.userId}`)
  } catch (e) {
    toast.error(e.message)
  }
}
load()

async function setActive(isActive) {
  let reason = ''
  if (!isActive) {
    reason = window.prompt('Motif de la suspension :')
    if (reason === null) return
  }
  busy.value = true
  try {
    await post(`/api/admin/users/${props.userId}/status`, { isActive, reason })
    toast.success(isActive ? 'Compte réactivé.' : 'Compte suspendu.')
    await load()
    emit('changed')
  } catch (e) {
    toast.error(e.message)
  } finally {
    busy.value = false
  }
}

async function sendMessage() {
  busy.value = true
  try {
    await post('/api/admin/notifications', { audience: 'user', userId: props.userId, ...message.value })
    toast.success('Notification envoyée.')
    message.value = { title: '', body: '' }
  } catch (e) {
    toast.error(e.message)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalShell @close="emit('close')">
    <template #header>
      <div v-if="data" class="d-flex flex-wrap align-items-center gap-2">
        <h5 class="mb-0 fw-bold text-white">{{ data.user.fullname || 'Sans nom' }}</h5>
        <span class="badge" :class="data.user.isActive ? 'bg-success' : 'bg-danger'">
          {{ data.user.isActive ? 'Actif' : 'Suspendu' }}
        </span>
        <span v-if="data.user.role === 'admin'" class="badge bg-warning text-dark">Administrateur</span>
        <span v-if="data.user.isDriver" class="badge bg-info text-dark">Chauffeur</span>
      </div>
      <span v-else class="text-white">Chargement…</span>
    </template>

    <div v-if="!data" class="text-center py-5"><span class="spinner-border"></span></div>

    <div v-else class="row g-4">
      <div class="col-lg-4">
        <div class="kpi-card mb-3">
          <div class="kpi-label">Contact</div>
          <div class="fw-semibold">{{ data.user.phoneNumber || '—' }}</div>
          <div class="small text-muted">{{ data.user.email || 'Pas d’e-mail' }}</div>
          <div class="text-xs text-muted mt-2">Inscrit le {{ dateOnly(data.user.createdAt) }}</div>
        </div>
        <div class="row g-2 mb-3">
          <div class="col-6">
            <div class="kpi-card">
              <div class="kpi-label">Courses</div>
              <div class="kpi-value fs-5">{{ data.user.ridesCount }}</div>
            </div>
          </div>
          <div class="col-6">
            <div class="kpi-card">
              <div class="kpi-label">Dépensé</div>
              <div class="kpi-value fs-6">{{ money(data.totalSpent) }}</div>
            </div>
          </div>
          <div class="col-12">
            <div class="kpi-card">
              <div class="kpi-label">Note passager</div>
              <div class="fw-bold">
                {{ data.user.rating?.toFixed(1) }} <i class="bi bi-star-fill text-warning"></i>
                <span class="text-muted small">({{ data.user.ratingCount }} avis)</span>
              </div>
            </div>
          </div>
        </div>

        <button
          v-if="data.user.isDriver"
          class="btn btn-outline-dark btn-sm w-100 mb-2"
          @click="emit('open-driver', data.user.driver?.id)"
        >
          <i class="bi bi-person-badge"></i> Ouvrir la fiche chauffeur
        </button>
        <template v-if="data.user.role !== 'admin'">
          <button
            v-if="data.user.isActive"
            class="btn btn-danger btn-sm w-100"
            :disabled="busy"
            @click="setActive(false)"
          >
            Suspendre le compte
          </button>
          <button v-else class="btn btn-success btn-sm w-100" :disabled="busy" @click="setActive(true)">
            Réactiver le compte
          </button>
        </template>

        <form class="kpi-card mt-3" @submit.prevent="sendMessage">
          <div class="kpi-label mb-2">Envoyer une notification</div>
          <input v-model="message.title" class="form-control form-control-sm mb-2" placeholder="Titre" required maxlength="140" />
          <textarea v-model="message.body" class="form-control form-control-sm mb-2" rows="3" placeholder="Message" required maxlength="500"></textarea>
          <button class="btn btn-dark btn-sm w-100" :disabled="busy">Envoyer</button>
        </form>
      </div>

      <div class="col-lg-8">
        <h6 class="fw-bold">Dernières courses (passager)</h6>
        <div class="table-responsive">
          <table class="table-custom align-middle">
            <thead>
              <tr>
                <th>Course</th>
                <th>Trajet</th>
                <th>Statut</th>
                <th class="text-end">Prix</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in data.rides" :key="r.id" class="cursor-pointer" @click="emit('open-ride', r.id)">
                <td>
                  <div class="mono small">#{{ shortId(r.id) }}</div>
                  <div class="text-xs text-muted">{{ dateTime(r.createdAt) }}</div>
                </td>
                <td class="small">{{ r.departureAddress }} → {{ r.destinationAddress }}</td>
                <td>
                  <StatusBadge :map="RIDE_STATUS" :value="r.status" />
                  <div v-if="r.isPaid" class="text-xs text-muted">{{ label(PAYMENT_METHOD, r.paymentMethod) }}</div>
                </td>
                <td class="text-end fw-bold">{{ money(r.finalPrice) }}</td>
              </tr>
              <tr v-if="!data.rides.length">
                <td colspan="4" class="text-center text-muted py-4">Aucune course.</td>
              </tr>
            </tbody>
          </table>
        </div>

        <h6 class="fw-bold mt-4">Avis reçus</h6>
        <div class="kpi-card">
          <div v-for="r in data.ratingsReceived" :key="r.id" class="small py-1 border-bottom">
            {{ '★'.repeat(r.score) }}<span class="text-muted">{{ '★'.repeat(5 - r.score) }}</span>
            <span class="text-muted text-xs ms-2">{{ dateOnly(r.createdAt) }}</span>
            <div v-if="r.comment">« {{ r.comment }} »</div>
          </div>
          <div v-if="!data.ratingsReceived.length" class="text-muted small">Aucun avis.</div>
        </div>
      </div>
    </div>
  </ModalShell>
</template>
