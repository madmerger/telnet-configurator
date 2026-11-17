import { useEffect, useState } from 'react'
import { api, type Inventory } from './api'
import DevicesPanel from './components/DevicesPanel'
import ConfigViewer from './components/ConfigViewer'
import ComparePanel from './components/ComparePanel'

type Tab = 'devices' | 'config' | 'compare'

const TABS: { id: Tab; label: string }[] = [
  { id: 'devices', label: 'デバイス・収集' },
  { id: 'config', label: 'コンフィグ確認' },
  { id: 'compare', label: 'コンフィグ比較' },
]

export default function App() {
  const [tab, setTab] = useState<Tab>('devices')
  const [inventories, setInventories] = useState<Inventory[]>([])
  const [inventory, setInventory] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [viewDevice, setViewDevice] = useState<string | null>(null)
  const [compareDevices, setCompareDevices] = useState<string[]>([])
  // bumped after every collection so the other tabs reload their lists
  const [revision, setRevision] = useState(0)

  useEffect(() => {
    api
      .inventories()
      .then((list) => {
        setInventories(list)
        const preferred = list.find((i) => i.name === 'devices.local.conf') ?? list[0]
        if (preferred) setInventory(preferred.name)
      })
      .catch((e: Error) => setError(e.message))
  }, [])

  const openConfig = (device: string) => {
    setViewDevice(device)
    setTab('config')
  }
  const openCompare = (devices: string[]) => {
    setCompareDevices(devices)
    setTab('compare')
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1>CBT コンフィグ収集</h1>
        <nav className="tabs">
          {TABS.map((t) => (
            <button key={t.id} className={tab === t.id ? 'tab active' : 'tab'} onClick={() => setTab(t.id)}>
              {t.label}
            </button>
          ))}
        </nav>
        <label className="inventory-select">
          インベントリ
          <select value={inventory} onChange={(e) => setInventory(e.target.value)}>
            {inventories.map((i) => (
              <option key={i.name} value={i.name} title={i.description}>
                {i.name}
              </option>
            ))}
          </select>
        </label>
      </header>
      {error && <div className="error banner">{error}</div>}
      <main>
        <div hidden={tab !== 'devices'}>
          <DevicesPanel
            inventory={inventory}
            description={inventories.find((i) => i.name === inventory)?.description ?? ''}
            onCollected={() => setRevision((r) => r + 1)}
            onView={openConfig}
            onCompare={openCompare}
          />
        </div>
        {tab === 'config' && <ConfigViewer device={viewDevice} onDeviceChange={setViewDevice} revision={revision} />}
        {tab === 'compare' && <ComparePanel initialDevices={compareDevices} revision={revision} />}
      </main>
    </div>
  )
}
