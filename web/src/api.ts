export interface Inventory {
  name: string
  description: string
}

export interface Device {
  name: string
  host: string
  port: number
  model: string
  sw: string
  protocol: 'telnet' | 'ssh'
  user?: string
  auth?: 'password' | 'publickey'
  host_key_check?: string
  key_file?: string
  has_password: boolean
  has_enable_password: boolean
  collector: string | null
  snapshots: number
  latest: string | null
}

export interface CollectResult {
  name: string
  ok: boolean
  snapshot: string | null
  lines: number
  error: string | null
  seconds: number
}

export interface StoredDevice {
  device: string
  snapshots: number
  latest: string | null
}

export interface Snapshot {
  id: string
  ts: string
  lines: number
  size: number
}

export interface Section {
  command: string
  output: string
  lines: number
}

export interface Config {
  device: string
  snapshot: string
  collected_at: string | null
  header: string | null
  lines: number
  sections: Section[]
}

export type RowType = 'eq' | 'chg' | 'del' | 'add'

export interface DiffRow {
  t: RowType
  l: number | null
  lt: string | null
  r: number | null
  rt: string | null
}

export interface SectionDiff {
  command: string
  status: 'equal' | 'changed' | 'only_base' | 'only_target'
  added: number
  removed: number
  rows: DiffRow[]
}

export interface TargetDiff {
  key: string
  identical: boolean
  added: number
  removed: number
  sections: SectionDiff[]
}

export interface CompareItem {
  key: string
  device: string
  snapshot: string
}

export interface CompareResult {
  base: string
  items: CompareItem[]
  commands: string[]
  matrix: Record<string, Record<string, number | null>>
  diffs: TargetDiff[]
}

export interface CompareRequest {
  items: { device: string; snapshot: string }[]
  base: number
  mask_hostname: boolean
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: init?.body ? { 'Content-Type': 'application/json' } : undefined,
  })
  const type = res.headers.get('Content-Type') ?? ''
  const body = type.includes('application/json') ? await res.json() : await res.text()
  if (!res.ok) {
    const msg = typeof body === 'object' && body && 'error' in body ? String(body.error) : `${res.status} ${res.statusText}`
    throw new Error(msg)
  }
  return body as T
}

const post = <T,>(path: string, body: unknown) => request<T>(path, { method: 'POST', body: JSON.stringify(body) })
const enc = encodeURIComponent

export const api = {
  inventories: () => request<Inventory[]>('/api/inventories'),
  devices: (inventory: string) => request<Device[]>(`/api/devices?inventory=${enc(inventory)}`),
  collect: (body: { inventory: string; devices: string[]; password?: string; enable_password?: string }) =>
    post<{ results: CollectResult[]; ok: number; total: number }>('/api/collect', body),
  storedDevices: () => request<StoredDevice[]>('/api/configs'),
  snapshots: (device: string) => request<Snapshot[]>(`/api/configs/${enc(device)}`),
  config: (device: string, snapshot = 'latest') => request<Config>(`/api/configs/${enc(device)}/${enc(snapshot)}`),
  rawUrl: (device: string, snapshot = 'latest') => `/api/configs/${enc(device)}/${enc(snapshot)}/raw`,
  sessionLog: (device: string) => request<string>(`/api/logs/${enc(device)}`),
  compare: (body: CompareRequest) => post<CompareResult>('/api/compare', body),
}

/** 20261117-180330 -> 2026-11-17 18:03:30 */
export function formatTs(ts: string | null | undefined): string {
  if (!ts) return '—'
  const m = /^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})$/.exec(ts)
  return m ? `${m[1]}-${m[2]}-${m[3]} ${m[4]}:${m[5]}:${m[6]}` : ts
}
