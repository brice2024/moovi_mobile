<script setup>
import StatusBadge from '../components/ui/StatusBadge.vue'
import PaginationBar from '../components/ui/PaginationBar.vue'
import { useDetail } from '../composables/useDetail'
import { useList } from '../composables/useList'
import { VEHICLE_TYPE, VERIFICATION_STATUS, dateOnly, label, money, timeAgo } from '../utils/format'

const detail = useDetail()
const { filters, items, pagination, loading, error, goTo } = useList('/api/admin/drivers', 'drivers', {
  q: '',
  verificationStatus: '',
  online: '',
  vehicleType: '',
  blocked: '',
})
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Chauffeurs</h1>
        <p class="page-subtitle">Dossiers, disponibilité, portefeuilles et sanctions.</p>
      </div>
    </div>

    <div class="table-card-custom">
      <div class="p-3 border-bottom d-flex flex-wrap gap-2 align-items-center">
        <div class="table-search-box flex-grow-1" style="max-width: 360px">
          <i class="bi bi-search table-search-icon"></i>
          <input v-model="filters.q" class="table-search-input" placeholder="Nom, téléphone, plaque…" />
        </div>
        <select v-model="filters.verificationStatus" class="form-select form-select-sm" style="width: auto">
          <option value="">Tous les dossiers</option>
          <option value="pending">En attente</option>
          <option value="approved">Validés</option>
          <option value="rejected">Refusés</option>
        </select>
        <select v-model="filters.online" class="form-select form-select-sm" style="width: auto">
          <option value="">En ligne et hors ligne</option>
          <option value="true">En ligne</option>
          <option value="false">Hors ligne</option>
        </select>
        <select v-model="filters.vehicleType" class="form-select form-select-sm" style="width: auto">
          <option value="">Tous véhicules</option>
          <option value="voiture">Voiture</option>
          <option value="moto">Moto</option>
          <option value="confort">Confort</option>
        </select>
        <button
          class="btn btn-sm"
          :class="filters.blocked === 'true' ? 'btn-danger' : 'btn-outline-danger'"
          @click="filters.blocked = filters.blocked === 'true' ? '' : 'true'"
        >
          <i class="bi bi-slash-circle"></i> Bloqués
        </button>
        <span v-if="loading" class="spinner-border spinner-border-sm ms-auto"></span>
      </div>

      <div v-if="error" class="alert alert-danger m-3">{{ error }}</div>

      <div class="table-responsive">
        <table class="table-custom align-middle">
          <thead>
            <tr>
              <th>Chauffeur</th>
              <th>Véhicule</th>
              <th>Dossier</th>
              <th>Disponibilité</th>
              <th>Note · courses</th>
              <th class="text-end">Portefeuille</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="d in items" :key="d.id" class="cursor-pointer" @click="detail.open('driver', d.id)">
              <td>
                <div class="table-user-cell">
                  <img v-if="d.photoUrl" :src="d.photoUrl" class="table-user-avatar" alt="" />
                  <span v-else class="table-user-avatar d-inline-flex align-items-center justify-content-center bg-lime-accent fw-bold">
                    {{ (d.driverName || '?').charAt(0) }}
                  </span>
                  <div>
                    <div class="table-user-name">
                      {{ d.driverName || 'Sans nom' }}
                      <span v-if="d.isAccountActive === false" class="badge bg-dark ms-1">Suspendu</span>
                      <span v-if="d.isTest" class="badge bg-info text-dark ms-1">Test</span>
                    </div>
                    <div class="table-user-sub">{{ d.phoneNumber }} · depuis {{ dateOnly(d.createdAt) }}</div>
                  </div>
                </div>
              </td>
              <td>
                <div class="small fw-semibold">{{ d.vehicleLabel || '—' }}</div>
                <div class="text-xs text-muted">{{ label(VEHICLE_TYPE, d.vehicleType) }} · <span class="mono">{{ d.plate }}</span></div>
              </td>
              <td>
                <StatusBadge :map="VERIFICATION_STATUS" :value="d.verificationStatus" />
                <div class="text-xs text-muted">{{ d.documents?.verified }}/{{ d.documents?.total }} docs validés</div>
              </td>
              <td>
                <span class="badge" :class="d.isAvailable ? 'bg-success' : 'bg-secondary'">
                  {{ d.isAvailable ? 'En ligne' : 'Hors ligne' }}
                </span>
                <div v-if="d.lastLocationAt" class="text-xs text-muted">vu {{ timeAgo(d.lastLocationAt) }}</div>
              </td>
              <td class="small">
                {{ d.rating?.toFixed(1) }} <i class="bi bi-star-fill text-warning"></i> · {{ d.ridesCount }} courses
                <div class="text-xs text-muted">{{ d.level }}</div>
              </td>
              <td class="text-end">
                <span class="fw-bold" :class="{ 'text-danger': d.isWalletBlocked || d.walletBalance < 0 }">
                  {{ money(d.walletBalance) }}
                </span>
                <div v-if="d.isWalletBlocked" class="text-xs text-danger">bloqué</div>
              </td>
            </tr>
            <tr v-if="!items.length && !loading">
              <td colspan="6" class="text-center text-muted py-5">Aucun chauffeur ne correspond.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationBar :pagination="pagination" @change="goTo" />
    </div>
  </div>
</template>
