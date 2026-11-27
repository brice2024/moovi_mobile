<script setup>
import StatusBadge from '../components/ui/StatusBadge.vue'
import PaginationBar from '../components/ui/PaginationBar.vue'
import { useDetail } from '../composables/useDetail'
import { useList } from '../composables/useList'
import { DOC_LABELS, VEHICLE_TYPE, VERIFICATION_STATUS, dateTime, label } from '../utils/format'

const detail = useDetail()
const { filters, items, pagination, loading, error, goTo } = useList('/api/admin/drivers', 'drivers', {
  verificationStatus: 'pending',
})

const docs = (d) => Object.values(d.documents?.items || {})
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Validation des dossiers</h1>
        <p class="page-subtitle">
          Un chauffeur ne peut se mettre en ligne qu'une fois son dossier validé. Ouvrez un dossier pour voir
          les pièces et décider.
        </p>
      </div>
      <select v-model="filters.verificationStatus" class="form-select form-select-sm" style="width: auto">
        <option value="pending">En attente</option>
        <option value="rejected">Refusés</option>
        <option value="approved">Validés</option>
      </select>
    </div>

    <div v-if="error" class="alert alert-danger">{{ error }}</div>
    <div v-if="loading && !items.length" class="text-center py-5"><span class="spinner-border"></span></div>

    <div class="row g-3">
      <div v-for="d in items" :key="d.id" class="col-12 col-lg-6 col-xxl-4">
        <div class="card p-3 h-100">
          <div class="d-flex justify-content-between align-items-start gap-2">
            <div>
              <h6 class="fw-bold mb-0">{{ d.driverName || 'Sans nom' }}</h6>
              <div class="text-xs text-muted">{{ d.phoneNumber }} · mis à jour {{ dateTime(d.updatedAt) }}</div>
              <div class="small mt-1">
                {{ label(VEHICLE_TYPE, d.vehicleType) }} · {{ d.vehicleLabel }} ·
                <span class="mono">{{ d.plate }}</span>
              </div>
            </div>
            <StatusBadge :map="VERIFICATION_STATUS" :value="d.verificationStatus" />
          </div>

          <div class="progress my-3" style="height: 6px">
            <div class="progress-bar bg-success" :style="{ width: `${d.documents?.progressPercent || 0}%` }"></div>
          </div>
          <div class="d-flex flex-wrap gap-1 mb-3">
            <span
              v-for="doc in docs(d)"
              :key="doc.docType"
              class="badge-table"
              :class="doc.status === 'verified' ? 'success' : doc.status === 'rejected' ? 'failed' : doc.status === 'missing' ? 'neutral' : 'pending'"
            >
              {{ label(DOC_LABELS, doc.docType) }}
            </span>
          </div>
          <div class="mt-auto d-flex justify-content-between align-items-center">
            <span class="text-xs text-muted">{{ d.documents?.uploaded }}/{{ d.documents?.total }} pièces envoyées</span>
            <button class="btn btn-dark btn-sm" @click="detail.open('driver', d.id)">
              <i class="bi bi-folder2-open"></i> Examiner le dossier
            </button>
          </div>
        </div>
      </div>
      <div v-if="!items.length && !loading" class="col-12">
        <div class="card p-5 text-center text-muted">
          <i class="bi bi-check2-circle fs-1 text-success"></i>
          <p class="mt-2 mb-0">Aucun dossier dans cette catégorie.</p>
        </div>
      </div>
    </div>
    <div class="table-card-custom mt-3"><PaginationBar :pagination="pagination" @change="goTo" /></div>
  </div>
</template>
