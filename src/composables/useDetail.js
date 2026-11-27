import { ref } from 'vue'

// Fiche ouverte (chauffeur, course ou utilisateur), partagée par tous les écrans.
const current = ref(null)
// Incrémenté après une action dans une fiche : les listes se rechargent.
const changes = ref(0)

export function useDetail() {
  return {
    current,
    changes,
    notifyChanged() {
      changes.value++
    },
    open(kind, id, extra = {}) {
      if (id) current.value = { kind, id, ...extra }
    },
    close() {
      current.value = null
    },
  }
}
