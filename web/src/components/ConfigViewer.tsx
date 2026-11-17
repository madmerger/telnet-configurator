import { useEffect, useMemo, useState } from 'react'
import { api, formatTs, type Config, type Snapshot, type StoredDevice } from '../api'

interface Props {
  device: string | null
  onDeviceChange: (device: string) => void
  revision: number
}

export default function ConfigViewer({ device, onDeviceChange, revision }: Props) {
  const [stored, setStored] = useState<StoredDevice[]>([])
  const [snapshots, setSnapshots] = useState<Snapshot[]>([])
  const [snapshot, setSnapshot] = useState('latest')
  const [config, setConfig] = useState<Config | null>(null)
  const [section, setSection] = useState<string>('')
  const [filter, setFilter] = useState('')
  const [log, setLog] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .storedDevices()
      .then((list) => {
        setStored(list)
        if (!device && list.length) onDeviceChange(list[0].device)
      })
      .catch((e: Error) => setError(e.message))
  }, [revision]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!device) return
    setSnapshot('latest')
    setLog(null)
    api
      .snapshots(device)
      .then(setSnapshots)
      .catch((e: Error) => setError(e.message))
  }, [device, revision])

  useEffect(() => {
    if (!device) return
    setError(null)
    api
      .config(device, snapshot)
      .then((c) => {
        setConfig(c)
        setSection((cur) => (c.sections.some((s) => s.command === cur) ? cur : ''))
      })
      .catch((e: Error) => {
        setConfig(null)
        setError(e.message)
      })
  }, [device, snapshot, revision])

  const shown = useMemo(() => {
    if (!config) return []
    const sections = section ? config.sections.filter((s) => s.command === section) : config.sections
    const needle = filter.toLowerCase()
    return sections.map((s) => ({
      command: s.command,
      lines: s.output
        .replace(/\n$/, '')
        .split('\n')
        .map((text, i) => ({ no: i + 1, text }))
        .filter((l) => !needle || l.text.toLowerCase().includes(needle)),
    }))
  }, [config, section, filter])

  const toggleLog = () => {
    if (log !== null || !device) return setLog(null)
    api
      .sessionLog(device)
      .then(setLog)
      .catch((e: Error) => setLog(`(${e.message})`))
  }

  if (!stored.length && !error)
    return (
      <section className="panel">
        <p className="muted">まだ収集されたコンフィグがありません。「デバイス・収集」タブで接続して収集してください。</p>
      </section>
    )

  return (
    <section className="panel">
      <div className="panel-head">
        <h2>コンフィグ確認</h2>
        <div className="actions">
          <label>
            装置
            <select value={device ?? ''} onChange={(e) => onDeviceChange(e.target.value)}>
              {stored.map((s) => (
                <option key={s.device} value={s.device}>
                  {s.device}
                </option>
              ))}
            </select>
          </label>
          <label>
            収集日時
            <select value={snapshot} onChange={(e) => setSnapshot(e.target.value)}>
              <option value="latest">最新 ({formatTs(snapshots[0]?.id)})</option>
              {snapshots.map((s) => (
                <option key={s.id} value={s.id}>
                  {formatTs(s.id)} ({s.lines} 行)
                </option>
              ))}
            </select>
          </label>
          {device && (
            <a className="button" href={api.rawUrl(device, snapshot)} download>
              ダウンロード
            </a>
          )}
          <button onClick={toggleLog} disabled={!device}>
            {log === null ? 'セッションログ' : 'ログを閉じる'}
          </button>
        </div>
      </div>

      {error && <div className="error">{error}</div>}

      {config && (
        <>
          <div className="config-meta">
            <span className="mono strong">{config.device}</span>
            <span>収集: {formatTs(config.collected_at)}</span>
            <span>{config.lines} 行</span>
          </div>
          <div className="toolbar">
            <div className="chips">
              <button className={section === '' ? 'chip active' : 'chip'} onClick={() => setSection('')}>
                すべて
              </button>
              {config.sections.map((s) => (
                <button
                  key={s.command}
                  className={section === s.command ? 'chip active' : 'chip'}
                  onClick={() => setSection(s.command)}
                >
                  {s.command} <span className="muted">{s.lines}</span>
                </button>
              ))}
            </div>
            <input
              className="search"
              type="search"
              placeholder="行を検索"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            />
          </div>
          {log !== null && (
            <div className="log">
              <h3>セッションログ (パスワードはマスク済み)</h3>
              <pre>{log}</pre>
            </div>
          )}
          {shown.map((s) => (
            <div key={s.command} className="config-section">
              <h3 className="mono">{s.command}</h3>
              <table className="code">
                <tbody>
                  {s.lines.map((l) => (
                    <tr key={l.no}>
                      <td className="ln">{l.no}</td>
                      <td className="txt">{l.text || ' '}</td>
                    </tr>
                  ))}
                  {!s.lines.length && (
                    <tr>
                      <td className="ln"></td>
                      <td className="txt muted">一致する行がありません</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          ))}
        </>
      )}
    </section>
  )
}
