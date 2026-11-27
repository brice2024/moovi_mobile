<script setup>
import { ref } from 'vue'
import { get, patch, post } from '../services/api'
import { useToastStore } from '../stores/toast'
import { dateOnly, money, parseDate } from '../utils/format'

const toast = useToastStore()
const codes = ref([])
const loading = ref(true)
const busy = ref(false)
const form = ref({ code: '', discountAmount: 500, maxUses: '', expiresAt: '' })

async function load() {
  loading.value = true
  try {
    codes.value = (await get('/api/admin/promo-codes')).promoCodes
  } catch (e) {
    toast.error(e.message)
  } finally {
    loading.value = false
  }
}
load()

async function create() {
  busy.value = true
  try {
    await post('/api/admin/promo-codes', {
      code: form.value.code.trim().toUpperCase(),
      discountAmount: Number(form.value.discountAmount),
      maxUses: form.value.maxUses ? Number(form.value.maxUses) : null,
      expiresAt: form.value.expiresAt ? `${form.value.expiresAt}T23:59:59` : null,
    })
    toast.success('Code promo créé.')
    form.value = { code: '', discountAmount: 500, maxUses: '', expiresAt: '' }
    load()
  } catch (e) {
    toast.error(e.message)
  } finally {
    busy.value = false
  }
}

async function toggle(code) {
  try {
    await patch(`/api/admin/promo-codes/${code.id}`, { isActive: !code.isActive })
    toast.success(code.isActive ? 'Code désactivé.' : 'Code réactivé.')
    load()
  } catch (e) {
    toast.error(e.message)
  }
}

const expired = (c) => c.expiresAt && parseDate(c.expiresAt) < new Date()
const exhausted = (c) => c.maxUses != null && c.usedCount >= c.maxUses
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Codes promo</h1>
        <p class="page-subtitle">
          Réduction en FCFA sur une course, une fois par passager. La réduction est payée par Moovi au chauffeur.
        </p>
      </div>
    </div>

    <div class="row g-3">
      <div class="col-lg-4">
        <form class="card p-3" @submit.prevent="create">
          <h6 class="fw-bold">Nouveau code</h6>
          <label class="form-label small mb-1">Code</label>
          <input
            v-model="form.code"
            class="form-control mb-2 text-uppercase"
            placeholder="BIENVENUE"
            required
            maxlength="40"
            pattern="\S+"
            title="Sans espace"
          />
          <label class="form-label small mb-1">Réduction (FCFA)</label>
          <input v-model="form.discountAmount" type="number" min="1" class="form-control mb-2" required />
          <label class="form-label small mb-1">Nombre d'utilisations maximum (vide = illimité)</label>
          <input v-model="form.maxUses" type="number" min="1" class="form-control mb-2" />
          <label class="form-label small mb-1">Expire le (facultatif)</label>
          <input v-model="form.expiresAt" type="date" class="form-control mb-3" />
          <button class="btn btn-dark w-100" :disabled="busy">Créer le code</button>
        </form>
      </div>

      <div class="col-lg-8">
        <div class="table-card-custom">
          <div class="table-responsive">
            <table class="table-custom align-middle">
              <thead>
                <tr>
                  <th>Code</th>
                  <th>Réduction</th>
                  <th>Utilisations</th>
                  <th>Expiration</th>
                  <th>Statut</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="c in codes" :key="c.id">
                  <td class="mono fw-bold">{{ c.code }}</td>
                  <td>{{ money(c.discountAmount) }}</td>
                  <td>{{ c.usedCount }}{{ c.maxUses != null ? ` / ${c.maxUses}` : '' }}</td>
                  <td class="small">{{ c.expiresAt ? dateOnly(c.expiresAt) : '—' }}</td>
                  <td>
                    <span v-if="!c.isActive" class="badge-table neutral">Désactivé</span>
                    <span v-else-if="expired(c)" class="badge-table failed">Expiré</span>
                    <span v-else-if="exhausted(c)" class="badge-table pending">Épuisé</span>
                    <span v-else class="badge-table success">Actif</span>
                  </td>
                  <td class="text-end">
                    <button class="btn btn-sm" :class="c.isActive ? 'btn-outline-danger' : 'btn-outline-success'" @click="toggle(c)">
                      {{ c.isActive ? 'Désactiver' : 'Réactiver' }}
                    </button>
                  </td>
                </tr>
                <tr v-if="!codes.length && !loading">
                  <td colspan="6" class="text-center text-muted py-5">Aucun code promo.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
