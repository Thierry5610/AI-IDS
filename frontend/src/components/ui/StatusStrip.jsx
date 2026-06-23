/**
 * StatusStrip — connector line passes through icon centres.
 * Line is drawn only in the gaps between circles (.sstrip-cell::after), so no
 * segment sits behind a circle. svg width/height are set as ATTRIBUTES too, so
 * icons can never blow up even if the stylesheet fails to load.
 */
import { MODELS } from '../../constants/models'

const ICONS = {
  sensor: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  inference: '<circle cx="12" cy="12" r="2.8"/><circle cx="12" cy="4.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="4.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="19.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="12" cy="19.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="6.2" cy="6.2" r="1.5" fill="currentColor" stroke="none"/><circle cx="17.8" cy="17.8" r="1.5" fill="currentColor" stroke="none"/><line x1="12" y1="7.6" x2="12" y2="9.2"/><line x1="7.6" y1="12" x2="9.2" y2="12"/><line x1="14.8" y1="12" x2="16.4" y2="12"/><line x1="12" y1="14.8" x2="12" y2="16.4"/><line x1="7.7" y1="7.7" x2="10" y2="10"/><line x1="14" y1="14" x2="16.3" y2="16.3"/>',
  bridge:   '<line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>',
  redis:    '<path d="M7 17a4 4 0 010-8 5 5 0 019.6-1.5A4.5 4.5 0 0117 17H7z"/>',
}

const SERVICES = [
  { key: 'sensor',    label: 'Sensor',    icon: ICONS.sensor,    color: 'var(--lime)'   },
  { key: 'inference', label: 'Inference', icon: ICONS.inference, color: 'var(--cyan)'   },
  { key: 'bridge',    label: 'Bridge',    icon: ICONS.bridge,    color: 'var(--violet)' },
  { key: 'redis',     label: 'Redis',     icon: ICONS.redis,     color: 'var(--amber)'  },
]

function Cell({ icon, color, label }) {
  return (
    <div className="sstrip-cell">
      <span className="sstrip-icon" style={{ color }}>
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
             strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
             dangerouslySetInnerHTML={{ __html: icon }} />
      </span>
      <span className="sstrip-label">{label}</span>
    </div>
  )
}

export default function StatusStrip() {
  return (
    <div className="sstrip">
      <div className="sstrip-rail">
        {SERVICES.map(s => (
          <Cell key={s.key} icon={s.icon} color={s.color} label={s.label} />
        ))}
        <div className="sstrip-cell">
          <span className="sstrip-more">+{MODELS.length}</span>
          <span className="sstrip-label">Models</span>
        </div>
      </div>

      <div className="sstrip-models">
        {MODELS.map(m => (
          <div key={m.id} className="sstrip-model">
            <span className="sstrip-model-dot" style={{ background: m.color }} />
            <span className="sstrip-model-name">{m.label}</span>
            <span className="sstrip-model-stat">loaded</span>
          </div>
        ))}
      </div>
    </div>
  )
}
