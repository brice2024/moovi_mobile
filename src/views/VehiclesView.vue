<script setup>
import { ref } from 'vue'
import StatusBadge from '../components/ui/StatusBadge.vue'
import PaginationBar from '../components/ui/PaginationBar.vue'
import { useDetail } from '../composables/useDetail'
import { useList } from '../composables/useList'
import { post } from '../services/api'
import { usePlatformStore } from '../stores/platform'
import { useToastStore } from '../stores/toast'
import { VEHICLE_TYPE, VERIFICATION_STATUS, dateOnly, label } from '../utils/format'

const detail = useDetail()
const toast = useToastStore()
const platform = usePlatformStore()
const busy = ref(null)
const { filters, items, pagination, loading, error, load, goTo } = useList('/api/admin/vehicles', 'vehicles', {
  q: '',
  verificationStatus: '',
  vehicleType: '',
})

async function review(vehicle, verificationStatus) {
  busy.value = vehicle.id
  try {
    await post(`/api/admin/drivers/${vehicle.driverId}/vehicles/${vehicle.id}/review`, { verificationStatus })
    toast.success(verificationStatus === 'approved' ? 'Véhicule validé.' : 'Véhicule refusé.')
    await load()
    platform.refresh()
  } catch (e) {
    toast.error(e.message)
  } finally {
    busy.value = null
  }
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Flotte</h1>
        <p class="page-subtitle">
          Véhicules déclarés par les chauffeurs. Le véhicule actif d'un chauffeur doit être validé pour rouler.
        </p>
      </div>
    </div>

    <div class="table-card-custom">
      <div class="p-3 border-bottom d-flex flex-wrap gap-2 align-items-center">
        <div class="table-search-box flex-grow-1" style="max-width: 320px">
          <i class="bi bi-search table-search-icon"></i>
          <input v-model="filters.q" class="table-search-input" placeholder="Plaque, marque, modèle…" />
        </div>
        <select v-model="filters.verificationStatus" class="form-select form-select-sm" style="width: auto">
          <option value="">Tous les statuts</option>
          <option value="pending">À valider</option>
          <option value="approved">Validés</option>
          <option value="rejected">Refusés</option>
        </select>
        <select v-model="filters.vehicleType" class="form-select form-select-sm" style="width: auto">
          <option value="">Tous types</option>
          <option value="voiture">Voiture</option>
          <option value="moto">Moto</option>
          <option value="confort">Confort</option>
        </select>
        <span v-if="loading" class="spinner-border spinner-border-sm ms-auto"></span>
      </div>
      <div v-if="error" class="alert alert-danger m-3">{{ error }}</div>
      <div class="table-responsive">
        <table class="table-custom align-middle">
          <thead>
            <tr>
              <th>Véhicule</th>
              <th>Plaque</th>
              <th>Chauffeur</th>
              <th>Statut</th>
              <th class="text-end">Décision</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="v in items" :key="v.id">
              <td>
                <div class="fw-semibold">{{ v.brand }} {{ v.model }}</div>
                <div class="text-xs text-muted">
                  {{ label(VEHICLE_TYPE, v.vehicleType) }} · {{ v.color }} · ajouté le {{ dateOnly(v.createdAt) }}
                  <span v-if="v.isActive" class="badge bg-dark ms-1">Actif</span>
                </div>
              </td>
              <td class="mono">{{ v.plate }}</td>
              <td>
                <a href="#" class="small" @click.prevent="detail.open('driver', v.driverId)">{{ v.driverName || 'Chauffeur' }}</a>
                <div class="text-xs text-muted">{{ v.driverPhone }}</div>
              </td>
              <td><StatusBadge :map="VERIFICATION_STATUS" :value="v.verificationStatus" /></td>
              <td class="text-end text-nowrap">
                <button
                  class="btn btn-sm btn-success me-1"
                  :disabled="busy === v.id || v.verificationStatus === 'approved'"
                  @click="review(v, 'approved')"
                >
                  Valider
                </button>
                <button
                  class="btn btn-sm btn-outline-danger"
                  :disabled="busy === v.id || v.verificationStatus === 'rejected'"
                  @click="review(v, 'rejected')"
                >
                  Refuser
                </button>
              </td>
            </tr>
            <tr v-if="!items.length && !loading">
              <td colspan="5" class="text-center text-muted py-5">Aucun véhicule.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationBar :pagination="pagination" @change="goTo" />
    </div>
  </div>
</template>
