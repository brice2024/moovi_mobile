<script setup>
import { computed, ref, watch } from 'vue'
import ModalShell from '../ui/ModalShell.vue'
import StatusBadge from '../ui/StatusBadge.vue'
import AuthImage from '../ui/AuthImage.vue'
import PaginationBar from '../ui/PaginationBar.vue'
import { get, post } from '../../services/api'
import { useToastStore } from '../../stores/toast'
import { usePlatformStore } from '../../stores/platform'
import {
  DOC_LABELS,
  PAYMENT_METHOD,
  RIDE_STATUS,
  TX_STATUS,
  TX_TYPE,
  VEHICLE_TYPE,
  VERIFICATION_STATUS,
  dateOnly,
  dateTime,
  label,
  money,
  shortId,
  timeAgo,
} from '../../utils/format'

const props = defineProps({
  driverId: { type: String, required: true },
  initialTab: { type: String, default: 'file' },
})
const emit = defineEmits(['close', 'changed', 'open-ride'])

const toast = useToastStore()
const platform = usePlatformStore()

const tab = ref(props.initialTab)
const driver = ref(null)
const loading = ref(true)
const busy = ref(false)
const zoom = ref(null)

const transactions = ref([])
const txPagination = ref(null)
const rides = ref([])
const ridesPagination = ref(null)

const adjustAmount = ref('')
const adjustReason = ref('')

const documents = computed(() => Object.values(driver.value?.documents?.items || {}))
const blocked = computed(
  () => driver.value && (driver.value.isWalletBlocked || driver.value.walletBalance < 0),
)

async function load() {
  loading.value = true
  try {
    driver.value = await get(`/api/admin/drivers/${props.driverId}`)
  } catch (e) {
    toast.error(e.message)
  } finally {
    loading.value = false
  }
}

async function loadTransactions(page = 1) {
  const data = await get(`/api/admin/drivers/${props.driverId}/transactions`, { page })
  transactions.value = data.transactions
  txPagination.value = data.pagination
}

async function loadRides(page = 1) {
  const data = await get(`/api/admin/drivers/${props.driverId}/rides`, { page })
  rides.value = data.rides
  ridesPagination.value = data.pagination
}

watch(
  tab,
  (value) => {
    if (value === 'wallet') loadTransactions().catch((e) => toast.error(e.message))
    if (value === 'rides') loadRides().catch((e) => toast.error(e.message))
  },
  { immediate: true },
)
load()

async function run(action, success) {
  if (busy.value) return
  busy.value = true
  try {
    const result = await action()
    if (success) toast.success(success)
    await load()
    platform.refresh()
    emit('changed')
    return result
  } catch (e) {
    toast.error(e.message)
  } finally {
    busy.value = false
  }
}

function reviewDocument(doc, status) {
  let reason
  if (status === 'rejected') {
    reason = window.prompt(`Motif du refus « ${label(DOC_LABELS, doc.docType)} » (envoyé au chauffeur) :`)
    if (reason === null) return
  }
  run(
    () => post(`/api/admin/drivers/${props.driverId}/documents/${doc.docType}/review`, { status, reason }),
    status === 'verified' ? 'Document validé.' : 'Document refusé.',
  )
}

function verifyAll(verificationStatus) {
  const messages = {
    approved: 'Valider tout le dossier ? Le chauffeur pourra se mettre en ligne et prendre des courses.',
    rejected: 'Refuser le dossier ? Le chauffeur sera mis hors ligne.',
    pending: 'Remettre le dossier en attente ?',
  }
  if (!window.confirm(messages[verificationStatus])) return
  run(
    () => post(`/api/admin/drivers/${props.driverId}/verify`, { verificationStatus }),
    'Dossier mis à jour.',
  )
}

function reviewVehicle(vehicle, verificationStatus) {
  run(
    () => post(`/api/admin/drivers/${props.driverId}/vehicles/${vehicle.id}/review`, { verificationStatus }),
    'Véhicule mis à jour.',
  )
}

function forceOffline() {
  if (!window.confirm('Mettre ce chauffeur hors ligne maintenant ?')) return
  run(() => post(`/api/admin/drivers/${props.driverId}/offline`), 'Chauffeur mis hors ligne.')
}

function setAccount(isActive) {
  let reason = ''
  if (!isActive) {
    reason = window.prompt('Motif de la suspension du compte :')
    if (reason === null) return
  }
  run(
    () => post(`/api/admin/users/${driver.value.userId}/status`, { isActive, reason }),
    isActive ? 'Compte réactivé.' : 'Compte suspendu.',
  )
}

async function adjustWallet() {
  const amount = Number(adjustAmount.value)
  if (!amount) return toast.error('Indiquez un montant (positif pour créditer, négatif pour débiter).')
  if (!window.confirm(`${amount > 0 ? 'Créditer' : 'Débiter'} ${money(Math.abs(amount))} ?`)) return
  await run(
    () => post(`/api/admin/drivers/${props.driverId}/wallet-adjustment`, { amount, reason: adjustReason.value }),
    'Portefeuille ajusté.',
  )
  adjustAmount.value = ''
  adjustReason.value = ''
  loadTransactions()
}
</script>

<template>
  <ModalShell @close="emit('close')">
    <template #header>
      <div v-if="driver" class="d-flex align-items-center gap-3">
        <img
          v-if="driver.photoUrl"
          :src="driver.photoUrl"
          class="rounded-circle border border-2 border-success"
          style="width: 56px; height: 56px; object-fit: cover"
          alt=""
        />
        <div
          v-else
          class="rounded-circle bg-lime-accent text-dark fw-bold d-flex align-items-center justify-content-center"
          style="width: 56px; height: 56px; font-size: 1.4rem"
        >
          {{ (driver.driverName || '?').charAt(0) }}
        </div>
        <div class="min-w-0">
          <h5 class="mb-1 fw-bold text-white text-truncate">{{ driver.driverName || 'Sans nom' }}</h5>
          <div class="d-flex flex-wrap gap-2 align-items-center small">
            <StatusBadge :map="VERIFICATION_STATUS" :value="driver.verificationStatus" />
            <span class="badge" :class="driver.isAvailable ? 'bg-success' : 'bg-secondary'">
              {{ driver.isAvailable ? 'En ligne' : 'Hors ligne' }}
            </span>
            <span v-if="blocked" class="badge bg-danger">Portefeuille bloqué</span>
            <span v-if="driver.isAccountActive === false" class="badge bg-dark">Compte suspendu</span>
            <span v-if="driver.isTest" class="badge bg-info text-dark">Test</span>
            <span class="text-white-50">{{ driver.phoneNumber }}</span>
          </div>
        </div>
      </div>
      <span v-else class="text-white">Chargement…</span>
    </template>

    <template #tabs>
      <div class="moovi-tabs">
        <button :class="{ active: tab === 'file' }" @click="tab = 'file'">
          <i class="bi bi-folder-check me-1"></i> Dossier
        </button>
        <button :class="{ active: tab === 'wallet' }" @click="tab = 'wallet'">
          <i class="bi bi-wallet2 me-1"></i> Portefeuille
        </button>
        <button :class="{ active: tab === 'rides' }" @click="tab = 'rides'">
          <i class="bi bi-signpost-2 me-1"></i> Courses
        </button>
        <button :class="{ active: tab === 'actions' }" @click="tab = 'actions'">
          <i class="bi bi-shield-lock me-1"></i> Actions
        </button>
      </div>
    </template>

    <div v-if="loading && !driver" class="text-center py-5"><span class="spinner-border"></span></div>

    <template v-else-if="driver">
      <!-- DOSSIER -->
      <div v-if="tab === 'file'">
        <div class="row g-3 mb-4">
          <div class="col-6 col-lg-3">
            <div class="kpi-card">
              <div class="kpi-label">Véhicule</div>
              <div class="fw-bold">{{ driver.vehicleLabel || '—' }}</div>
              <div class="kpi-sub">
                {{ label(VEHICLE_TYPE, driver.vehicleType) }} · {{ driver.vehicle?.color }} ·
                <span class="mono">{{ driver.plate }}</span>
              </div>
            </div>
          </div>
          <div class="col-6 col-lg-3">
            <div class="kpi-card">
              <div class="kpi-label">Note</div>
              <div class="kpi-value">
                {{ driver.rating?.toFixed(1) }} <i class="bi bi-star-fill text-warning fs-6"></i>
              </div>
              <div class="kpi-sub">{{ driver.ratingCount }} avis · niveau {{ driver.level }}</div>
            </div>
          </div>
          <div class="col-6 col-lg-3">
            <div class="kpi-card">
              <div class="kpi-label">Courses réglées</div>
              <div class="kpi-value">{{ driver.ridesCount }}</div>
              <div class="kpi-sub">CA : {{ money(driver.totalRevenue) }}</div>
            </div>
          </div>
          <div class="col-6 col-lg-3">
            <div class="kpi-card">
              <div class="kpi-label">Portefeuille</div>
              <div class="kpi-value" :class="{ 'text-danger': blocked }">{{ money(driver.walletBalance) }}</div>
              <div class="kpi-sub">Inscrit le {{ dateOnly(driver.createdAt) }}</div>
            </div>
          </div>
        </div>

        <div class="d-flex flex-wrap gap-2 mb-3">
          <button class="btn btn-success btn-sm" :disabled="busy" @click="verifyAll('approved')">
            <i class="bi bi-patch-check"></i> Valider le dossier complet
          </button>
          <button class="btn btn-outline-danger btn-sm" :disabled="busy" @click="verifyAll('rejected')">
            <i class="bi bi-x-octagon"></i> Refuser le dossier
          </button>
          <button class="btn btn-outline-secondary btn-sm" :disabled="busy" @click="verifyAll('pending')">
            Remettre en attente
          </button>
          <span class="ms-auto text-muted small align-self-center">
            Documents : {{ driver.documents?.uploaded }}/{{ driver.documents?.total }} envoyés,
            {{ driver.documents?.verified }} validés
          </span>
        </div>

        <div class="row g-3">
          <div v-for="doc in documents" :key="doc.docType" class="col-12 col-sm-6 col-lg-3">
            <div class="border rounded-3 p-2 h-100 d-flex flex-column gap-2">
              <AuthImage :src="doc.url" @open="zoom = $event" />
              <div class="d-flex justify-content-between align-items-center gap-1">
                <strong class="small">{{ label(DOC_LABELS, doc.docType) }}</strong>
                <StatusBadge :map="VERIFICATION_STATUS" :value="doc.status" />
              </div>
              <div v-if="doc.rejectionReason" class="text-danger text-xs">Motif : {{ doc.rejectionReason }}</div>
              <div v-if="doc.url" class="d-flex gap-1 mt-auto">
                <button
                  class="btn btn-sm btn-success flex-fill"
                  :disabled="busy || doc.status === 'verified'"
                  @click="reviewDocument(doc, 'verified')"
                >
                  Valider
                </button>
                <button
                  class="btn btn-sm btn-outline-danger flex-fill"
                  :disabled="busy"
                  @click="reviewDocument(doc, 'rejected')"
                >
                  Refuser
                </button>
              </div>
            </div>
          </div>
        </div>

        <h6 class="fw-bold mt-4 mb-2">Véhicules</h6>
        <div class="table-responsive">
          <table class="table-custom align-middle">
            <thead>
              <tr>
                <th>Véhicule</th>
                <th>Plaque</th>
                <th>Type</th>
                <th>Statut</th>
                <th class="text-end">Décision</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="v in driver.vehicles" :key="v.id">
                <td>
                  {{ v.brand }} {{ v.model }} <span class="text-muted">· {{ v.color }}</span>
                  <span v-if="v.isActive" class="badge bg-dark ms-1">Actif</span>
                </td>
                <td class="mono">{{ v.plate }}</td>
                <td>{{ label(VEHICLE_TYPE, v.vehicleType || v.type) }}</td>
                <td><StatusBadge :map="VERIFICATION_STATUS" :value="v.verificationStatus" /></td>
                <td class="text-end">
                  <button class="btn btn-sm btn-success me-1" :disabled="busy" @click="reviewVehicle(v, 'approved')">
                    Valider
                  </button>
                  <button class="btn btn-sm btn-outline-danger" :disabled="busy" @click="reviewVehicle(v, 'rejected')">
                    Refuser
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- PORTEFEUILLE -->
      <div v-else-if="tab === 'wallet'">
        <div class="row g-3 mb-3">
          <div class="col-md-4">
            <div class="kpi-card">
              <div class="kpi-label">Solde actuel</div>
              <div class="kpi-value" :class="{ 'text-danger': blocked }">{{ money(driver.walletBalance) }}</div>
              <div class="kpi-sub">
                {{ blocked ? 'Bloqué : le chauffeur doit recharger' : 'Débité de 15 % à chaque course terminée' }}
              </div>
            </div>
          </div>
          <div class="col-md-8">
            <form class="kpi-card" @submit.prevent="adjustWallet">
              <div class="kpi-label mb-2">Ajustement manuel (tracé et notifié au chauffeur)</div>
              <div class="row g-2">
                <div class="col-sm-4">
                  <input
                    v-model="adjustAmount"
                    type="number"
                    step="1"
                    class="form-control form-control-sm"
                    placeholder="+5000 ou -2000"
                  />
                </div>
                <div class="col-sm-5">
                  <input
                    v-model="adjustReason"
                    class="form-control form-control-sm"
                    placeholder="Motif (obligatoire)"
                    required
                    minlength="3"
                  />
                </div>
                <div class="col-sm-3">
                  <button class="btn btn-dark btn-sm w-100" :disabled="busy">Appliquer</button>
                </div>
              </div>
            </form>
          </div>
        </div>
        <div class="table-responsive">
          <table class="table-custom align-middle">
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>Description</th>
                <th>Statut</th>
                <th class="text-end">Montant</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="t in transactions" :key="t.id">
                <td class="text-xs">{{ dateTime(t.createdAt) }}</td>
                <td>{{ label(TX_TYPE, t.type) }}</td>
                <td class="small">{{ t.description }}</td>
                <td><StatusBadge :map="TX_STATUS" :value="t.status" /></td>
                <td class="text-end fw-bold" :class="t.amount < 0 ? 'text-danger' : 'text-success'">
                  {{ t.amount > 0 ? '+' : '' }}{{ money(t.amount) }}
                </td>
              </tr>
              <tr v-if="!transactions.length">
                <td colspan="5" class="text-center text-muted py-4">Aucun mouvement.</td>
              </tr>
            </tbody>
          </table>
        </div>
        <PaginationBar :pagination="txPagination" @change="loadTransactions" />
      </div>

      <!-- COURSES -->
      <div v-else-if="tab === 'rides'">
        <div class="table-responsive">
          <table class="table-custom align-middle">
            <thead>
              <tr>
                <th>Course</th>
                <th>Trajet</th>
                <th>Passager</th>
                <th>Statut</th>
                <th class="text-end">Prix</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in rides" :key="r.id" class="cursor-pointer" @click="emit('open-ride', r.id)">
                <td>
                  <div class="mono small">#{{ shortId(r.id) }}</div>
                  <div class="text-xs text-muted">{{ dateTime(r.createdAt) }}</div>
                </td>
                <td class="small">{{ r.departureAddress }} → {{ r.destinationAddress }}</td>
                <td class="small">{{ r.clientName || '—' }}</td>
                <td>
                  <StatusBadge :map="RIDE_STATUS" :value="r.status" />
                  <div v-if="r.isPaid" class="text-xs text-muted">{{ label(PAYMENT_METHOD, r.paymentMethod) }}</div>
                </td>
                <td class="text-end fw-bold">{{ money(r.finalPrice) }}</td>
              </tr>
              <tr v-if="!rides.length">
                <td colspan="5" class="text-center text-muted py-4">Aucune course.</td>
              </tr>
            </tbody>
          </table>
        </div>
        <PaginationBar :pagination="ridesPagination" @change="loadRides" />
      </div>

      <!-- ACTIONS -->
      <div v-else-if="tab === 'actions'" class="row g-3">
        <div class="col-md-6">
          <div class="kpi-card">
            <h6 class="fw-bold"><i class="bi bi-broadcast me-1"></i> Disponibilité</h6>
            <p class="small text-muted mb-2">
              {{ driver.isAvailable ? 'En ligne' : 'Hors ligne' }}
              <template v-if="driver.lastLocationAt">· dernière position {{ timeAgo(driver.lastLocationAt) }}</template>
            </p>
            <button class="btn btn-outline-dark btn-sm" :disabled="busy || !driver.isAvailable" @click="forceOffline">
              Mettre hors ligne
            </button>
          </div>
        </div>
        <div class="col-md-6">
          <div class="kpi-card">
            <h6 class="fw-bold"><i class="bi bi-person-lock me-1"></i> Compte</h6>
            <p class="small text-muted mb-2">
              Suspendre bloque la connexion à l'application (chauffeur et passager) et met hors ligne.
            </p>
            <button
              v-if="driver.isAccountActive !== false"
              class="btn btn-danger btn-sm"
              :disabled="busy"
              @click="setAccount(false)"
            >
              Suspendre le compte
            </button>
            <button v-else class="btn btn-success btn-sm" :disabled="busy" @click="setAccount(true)">
              Réactiver le compte
            </button>
          </div>
        </div>
        <div class="col-12 text-muted text-xs">
          Identifiants : chauffeur <span class="mono">{{ driver.id }}</span> · utilisateur
          <span class="mono">{{ driver.userId }}</span>
        </div>
      </div>
    </template>
  </ModalShell>

  <Teleport to="body">
    <div v-if="zoom" class="moovi-modal-backdrop align-items-center" style="z-index: 1070" @click="zoom = null">
      <img :src="zoom" class="doc-zoom" alt="Document" />
    </div>
  </Teleport>
</template>
