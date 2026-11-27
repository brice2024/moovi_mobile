<script setup>
import { ref } from 'vue'
import { useRoute } from 'vue-router'
import StatusBadge from '../components/ui/StatusBadge.vue'
import PaginationBar from '../components/ui/PaginationBar.vue'
import { useDetail } from '../composables/useDetail'
import { useList } from '../composables/useList'
import { post } from '../services/api'
import { usePlatformStore } from '../stores/platform'
import { useToastStore } from '../stores/toast'
import { PAYMENT_METHOD, PAYMENT_STATUS, TX_STATUS, TX_TYPE, dateTime, label, money, shortId } from '../utils/format'

const route = useRoute()
const detail = useDetail()
const toast = useToastStore()
const platform = usePlatformStore()
const tab = ref(route.query.tab === 'wallet' ? 'wallet' : 'rides')

// Deux listes sur la même page : filtres gardés localement (pas dans l'URL).
const payments = useList(
  '/api/admin/payments',
  'payments',
  { status: tab.value === 'rides' ? route.query.status || '' : '' },
  { urlSync: false },
)
const wallet = useList(
  '/api/admin/wallet-transactions',
  'transactions',
  { type: '', status: tab.value === 'wallet' ? route.query.status || '' : '' },
  { urlSync: false },
)


async function markRefunded(p) {
  const note = window.prompt(
    `Confirmez le remboursement de ${money(p.amount)} au ${p.msisdn || 'passager'} (référence, moyen utilisé…) :`,
  )
  if (note === null) return
  try {
    await post(`/api/admin/payments/${p.depositId}/refunded`, { note })
    toast.success('Paiement marqué remboursé. Le passager est notifié.')
    payments.load()
    platform.refresh()
  } catch (e) {
    toast.error(e.message)
  }
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Paiements</h1>
        <p class="page-subtitle">
          Paiements Mobile Money des courses (PawaPay) et mouvements des portefeuilles chauffeurs. Les dépôts en
          attente sont revérifiés automatiquement auprès de PawaPay toutes les minutes.
        </p>
      </div>
    </div>

    <div class="table-card-custom">
      <div class="moovi-tabs">
        <button :class="{ active: tab === 'rides' }" @click="tab = 'rides'">
          <i class="bi bi-phone me-1"></i> Paiements de courses
        </button>
        <button :class="{ active: tab === 'wallet' }" @click="tab = 'wallet'">
          <i class="bi bi-wallet2 me-1"></i> Portefeuilles chauffeurs
        </button>
      </div>

      <!-- Paiements Mobile Money des courses -->
      <template v-if="tab === 'rides'">
        <div class="p-3 border-bottom d-flex flex-wrap gap-2 align-items-center">
          <select v-model="payments.filters.status" class="form-select form-select-sm" style="width: auto">
            <option value="">Tous les statuts</option>
            <option value="pending">En attente</option>
            <option value="completed">Payés</option>
            <option value="failed">Échoués</option>
            <option value="duplicate">En double (à rembourser)</option>
            <option value="refunded">Remboursés</option>
          </select>
          <span v-if="payments.loading.value" class="spinner-border spinner-border-sm ms-auto"></span>
        </div>
        <div v-if="payments.error.value" class="alert alert-danger m-3">{{ payments.error.value }}</div>
        <div class="table-responsive">
          <table class="table-custom align-middle">
            <thead>
              <tr>
                <th>Date</th>
                <th>Passager</th>
                <th>Opérateur · numéro</th>
                <th>Course</th>
                <th>Statut</th>
                <th class="text-end">Montant</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in payments.items.value" :key="p.depositId">
                <td class="text-xs">{{ dateTime(p.createdAt) }}</td>
                <td class="small">
                  <a v-if="p.payer" href="#" @click.prevent="detail.open('user', p.payer.id)">{{ p.payer.fullname || 'Passager' }}</a>
                  <div class="text-xs text-muted">{{ p.payer?.phoneNumber }}</div>
                </td>
                <td class="small">{{ p.operatorCode }}<div class="text-xs text-muted mono">{{ p.msisdn }}</div></td>
                <td class="small">
                  <a v-if="p.ride" href="#" class="mono" @click.prevent="detail.open('ride', p.ride.id)">#{{ shortId(p.ride.id) }}</a>
                  <div v-if="p.ride" class="text-xs text-muted">{{ p.ride.isPaid ? `réglée · ${label(PAYMENT_METHOD, p.ride.paymentMethod)}` : 'non réglée' }}</div>
                </td>
                <td>
                  <StatusBadge :map="PAYMENT_STATUS" :value="p.status" />
                  <div v-if="p.failureReason" class="text-xs text-danger" style="max-width: 220px">{{ p.failureReason }}</div>
                </td>
                <td class="text-end fw-bold">{{ money(p.amount) }}</td>
                <td class="text-end">
                  <button v-if="p.status === 'duplicate'" class="btn btn-sm btn-outline-danger" @click="markRefunded(p)">
                    Marquer remboursé
                  </button>
                </td>
              </tr>
              <tr v-if="!payments.items.value.length && !payments.loading.value">
                <td colspan="7" class="text-center text-muted py-5">Aucun paiement.</td>
              </tr>
            </tbody>
          </table>
        </div>
        <PaginationBar :pagination="payments.pagination.value" @change="payments.goTo" />
      </template>

      <!-- Portefeuilles -->
      <template v-else>
        <div class="p-3 border-bottom d-flex flex-wrap gap-2 align-items-center">
          <select v-model="wallet.filters.type" class="form-select form-select-sm" style="width: auto">
            <option value="">Tous les mouvements</option>
            <option value="deposit">Recharges</option>
            <option value="commission">Commissions</option>
            <option value="ride_payout">Reversements de courses</option>
            <option value="promo_subsidy">Subventions promo</option>
            <option value="adjustment">Ajustements</option>
          </select>
          <select v-model="wallet.filters.status" class="form-select form-select-sm" style="width: auto">
            <option value="">Tous les statuts</option>
            <option value="pending">En attente</option>
            <option value="completed">Effectués</option>
            <option value="failed">Échoués</option>
          </select>
          <span v-if="wallet.loading.value" class="spinner-border spinner-border-sm ms-auto"></span>
        </div>
        <div v-if="wallet.error.value" class="alert alert-danger m-3">{{ wallet.error.value }}</div>
        <div class="table-responsive">
          <table class="table-custom align-middle">
            <thead>
              <tr>
                <th>Date</th>
                <th>Chauffeur</th>
                <th>Type</th>
                <th>Description</th>
                <th>Statut</th>
                <th class="text-end">Montant</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="t in wallet.items.value" :key="t.id">
                <td class="text-xs">{{ dateTime(t.createdAt) }}</td>
                <td class="small">
                  <a href="#" @click.prevent="detail.open('driver', t.driverId, { tab: 'wallet' })">{{ t.driverName || 'Chauffeur' }}</a>
                  <div class="text-xs text-muted">{{ t.driverPhone }}</div>
                </td>
                <td class="small">{{ label(TX_TYPE, t.type) }}</td>
                <td class="small" style="max-width: 300px">
                  {{ t.description }}
                  <div v-if="t.operatorName" class="text-xs text-muted">{{ t.operatorName }} · {{ t.phoneNumber }}</div>
                </td>
                <td><StatusBadge :map="TX_STATUS" :value="t.status" /></td>
                <td class="text-end fw-bold" :class="t.amount < 0 ? 'text-danger' : 'text-success'">
                  {{ t.amount > 0 ? '+' : '' }}{{ money(t.amount) }}
                </td>
              </tr>
              <tr v-if="!wallet.items.value.length && !wallet.loading.value">
                <td colspan="6" class="text-center text-muted py-5">Aucun mouvement.</td>
              </tr>
            </tbody>
          </table>
        </div>
        <PaginationBar :pagination="wallet.pagination.value" @change="wallet.goTo" />
      </template>
    </div>
  </div>
</template>
