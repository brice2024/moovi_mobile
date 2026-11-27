<script setup>
import PaginationBar from '../components/ui/PaginationBar.vue'
import { useDetail } from '../composables/useDetail'
import { useList } from '../composables/useList'
import { dateOnly } from '../utils/format'

const detail = useDetail()
const { filters, items, pagination, loading, error, goTo } = useList('/api/admin/users', 'users', {
  q: '',
  role: '',
  status: '',
})
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Utilisateurs</h1>
        <p class="page-subtitle">Passagers, chauffeurs et administrateurs. Suspension et messages ciblés.</p>
      </div>
    </div>

    <div class="table-card-custom">
      <div class="p-3 border-bottom d-flex flex-wrap gap-2 align-items-center">
        <div class="table-search-box flex-grow-1" style="max-width: 360px">
          <i class="bi bi-search table-search-icon"></i>
          <input v-model="filters.q" class="table-search-input" placeholder="Nom, téléphone, e-mail…" />
        </div>
        <select v-model="filters.role" class="form-select form-select-sm" style="width: auto">
          <option value="">Tous les profils</option>
          <option value="passenger">Passagers uniquement</option>
          <option value="driver">Chauffeurs</option>
          <option value="admin">Administrateurs</option>
        </select>
        <select v-model="filters.status" class="form-select form-select-sm" style="width: auto">
          <option value="">Actifs et suspendus</option>
          <option value="active">Actifs</option>
          <option value="suspended">Suspendus</option>
        </select>
        <span v-if="loading" class="spinner-border spinner-border-sm ms-auto"></span>
      </div>
      <div v-if="error" class="alert alert-danger m-3">{{ error }}</div>
      <div class="table-responsive">
        <table class="table-custom align-middle">
          <thead>
            <tr>
              <th>Utilisateur</th>
              <th>Contact</th>
              <th>Profil</th>
              <th>Courses</th>
              <th>Note</th>
              <th>Statut</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="u in items" :key="u.id" class="cursor-pointer" @click="detail.open('user', u.id)">
              <td>
                <div class="table-user-cell">
                  <img v-if="u.photoUrl" :src="u.photoUrl" class="table-user-avatar" alt="" />
                  <span v-else class="table-user-avatar d-inline-flex align-items-center justify-content-center bg-lime-accent fw-bold">
                    {{ (u.firstName || '?').charAt(0) }}
                  </span>
                  <div>
                    <div class="table-user-name">{{ u.fullname || 'Sans nom' }}</div>
                    <div class="table-user-sub">inscrit le {{ dateOnly(u.createdAt) }}</div>
                  </div>
                </div>
              </td>
              <td class="small">
                {{ u.phoneNumber || '—' }}
                <div class="text-xs text-muted">{{ u.email }}</div>
              </td>
              <td>
                <span v-if="u.role === 'admin'" class="badge bg-warning text-dark">Admin</span>
                <span v-else-if="u.isDriver" class="badge bg-info text-dark">Chauffeur</span>
                <span v-else class="badge bg-light text-dark border">Passager</span>
              </td>
              <td>{{ u.ridesCount }}</td>
              <td class="small">{{ u.rating?.toFixed(1) }} <i class="bi bi-star-fill text-warning"></i></td>
              <td>
                <span class="badge-table" :class="u.isActive ? 'success' : 'failed'">
                  {{ u.isActive ? 'Actif' : 'Suspendu' }}
                </span>
              </td>
            </tr>
            <tr v-if="!items.length && !loading">
              <td colspan="6" class="text-center text-muted py-5">Aucun utilisateur.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationBar :pagination="pagination" @change="goTo" />
    </div>
  </div>
</template>
