<script setup>
import StatusBadge from '../components/ui/StatusBadge.vue'
import PaginationBar from '../components/ui/PaginationBar.vue'
import { useDetail } from '../composables/useDetail'
import { useList } from '../composables/useList'
import { PAYMENT_METHOD, RIDE_STATUS, VEHICLE_TYPE, dateTime, label, money, shortId } from '../utils/format'

const detail = useDetail()
const { filters, items, pagination, loading, error, goTo } = useList('/api/admin/rides', 'rides', {
  q: '',
  status: '',
  paymentMethod: '',
  from: '',
  to: '',
})
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Courses</h1>
        <p class="page-subtitle">Toutes les courses de la plateforme, du suivi en direct aux litiges.</p>
      </div>
    </div>

    <div class="table-card-custom">
      <div class="p-3 border-bottom d-flex flex-wrap gap-2 align-items-center">
        <div class="table-search-box flex-grow-1" style="max-width: 340px">
          <i class="bi bi-search table-search-icon"></i>
          <input v-model="filters.q" class="table-search-input" placeholder="N°, adresse, passager, chauffeur, plaque…" />
        </div>
        <select v-model="filters.status" class="form-select form-select-sm" style="width: auto">
          <option value="">Tous les statuts</option>
          <option value="active">En cours (toutes étapes)</option>
          <option value="searching">Recherche de chauffeur</option>
          <option value="accepted">Acceptées</option>
          <option value="in_progress">En course</option>
          <option value="completed">Terminées</option>
          <option value="unpaid">Terminées non réglées</option>
          <option value="cancelled">Annulées</option>
          <option value="expired">Expirées</option>
        </select>
        <select v-model="filters.paymentMethod" class="form-select form-select-sm" style="width: auto">
          <option value="">Tout règlement</option>
          <option value="cash">Espèces</option>
          <option value="mobile_money">Mobile Money</option>
          <option value="moovi_promo">Offert (promo)</option>
        </select>
        <input v-model="filters.from" type="date" class="form-control form-control-sm" style="width: auto" title="Du" />
        <input v-model="filters.to" type="date" class="form-control form-control-sm" style="width: auto" title="Au" />
        <span v-if="loading" class="spinner-border spinner-border-sm ms-auto"></span>
      </div>
      <div v-if="error" class="alert alert-danger m-3">{{ error }}</div>
      <div class="table-responsive">
        <table class="table-custom align-middle">
          <thead>
            <tr>
              <th>Course</th>
              <th>Trajet</th>
              <th>Passager</th>
              <th>Chauffeur</th>
              <th>Statut</th>
              <th class="text-end">Prix</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in items" :key="r.id" class="cursor-pointer" @click="detail.open('ride', r.id)">
              <td>
                <div class="mono small">#{{ shortId(r.id) }}</div>
                <div class="text-xs text-muted">{{ dateTime(r.createdAt) }}</div>
                <div class="text-xs text-muted">{{ label(VEHICLE_TYPE, r.rideType) }}</div>
              </td>
              <td class="small" style="max-width: 280px">
                <div class="text-truncate"><i class="bi bi-geo-alt text-success"></i> {{ r.departureAddress }}</div>
                <div class="text-truncate"><i class="bi bi-flag text-danger"></i> {{ r.destinationAddress }}</div>
              </td>
              <td class="small">
                {{ r.clientName || '—' }}
                <div class="text-xs text-muted">{{ r.clientPhone }}</div>
              </td>
              <td class="small">
                {{ r.driverName || '—' }}
                <div class="text-xs text-muted mono">{{ r.driverPlate }}</div>
              </td>
              <td>
                <StatusBadge :map="RIDE_STATUS" :value="r.status" />
                <div class="text-xs" :class="r.isPaid ? 'text-success' : 'text-muted'">
                  {{ r.isPaid ? label(PAYMENT_METHOD, r.paymentMethod) : r.status === 'completed' ? 'non réglée' : '' }}
                </div>
              </td>
              <td class="text-end">
                <div class="fw-bold">{{ money(r.finalPrice) }}</div>
                <div v-if="r.commissionDeducted" class="text-xs text-success">+{{ money(r.platformCommission) }}</div>
              </td>
            </tr>
            <tr v-if="!items.length && !loading">
              <td colspan="6" class="text-center text-muted py-5">Aucune course ne correspond.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationBar :pagination="pagination" @change="goTo" />
    </div>
  </div>
</template>
