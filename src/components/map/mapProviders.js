// Carte OpenStreetMap (Leaflet) pour le suivi des chauffeurs en temps réel.
//
// Interface commune :
//   upsert(id, { lat, lng, html, onClick })  crée ou déplace un marqueur (animé)
//   remove(id) · openPopup(id, html) · closePopup()
//   fit(points) · focus(lat, lng, zoom) · destroy()

const ANIMATION_MS = 900

function animate(from, to, apply) {
  const start = performance.now()
  const step = (now) => {
    const t = Math.min(1, (now - start) / ANIMATION_MS)
    const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2
    apply(from.lat + (to.lat - from.lat) * e, from.lng + (to.lng - from.lng) * e)
    if (t < 1) return requestAnimationFrame(step)
  }
  return requestAnimationFrame(step)
}

// ── OpenStreetMap (Leaflet) ─────────────────────────────────────────────

export async function createOsmProvider(el, { center, zoom, onMapClick }) {
  const [{ default: L }] = await Promise.all([import('leaflet'), import('leaflet/dist/leaflet.css')])
  const map = L.map(el).setView(center, zoom)
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; contributeurs OpenStreetMap',
  }).addTo(map)
  map.on('click', () => onMapClick?.())
  const markers = new Map()
  let popupId = null
  const popup = L.popup({ offset: [0, -14] })

  const iconFor = (html) =>
    L.divIcon({ className: 'driver-marker', html, iconSize: [34, 34], iconAnchor: [17, 17] })

  return {
    kind: 'osm',
    upsert(id, { lat, lng, html, onClick }) {
      const existing = markers.get(id)
      if (!existing) {
        const marker = L.marker([lat, lng], { icon: iconFor(html) }).addTo(map)
        marker.on('click', () => onClick?.())
        marker.mooviHtml = html
        markers.set(id, marker)
        return
      }
      if (existing.mooviHtml !== html) {
        existing.setIcon(iconFor(html))
        existing.mooviHtml = html
      }
      const from = existing.getLatLng()
      if (from.lat !== lat || from.lng !== lng) {
        cancelAnimationFrame(existing.anim)
        existing.anim = animate({ lat: from.lat, lng: from.lng }, { lat, lng }, (a, b) => {
          existing.setLatLng([a, b])
          if (popupId === id) popup.setLatLng([a, b])
        })
      }
    },
    remove(id) {
      markers.get(id)?.remove()
      markers.delete(id)
      if (popupId === id) map.closePopup()
    },
    openPopup(id, html) {
      const m = markers.get(id)
      if (!m) return
      popupId = id
      popup.setLatLng(m.getLatLng()).setContent(html).openOn(map)
    },
    refreshPopup(id, html) {
      if (popupId === id && map.hasLayer(popup)) popup.setContent(html)
    },
    closePopup() {
      map.closePopup()
    },
    fit(points) {
      if (!points.length) return map.setView(center, zoom)
      if (points.length === 1) return map.setView(points[0], 15)
      map.fitBounds(L.latLngBounds(points), { padding: [40, 40], maxZoom: 15 })
    },
    focus(lat, lng, z = 15) {
      map.flyTo([lat, lng], Math.max(map.getZoom(), z), { duration: 0.6 })
    },
    destroy() {
      map.remove()
      markers.clear()
    },
  }
}
