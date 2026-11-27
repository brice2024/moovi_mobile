// Connexion Socket.IO du back-office (positions des chauffeurs en direct).
import { io } from 'socket.io-client'
import { API_URL, getSession } from './api'

let socket = null
let users = 0

/** Ouvre (ou réutilise) la connexion ; à refermer avec `release()`. */
export function acquireSocket() {
  users++
  if (!socket) {
    socket = io(API_URL, {
      transports: ['websocket', 'polling'],
      // Jeton relu à chaque (re)connexion : il peut avoir été renouvelé.
      auth: (cb) => cb({ token: getSession()?.accessToken }),
      reconnectionDelayMax: 10000,
    })
  }
  return socket
}

export function releaseSocket() {
  users = Math.max(0, users - 1)
  if (users === 0 && socket) {
    socket.disconnect()
    socket = null
  }
}
