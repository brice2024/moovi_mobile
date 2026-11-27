<script setup>
import { ref } from 'vue'
import { get, post } from '../services/api'
import { useToastStore } from '../stores/toast'
import { dateTime } from '../utils/format'

const toast = useToastStore()
const history = ref([])
const busy = ref(false)
const form = ref({ audience: 'all', title: '', body: '' })

const AUDIENCES = {
  all: 'Tous les utilisateurs',
  passengers: 'Passagers (non chauffeurs)',
  drivers: 'Tous les chauffeurs',
  online_drivers: 'Chauffeurs en ligne',
}

async function load() {
  try {
    history.value = (await get('/api/admin/notifications')).notifications
  } catch (e) {
    toast.error(e.message)
  }
}
load()

async function send() {
  if (!window.confirm(`Envoyer cette notification à : ${AUDIENCES[form.value.audience]} ?`)) return
  busy.value = true
  try {
    const res = await post('/api/admin/notifications', form.value)
    toast.success(`Notification envoyée à ${res.sent} utilisateur(s).`)
    form.value = { audience: form.value.audience, title: '', body: '' }
    load()
  } catch (e) {
    toast.error(e.message)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Notifications</h1>
        <p class="page-subtitle">
          Message affiché dans l'application (bandeau et écran Notifications) et en notification système si
          l'application tourne en arrière-plan.
        </p>
      </div>
    </div>

    <div class="row g-3">
      <div class="col-lg-5">
        <form class="card p-3" @submit.prevent="send">
          <h6 class="fw-bold">Nouveau message</h6>
          <label class="form-label small mb-1">Destinataires</label>
          <select v-model="form.audience" class="form-select mb-2">
            <option v-for="(text, key) in AUDIENCES" :key="key" :value="key">{{ text }}</option>
          </select>
          <label class="form-label small mb-1">Titre</label>
          <input v-model="form.title" class="form-control mb-2" maxlength="140" required />
          <label class="form-label small mb-1">Message ({{ form.body.length }}/500)</label>
          <textarea v-model="form.body" class="form-control mb-3" rows="5" maxlength="500" required></textarea>
          <button class="btn btn-dark w-100" :disabled="busy">
            <i class="bi bi-send"></i> Envoyer
          </button>
          <p class="text-xs text-muted mt-2 mb-0">
            Pour écrire à une seule personne, ouvrez sa fiche dans Utilisateurs.
          </p>
        </form>
      </div>
      <div class="col-lg-7">
        <div class="table-card-custom">
          <div class="p-3 border-bottom"><h6 class="fw-bold mb-0">Derniers envois</h6></div>
          <div class="table-responsive">
            <table class="table-custom align-middle">
              <thead>
                <tr><th>Message</th><th>Destinataires</th><th>Envoyé le</th></tr>
              </thead>
              <tbody>
                <tr v-for="n in history" :key="`${n.title}-${n.sentAt}`">
                  <td>
                    <div class="fw-semibold">{{ n.title }}</div>
                    <div class="small text-muted">{{ n.body }}</div>
                  </td>
                  <td>{{ n.recipients }}</td>
                  <td class="text-xs">{{ dateTime(n.sentAt) }}</td>
                </tr>
                <tr v-if="!history.length">
                  <td colspan="3" class="text-center text-muted py-5">Aucun message envoyé.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
