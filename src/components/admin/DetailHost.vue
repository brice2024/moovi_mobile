<script setup>
import DriverDetailModal from './DriverDetailModal.vue'
import RideDetailModal from './RideDetailModal.vue'
import UserDetailModal from './UserDetailModal.vue'
import { useDetail } from '../../composables/useDetail'

// Une seule fiche ouverte à la fois ; on peut naviguer d'une fiche à l'autre
// (course → chauffeur → courses du chauffeur…).
const detail = useDetail()
const emit = defineEmits(['changed'])
</script>

<template>
  <DriverDetailModal
    v-if="detail.current.value?.kind === 'driver'"
    :key="`d-${detail.current.value.id}`"
    :driver-id="detail.current.value.id"
    :initial-tab="detail.current.value.tab || 'file'"
    @close="detail.close()"
    @changed="emit('changed')"
    @open-ride="detail.open('ride', $event)"
  />
  <RideDetailModal
    v-else-if="detail.current.value?.kind === 'ride'"
    :key="`r-${detail.current.value.id}`"
    :ride-id="detail.current.value.id"
    @close="detail.close()"
    @changed="emit('changed')"
    @open-driver="detail.open('driver', $event)"
    @open-user="detail.open('user', $event)"
  />
  <UserDetailModal
    v-else-if="detail.current.value?.kind === 'user'"
    :key="`u-${detail.current.value.id}`"
    :user-id="detail.current.value.id"
    @close="detail.close()"
    @changed="emit('changed')"
    @open-ride="detail.open('ride', $event)"
    @open-driver="detail.open('driver', $event)"
  />
</template>
