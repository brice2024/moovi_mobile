// Formats et libellés partagés par les écrans du back-office.

export function money(value) {
  const n = Number(value || 0)
  return `${n.toLocaleString('fr-FR', { maximumFractionDigits: 0 })} FCFA`
}

export function number(value) {
  return Number(value || 0).toLocaleString('fr-FR')
}

/** Les dates de l'API sont en UTC sans fuseau : on les affiche à l'heure de Libreville. */
export function parseDate(value) {
  if (!value) return null
  const iso = /[zZ]|[+-]\d\d:\d\d$/.test(value) ? value : `${value}Z`
  const date = new Date(iso)
  return Number.isNaN(date.getTime()) ? null : date
}

export function dateTime(value) {
  const d = parseDate(value)
  return d
    ? d.toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : '—'
}

export function dateOnly(value) {
  const d = parseDate(value)
  return d ? d.toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'
}

export function timeAgo(value) {
  const d = parseDate(value)
  if (!d) return '—'
  const s = Math.round((Date.now() - d.getTime()) / 1000)
  if (s < 60) return "à l'instant"
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`
  if (s < 86400) return `il y a ${Math.floor(s / 3600)} h`
  return `il y a ${Math.floor(s / 86400)} j`
}

export function shortId(id) {
  return id ? String(id).slice(0, 8).toUpperCase() : '—'
}

// [libellé, classe de badge (success | pending | failed | neutral | info)]
export const RIDE_STATUS = {
  searching: ['Recherche', 'info'],
  accepted: ['Acceptée', 'info'],
  driver_arrived: ['Chauffeur arrivé', 'info'],
  in_progress: ['En cours', 'pending'],
  completed: ['Terminée', 'success'],
  cancelled: ['Annulée', 'failed'],
  expired: ['Expirée', 'neutral'],
}

export const VERIFICATION_STATUS = {
  approved: ['Validé', 'success'],
  verified: ['Validé', 'success'],
  pending: ['En attente', 'pending'],
  rejected: ['Refusé', 'failed'],
  missing: ['Manquant', 'neutral'],
}

export const PAYMENT_STATUS = {
  pending: ['En attente', 'pending'],
  completed: ['Payé', 'success'],
  failed: ['Échoué', 'failed'],
  duplicate: ['En double', 'failed'],
  refunded: ['Remboursé', 'neutral'],
}

export const PAYMENT_METHOD = {
  cash: 'Espèces',
  mobile_money: 'Mobile Money',
  moovi_promo: 'Offert (promo)',
}

export const VEHICLE_TYPE = { voiture: 'Voiture', moto: 'Moto', confort: 'Confort' }

export const TX_TYPE = {
  deposit: 'Recharge',
  commission: 'Commission',
  ride_payout: 'Reversement course',
  promo_subsidy: 'Subvention promo',
  adjustment: 'Ajustement',
}

export const TX_STATUS = {
  completed: ['Effectué', 'success'],
  pending: ['En attente', 'pending'],
  failed: ['Échoué', 'failed'],
}

export const DOC_LABELS = {
  license: 'Permis de conduire',
  registration: 'Carte grise',
  plate: "Plaque d'immatriculation",
  front: 'Photo avant',
  back: 'Photo arrière',
  left: 'Côté gauche',
  right: 'Côté droit',
  interior: 'Intérieur',
}

export function label(map, key) {
  const entry = map[key]
  return Array.isArray(entry) ? entry[0] : entry || key || '—'
}

export function tone(map, key) {
  const entry = map[key]
  return Array.isArray(entry) ? entry[1] : 'neutral'
}
