<script setup>
import { computed, ref } from 'vue'
import ModalShell from '../ui/ModalShell.vue'
import StatusBadge from '../ui/StatusBadge.vue'
import { get, post } from '../../services/api'
import { useToastStore } from '../../stores/toast'
import { usePlatformStore } from '../../stores/platform'
import {
  PAYMENT_METHOD,
  PAYMENT_STATUS,
  RIDE_STATUS,
  TX_TYPE,
  VEHICLE_TYPE,
  dateTime,
  label,
  money,
  shortId,
} from '../../utils/format'

const OFFER_STATUS = {
  pending: ['En attente', 'pending'],
  accepted: ['Retenue', 'success'],
  rejected: ['Non retenue', 'neutral'],
  cancelled: ['Retirée', 'neutral'],
}

const props = defineProps({ rideId: { type: String, required: true } })
const emit = defineEmits(['close', 'changed', 'open-driver', 'open-user'])

const toast = useToastStore()
const platform = usePlatformStore()
const data = ref(null)
const busy = ref(false)

const ride = computed(() => data.value?.ride)
const cancellable = computed(() =>
  ['searching', 'accepted', 'driver_arrived'].includes(ride.value?.status),
)

const timeline = computed(() => {
  const r = ride.value
  if (!r) return []
  return [
    ['Demande créée', r.createdAt],
    ['Offre acceptée', r.acceptedAt],
    ['Chauffeur arrivé', r.driverArrivedAt],
    ['Course démarrée', r.startedAt],
    ['Course terminée', r.completedAt],
    ['Règlement', r.paidAt],
    ['Annulation', r.cancelledAt],
  ].filter(([title, at]) => at || title !== 'Annulation')
})

async function load() {
  try {
    data.value = await get(`/api/admin/rides/${props.rideId}`)
  } catch (e) {
    toast.error(e.message)
  }
}
load()

async function cancelRide() {
  const reason = window.prompt("Motif de l'annulation (communiqué aux participants) :", 'Annulée par Moovi')
  if (reason === null) return
  busy.value = true
  try {
    await post(`/api/rides/${props.rideId}/cancel`, { reason })
    toast.success('Course annulée.')
    await load()
    platform.refresh()
    emit('changed')
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
      <div v-if="ride" class="d-flex flex-wrap align-items-center gap-2">
        <h5 class="mb-0 fw-bold text-white">Course #{{ shortId(ride.id) }}</h5>
        <StatusBadge :map="RIDE_STATUS" :value="ride.status" />
        <span v-if="ride.isPaid" class="badge bg-success">Payée · {{ label(PAYMENT_METHOD, ride.paymentMethod) }}</span>
        <span v-else-if="ride.status === 'completed'" class="badge bg-warning text-dark">Non réglée</span>
        <span class="text-white-50 small">{{ label(VEHICLE_TYPE, ride.rideType) }}</span>
      </div>
      <span v-else class="text-white">Chargement…</span>
    </template>

    <div v-if="!data" class="text-center py-5"><span class="spinner-border"></span></div>

    <div v-else class="row g-4">
      <div class="col-lg-7">
        <div class="kpi-card mb-3">
          <div class="d-flex gap-3">
            <div class="text-success"><i class="bi bi-geo-alt-fill"></i></div>
            <div>
              <div class="kpi-label">Départ</div>
              <div class="fw-semibold">{{ ride.departureAddress }}</div>
            </div>
          </div>
          <div class="d-flex gap-3 mt-2">
            <div class="text-danger"><i class="bi bi-flag-fill"></i></div>
            <div>
              <div class="kpi-label">Destination</div>
              <div class="fw-semibold">{{ ride.destinationAddress }}</div>
            </div>
          </div>
          <div class="text-muted text-xs mt-2">{{ ride.distance }} · {{ ride.duration }}</div>
        </div>

        <div class="row g-3 mb-3">
          <div class="col-4">
            <div class="kpi-card">
              <div class="kpi-label">Prix convenu</div>
              <div class="kpi-value fs-5">{{ money(ride.finalPrice) }}</div>
              <div class="kpi-sub">Proposé : {{ money(ride.price) }}</div>
            </div>
          </div>
          <div class="col-4">
            <div class="kpi-card">
              <div class="kpi-label">Payé par le passager</div>
              <div class="kpi-value fs-5">{{ ride.isPaid ? money(ride.paidAmount) : '—' }}</div>
              <div class="kpi-sub">Remise : {{ money(ride.discountAmount) }}</div>
            </div>
          </div>
          <div class="col-4">
            <div class="kpi-card">
              <div class="kpi-label">Commission Moovi</div>
              <div class="kpi-value fs-5">{{ ride.commissionDeducted ? money(ride.platformCommission) : '—' }}</div>
              <div class="kpi-sub">{{ ride.commissionRate ? `${Math.round(ride.commissionRate * 100)} %` : 'non prélevée' }}</div>
            </div>
          </div>
        </div>

        <div class="row g-3">
          <div class="col-sm-6">
            <div class="kpi-card cursor-pointer" @click="data.client && emit('open-user', data.client.id)">
              <div class="kpi-label">Passager</div>
              <div class="fw-bold">{{ data.client?.fullname || '—' }}</div>
              <div class="kpi-sub">{{ data.client?.phoneNumber }}</div>
            </div>
          </div>
          <div class="col-sm-6">
            <div class="kpi-card cursor-pointer" @click="data.driver && emit('open-driver', data.driver.id)">
              <div class="kpi-label">Chauffeur</div>
              <div class="fw-bold">{{ ride.driverName || 'Pas encore attribué' }}</div>
              <div class="kpi-sub">{{ ride.driverCar }} <span class="mono">{{ ride.driverPlate }}</span></div>
              <div class="kpi-sub">{{ ride.driverPhone }}</div>
            </div>
          </div>
        </div>

        <h6 class="fw-bold mt-4">Offres reçues ({{ ride.offers?.length || 0 }})</h6>
        <table class="table-custom align-middle">
          <tbody>
            <tr v-for="o in ride.offers" :key="o.id">
              <td>{{ o.driverName }} <span class="text-muted text-xs">{{ o.car }}</span></td>
              <td>{{ o.arrivalMinutes }} min</td>
              <td class="fw-bold">{{ money(o.price) }}</td>
              <td><StatusBadge :map="OFFER_STATUS" :value="o.status" /></td>
            </tr>
            <tr v-if="!ride.offers?.length"><td class="text-muted">Aucune offre.</td></tr>
          </tbody>
        </table>

        <h6 class="fw-bold mt-4">Discussion ({{ data.messages.length }})</h6>
        <div class="kpi-card d-flex flex-column gap-2" style="max-height: 260px; overflow-y: auto">
          <div v-for="m in data.messages" :key="m.id" class="chat-bubble" :class="m.senderRole">
            <div class="text-xs fw-bold">{{ m.senderName }} · {{ dateTime(m.createdAt) }}</div>
            {{ m.content }}
          </div>
          <div v-if="!data.messages.length" class="text-muted small">Aucun message.</div>
        </div>
      </div>

      <div class="col-lg-5">
        <h6 class="fw-bold">Chronologie</h6>
        <div class="kpi-card mb-3">
          <div v-for="[title, at] in timeline" :key="title" class="timeline-step">
            <span class="timeline-dot" :class="{ done: at }"></span>
            <div>
              <div class="small fw-semibold" :class="{ 'text-muted': !at }">{{ title }}</div>
              <div class="text-xs text-muted">{{ at ? dateTime(at) : '—' }}</div>
            </div>
          </div>
          <div v-if="ride.cancelReason" class="text-danger text-xs">
            Annulée par {{ ride.cancelledBy }} : {{ ride.cancelReason }}
          </div>
        </div>

        <h6 class="fw-bold">Paiements Mobile Money</h6>
        <div class="kpi-card mb-3">
          <div v-for="p in data.payments" :key="p.depositId" class="d-flex justify-content-between align-items-center py-1 border-bottom">
            <div>
              <div class="small fw-semibold">{{ money(p.amount) }} · {{ p.operatorCode }}</div>
              <div class="text-xs text-muted">{{ dateTime(p.createdAt) }}</div>
              <div v-if="p.failureReason" class="text-xs text-danger">{{ p.failureReason }}</div>
            </div>
            <StatusBadge :map="PAYMENT_STATUS" :value="p.status" />
          </div>
          <div v-if="!data.payments.length" class="text-muted small">Aucune tentative.</div>
        </div>

        <h6 class="fw-bold">Mouvements du portefeuille chauffeur</h6>
        <div class="kpi-card mb-3">
          <div v-for="t in data.walletTransactions" :key="t.id" class="d-flex justify-content-between small py-1">
            <span>{{ label(TX_TYPE, t.type) }}</span>
            <strong :class="t.amount < 0 ? 'text-danger' : 'text-success'">{{ t.amount > 0 ? '+' : '' }}{{ money(t.amount) }}</strong>
          </div>
          <div v-if="!data.walletTransactions.length" class="text-muted small">Aucun mouvement.</div>
        </div>

        <h6 class="fw-bold">Évaluations</h6>
        <div class="kpi-card mb-3">
          <div v-for="r in data.ratings" :key="r.id" class="small py-1">
            <strong>{{ r.targetRole === 'driver' ? 'Chauffeur' : 'Passager' }}</strong> :
            {{ '★'.repeat(r.score) }}<span class="text-muted">{{ '★'.repeat(5 - r.score) }}</span>
            <div v-if="r.comment" class="text-muted">« {{ r.comment }} »</div>
          </div>
          <div v-if="!data.ratings.length" class="text-muted small">Aucune évaluation.</div>
        </div>

        <button v-if="cancellable" class="btn btn-outline-danger w-100" :disabled="busy" @click="cancelRide">
          <i class="bi bi-x-circle"></i> Annuler la course
        </button>
        <div class="text-muted text-xs mt-2 mono">{{ ride.id }}</div>
      </div>
    </div>
  </ModalShell>
</template>
