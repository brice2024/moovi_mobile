<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import ApexChart from '../components/ui/ApexChart.vue'
import StatusBadge from '../components/ui/StatusBadge.vue'
import { useDetail } from '../composables/useDetail'
import { usePlatformStore } from '../stores/platform'
import { PAYMENT_METHOD, RIDE_STATUS, dateTime, label, money, number, shortId, timeAgo } from '../utils/format'

const platform = usePlatformStore()
const detail = useDetail()
const days = ref(14)

const ov = computed(() => platform.overview)
const series = computed(() => ov.value?.series || [])
const categories = computed(() =>
  series.value.map((d) => new Date(`${d.date}T00:00:00`).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' })),
)

const periodTotals = computed(() =>
  series.value.reduce(
    (acc, d) => ({
      created: acc.created + d.ridesCreated,
      completed: acc.completed + d.ridesCompleted,
      cancelled: acc.cancelled + d.ridesCancelled,
      volume: acc.volume + d.volume,
      commission: acc.commission + d.commission,
    }),
    { created: 0, completed: 0, cancelled: 0, volume: 0, commission: 0 },
  ),
)

const completionRate = computed(() => {
  const t = periodTotals.value
  return t.created ? Math.round((t.completed / t.created) * 100) : 0
})

const ridesChart = computed(() => ({
  chart: { type: 'bar', height: 260, stacked: true },
  series: [
    { name: 'Terminées', data: series.value.map((d) => d.ridesCompleted) },
    { name: 'Annulées / expirées', data: series.value.map((d) => d.ridesCancelled) },
    {
      name: 'Autres',
      data: series.value.map((d) => Math.max(0, d.ridesCreated - d.ridesCompleted - d.ridesCancelled)),
    },
  ],
  colors: ['#22C55E', '#EF4444', '#B4F105'],
  plotOptions: { bar: { columnWidth: '55%', borderRadius: 3 } },
  dataLabels: { enabled: false },
  xaxis: { categories: categories.value },
  yaxis: { labels: { formatter: (v) => Math.round(v) } },
  grid: { borderColor: '#E9EFEF', strokeDashArray: 4 },
  legend: { position: 'top', horizontalAlign: 'left' },
}))

const moneyChart = computed(() => ({
  chart: { type: 'area', height: 260 },
  series: [
    { name: 'Encaissé (FCFA)', data: series.value.map((d) => Math.round(d.volume)) },
    { name: 'Commission Moovi (FCFA)', data: series.value.map((d) => Math.round(d.commission)) },
  ],
  colors: ['#072F1F', '#B4F105'],
  stroke: { curve: 'smooth', width: 2 },
  fill: { type: 'solid', opacity: [0.08, 0.25] },
  dataLabels: { enabled: false },
  xaxis: { categories: categories.value },
  yaxis: { labels: { formatter: (v) => number(Math.round(v)) } },
  tooltip: { y: { formatter: (v) => money(v) } },
  grid: { borderColor: '#E9EFEF', strokeDashArray: 4 },
  legend: { position: 'top', horizontalAlign: 'left' },
}))

const methodsChart = computed(() => {
  const byMethod = ov.value?.money?.byPaymentMethod || {}
  const keys = Object.keys(byMethod)
  return {
    chart: { type: 'donut', height: 240 },
    series: keys.map((k) => byMethod[k]),
    labels: keys.map((k) => label(PAYMENT_METHOD, k)),
    colors: ['#072F1F', '#B4F105', '#F97316', '#6C7E75'],
    legend: { position: 'bottom' },
    dataLabels: { enabled: true },
  }
})

const alertCards = computed(() => {
  const a = ov.value?.alerts || {}
  return [
    { n: a.pendingVerifications, to: '/documents', cls: 'alert-warning', icon: 'bi-person-plus-fill', title: 'dossier(s) chauffeur à valider', action: 'Examiner' },
    { n: a.pendingVehicles, to: '/vehicles?verificationStatus=pending', cls: 'alert-warning', icon: 'bi-car-front', title: 'véhicule(s) à valider', action: 'Voir' },
    { n: a.duplicatePayments, to: '/payments?status=duplicate', cls: 'alert-danger', icon: 'bi-exclamation-octagon', title: 'paiement(s) en double à rembourser', action: 'Traiter' },
    { n: a.stalePendingPayments, to: '/payments?status=pending', cls: 'alert-danger', icon: 'bi-hourglass-split', title: 'paiement(s) Mobile Money en attente > 10 min', action: 'Voir' },
    { n: a.stalePendingRecharges, to: '/payments?tab=wallet&status=pending', cls: 'alert-danger', icon: 'bi-wallet2', title: 'recharge(s) en attente > 10 min', action: 'Voir' },
    { n: a.unpaidCompletedRides, to: '/rides?status=unpaid', cls: 'alert-secondary', icon: 'bi-receipt', title: 'course(s) terminée(s) non réglée(s)', action: 'Voir' },
    { n: a.blockedDrivers, to: '/drivers?blocked=true', cls: 'alert-secondary', icon: 'bi-slash-circle', title: 'chauffeur(s) bloqué(s) (solde négatif)', action: 'Voir' },
  ].filter((x) => x.n > 0)
})

watch(days, (d) => platform.refresh(d))
onMounted(() => platform.refresh(days.value))
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Tableau de bord</h1>
        <p class="page-subtitle">
          Activité de la plateforme Moovi
          <span v-if="ov" class="text-muted">· actualisé {{ timeAgo(ov.generatedAt) }}</span>
        </p>
      </div>
      <select v-model.number="days" class="form-select form-select-sm" style="width: auto">
        <option :value="7">7 derniers jours</option>
        <option :value="14">14 derniers jours</option>
        <option :value="30">30 derniers jours</option>
        <option :value="90">90 derniers jours</option>
      </select>
    </div>

    <div v-if="platform.error && !ov" class="alert alert-danger">{{ platform.error }}</div>
    <div v-if="!ov" class="text-center py-5"><span class="spinner-border"></span></div>

    <template v-else>
      <div v-if="alertCards.length" class="row g-3 mb-4">
        <div v-for="a in alertCards" :key="a.title" class="col-12 col-md-6 col-xl-4">
          <div class="alert d-flex align-items-center justify-content-between p-3 mb-0 rounded-3 border-0 shadow-sm" :class="a.cls">
            <div class="d-flex align-items-center gap-3">
              <i class="bi fs-3" :class="a.icon"></i>
              <div><strong class="fs-5">{{ a.n }}</strong> {{ a.title }}</div>
            </div>
            <router-link :to="a.to" class="btn btn-sm btn-dark">{{ a.action }}</router-link>
          </div>
        </div>
      </div>

      <div class="row g-3 mb-4">
        <div class="col-6 col-xl-3">
          <div class="card alert-green-card h-100">
            <div class="position-relative z-index-2">
              <span class="alert-green-badge">En direct</span>
              <div class="alert-green-text mt-2">
                {{ ov.drivers.online }} chauffeur(s) en ligne · {{ ov.rides.active }} course(s) en cours
              </div>
            </div>
            <router-link to="/map" class="alert-green-link z-index-2">
              <span>Voir la carte en direct</span> <i class="bi bi-arrow-right"></i>
            </router-link>
          </div>
        </div>
        <div class="col-6 col-xl-3">
          <div class="kpi-card">
            <div class="kpi-label">Encaissé sur la période</div>
            <div class="kpi-value">{{ money(periodTotals.volume) }}</div>
            <div class="kpi-sub">Total historique : {{ money(ov.money.volume) }}</div>
          </div>
        </div>
        <div class="col-6 col-xl-3">
          <div class="kpi-card">
            <div class="kpi-label">Commissions Moovi (période)</div>
            <div class="kpi-value text-success">{{ money(periodTotals.commission) }}</div>
            <div class="kpi-sub">Total historique : {{ money(ov.money.commission) }}</div>
          </div>
        </div>
        <div class="col-6 col-xl-3">
          <div class="kpi-card">
            <div class="kpi-label">Courses sur la période</div>
            <div class="kpi-value">{{ number(periodTotals.created) }}</div>
            <div class="kpi-sub">{{ completionRate }} % terminées · {{ periodTotals.cancelled }} annulées/expirées</div>
          </div>
        </div>
      </div>

      <div class="row g-3 mb-4">
        <div class="col-6 col-md-3 col-xl-2">
          <div class="kpi-card"><div class="kpi-label">Utilisateurs</div><div class="kpi-value">{{ number(ov.users.total) }}</div><div class="kpi-sub">+{{ ov.users.newToday }} aujourd'hui</div></div>
        </div>
        <div class="col-6 col-md-3 col-xl-2">
          <div class="kpi-card"><div class="kpi-label">Chauffeurs validés</div><div class="kpi-value">{{ ov.drivers.approved }}</div><div class="kpi-sub">sur {{ ov.drivers.total }} inscrits</div></div>
        </div>
        <div class="col-6 col-md-3 col-xl-2">
          <div class="kpi-card"><div class="kpi-label">Dossiers en attente</div><div class="kpi-value text-warning">{{ ov.drivers.pending }}</div><div class="kpi-sub">{{ ov.drivers.rejected }} refusés</div></div>
        </div>
        <div class="col-6 col-md-3 col-xl-2">
          <div class="kpi-card"><div class="kpi-label">Portefeuilles chauffeurs</div><div class="kpi-value fs-5">{{ money(ov.drivers.walletTotal) }}</div><div class="kpi-sub">{{ ov.drivers.blocked }} bloqué(s)</div></div>
        </div>
        <div class="col-6 col-md-3 col-xl-2">
          <div class="kpi-card"><div class="kpi-label">Courses (total)</div><div class="kpi-value">{{ number(ov.rides.total) }}</div><div class="kpi-sub">{{ ov.rides.paid }} réglées</div></div>
        </div>
        <div class="col-6 col-md-3 col-xl-2">
          <div class="kpi-card"><div class="kpi-label">Comptes suspendus</div><div class="kpi-value text-danger">{{ ov.users.suspended }}</div><div class="kpi-sub">{{ ov.users.passengers }} passagers</div></div>
        </div>
      </div>

      <div class="row g-3 mb-4">
        <div class="col-xl-6">
          <div class="card p-3 h-100">
            <h6 class="fw-bold mb-0">Courses par jour</h6>
            <ApexChart :options="ridesChart" />
          </div>
        </div>
        <div class="col-xl-6">
          <div class="card p-3 h-100">
            <h6 class="fw-bold mb-0">Encaissements et commissions</h6>
            <ApexChart :options="moneyChart" />
          </div>
        </div>
      </div>

      <div class="row g-3">
        <div class="col-xl-8">
          <div class="table-card-custom h-100">
            <div class="p-3 border-bottom d-flex justify-content-between align-items-center">
              <h6 class="fw-bold mb-0">Dernières courses</h6>
              <router-link to="/rides" class="btn btn-sm btn-outline-dark">Toutes les courses</router-link>
            </div>
            <div class="table-responsive">
              <table class="table-custom align-middle">
                <thead>
                  <tr><th>Course</th><th>Passager</th><th>Chauffeur</th><th>Statut</th><th class="text-end">Prix</th></tr>
                </thead>
                <tbody>
                  <tr v-for="r in ov.recentRides" :key="r.id" class="cursor-pointer" @click="detail.open('ride', r.id)">
                    <td><div class="mono small">#{{ shortId(r.id) }}</div><div class="text-xs text-muted">{{ dateTime(r.createdAt) }}</div></td>
                    <td class="small">{{ r.clientName || '—' }}</td>
                    <td class="small">{{ r.driverName || '—' }}</td>
                    <td><StatusBadge :map="RIDE_STATUS" :value="r.status" /></td>
                    <td class="text-end fw-bold">{{ money(r.finalPrice) }}</td>
                  </tr>
                  <tr v-if="!ov.recentRides.length"><td colspan="5" class="text-center text-muted py-4">Aucune course pour l'instant.</td></tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
        <div class="col-xl-4">
          <div class="card p-3 h-100">
            <h6 class="fw-bold mb-0">Modes de règlement</h6>
            <ApexChart v-if="methodsChart.series.length" :options="methodsChart" />
            <p v-else class="text-muted small mt-3">Aucune course réglée.</p>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
