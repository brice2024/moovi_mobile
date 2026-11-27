<script setup>
import { computed, ref } from 'vue'
import { API_URL, api, get } from '../services/api'
import { useToastStore } from '../stores/toast'
import { money } from '../utils/format'

const toast = useToastStore()
const settings = ref(null)
const health = ref(null)

async function load() {
  try {
    settings.value = await get('/api/admin/settings')
  } catch (e) {
    toast.error(e.message)
  }
  try {
    health.value = await api('GET', '/api/health', { auth: false })
  } catch (e) {
    health.value = { error: e.message }
  }
}
load()

const rows = computed(() => {
  const s = settings.value
  if (!s) return []
  return [
    ['Environnement', s.environment, 'APP_ENV'],
    ['Commission Moovi', `${Math.round(s.commissionRate * 100)} %`, 'COMMISSION_RATE'],
    ['Prix minimum / maximum', `${money(s.minRidePrice)} – ${money(s.maxRidePrice)}`, 'MIN_RIDE_PRICE / MAX_RIDE_PRICE'],
    ['Pas de prix', money(s.priceStep), 'PRICE_STEP'],
    ['Rayon de recherche', `${s.searchRadiusKm} km`, 'DEFAULT_SEARCH_RADIUS_KM'],
    ['Expiration d’une recherche', `${Math.round(s.rideSearchTimeoutSeconds / 60)} min`, 'RIDE_SEARCH_TIMEOUT_SECONDS'],
    ['Chauffeur sans signal mis hors ligne après', `${s.driverDisconnectGraceSeconds} s`, 'DRIVER_DISCONNECT_GRACE_SECONDS'],
    ['Solde offert aux nouveaux chauffeurs', money(s.defaultWalletBalance), 'DEFAULT_WALLET_BALANCE'],
    ['Réduction 1re course', money(s.promoDiscount), 'PROMO_DISCOUNT_XAF'],
    ['Bonus de parrainage', money(s.referralReward), 'REFERRAL_REWARD_XAF'],
    ['Validation des chauffeurs obligatoire', s.requireDriverVerification ? 'Oui' : 'Non', 'REQUIRE_DRIVER_VERIFICATION'],
    ['Envoi des codes OTP', s.otpProvider, 'SMS_PROVIDER'],
    ['PawaPay', s.pawapayEnvironment, 'PAWAPAY_PRODUCTION / PAWAPAY_SIMULATE'],
    ['Webhook PawaPay signé', s.pawapayWebhookSigned ? 'Oui' : 'Non (statuts revérifiés auprès de PawaPay)', 'PAWAPAY_WEBHOOK_SECRET'],
  ]
})
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <h1 class="page-title">Paramètres</h1>
        <p class="page-subtitle">
          Configuration en vigueur. Ces valeurs se modifient dans le fichier <code>.env</code> de l'API, puis au
          redémarrage du serveur.
        </p>
      </div>
    </div>

    <div class="row g-3">
      <div class="col-xl-8">
        <div class="table-card-custom">
          <div class="table-responsive">
            <table class="table-custom align-middle">
              <thead>
                <tr><th>Réglage</th><th>Valeur</th><th>Variable</th></tr>
              </thead>
              <tbody>
                <tr v-for="[name, value, key] in rows" :key="key">
                  <td>{{ name }}</td>
                  <td class="fw-semibold">{{ value }}</td>
                  <td class="mono text-xs text-muted">{{ key }}</td>
                </tr>
                <tr v-if="!rows.length"><td colspan="3" class="text-center py-4"><span class="spinner-border spinner-border-sm"></span></td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="col-xl-4">
        <div class="card p-3 mb-3">
          <h6 class="fw-bold">Serveur</h6>
          <div class="small">Adresse de l'API : <span class="mono">{{ API_URL }}</span></div>
          <div v-if="health && !health.error" class="small mt-1">
            <span class="badge bg-success">En service</span>
            <span class="ms-1">Base de données : {{ health.database || health.db || 'ok' }}</span>
          </div>
          <div v-else-if="health?.error" class="small text-danger mt-1">{{ health.error }}</div>
          <a :href="`${API_URL}/api/docs`" target="_blank" rel="noopener" class="btn btn-sm btn-outline-dark mt-2">
            Documentation de l'API
          </a>
        </div>

        <div v-if="settings" class="card p-3 mb-3">
          <h6 class="fw-bold">Paiement Mobile Money (PawaPay)</h6>
          <div v-for="c in settings.paymentCountries" :key="c.code" class="small mb-1">
            <strong>{{ c.name }}</strong> : {{ c.operators.join(', ') }}
          </div>
        </div>

        <div v-if="settings" class="card p-3">
          <h6 class="fw-bold">Contacts affichés dans l'écran Assistance</h6>
          <div class="small">Téléphone : {{ settings.support.phone || '—' }}</div>
          <div class="small">WhatsApp : {{ settings.support.whatsapp || '—' }}</div>
          <div class="small">E-mail : {{ settings.support.email || '—' }}</div>
          <p v-if="!settings.support.phone && !settings.support.whatsapp && !settings.support.email" class="text-xs text-warning mt-2 mb-0">
            Aucun contact : renseignez SUPPORT_PHONE, SUPPORT_WHATSAPP ou SUPPORT_EMAIL dans le .env.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
